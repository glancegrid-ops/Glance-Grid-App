import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// no flutter services required
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';

// Foreground-only recorder manager.
// Usage:
// - Call RecorderManager.instance.init(context) early (e.g., in main widget initState).
// - App will ask for permission + consent. Recording starts automatically when granted.
// - Call setSegmentDuration(Duration?) to set current segment length. When null, defaults to 10s.

class RecorderManager with WidgetsBindingObserver {
  RecorderManager._internal();
  static final RecorderManager instance = RecorderManager._internal();

  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  bool _isRecording = false;
  bool _consented = false;
  bool _initialized = false;
  bool _wasRecordingBeforePause = false;
  // The id of the currently playing video (from Firestore doc id). Used to
  // prefix saved clip filenames so they are associated with the video.
  String? _currentVideoDocId;

  // Add a lock to prevent concurrent camera operations
  bool _isProcessingCamera = false;

  // The last temporary segment file path returned by stopVideoRecording().
  // This is set when segments are rotated/stopped so notifySegmentEnd()
  // can save that file even if the camera is not currently recording.
  String? _lastSegmentTempPath;

  // Track if the first segment has been successfully saved.
  // Used to apply extended timeout on initial startup.
  bool _firstSegmentSaved = false;

  Duration? _segmentDuration;
  Timer? _segmentTimer;
  // Notifier for UI to show recording indicator
  final ValueNotifier<bool> recordingNotifier = ValueNotifier(false);
  // Notifier that user gave consent (persisted) — useful to gate playback.
  final ValueNotifier<bool> consentedNotifier = ValueNotifier(false);
  // Notifier that permissions are granted and recorder can start.
  final ValueNotifier<bool> readyNotifier = ValueNotifier(false);

  // Initialize: request permissions and consent, then start camera if allowed.
  Future<void> init(BuildContext context) async {
    if (_initialized) return;
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
    await _requestPermissionAndStart(context);
  }

  Future<void> disposeManager() async {
    WidgetsBinding.instance.removeObserver(this);
    await _stopRecordingIfNeeded();
    try {
      await _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
    try {
      recordingNotifier.dispose();
    } catch (_) {}
    try {
      consentedNotifier.dispose();
    } catch (_) {}
    try {
      readyNotifier.dispose();
    } catch (_) {}
    _initialized = false;
  }

  Future<void> _requestPermissionAndStart(BuildContext context) async {
    // Persisted consent: only show dialog once. When already consented,
    // skip the dialog. The dialog is non-dismissible and only has an
    // explicit "Allow" action so the user must accept to continue.
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool('recorder_user_consented') ?? false;

    if (!alreadyConsented) {
      if (!context.mounted) return;
      final consent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Recording Permission'),
          content: const Text(
            'This app will record video from the front camera while it is in the foreground. Files are saved to the device. Please tap Allow to consent.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (consent != true) {
        // If dialog was somehow dismissed (should not happen), treat as no consent.
        _consented = false;
        consentedNotifier.value = false;
        return;
      }

      await prefs.setBool('recorder_user_consented', true);
    }

    _consented = true;
    consentedNotifier.value = true;

    // Request runtime permissions (system dialogs). If permissions are
    // already granted, this will be quick. We set readyNotifier when both
    // camera and microphone are granted so the app can begin playback.
    final camStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;

    PermissionStatus camReq = camStatus;
    PermissionStatus micReq = micStatus;
    if (!camStatus.isGranted) camReq = await Permission.camera.request();
    if (!micStatus.isGranted) micReq = await Permission.microphone.request();

    if (!camReq.isGranted || !micReq.isGranted) {
      // Permissions not granted — recorder cannot start. We still set ready=false
      // so the UI can wait; the app will not start recording or playback until
      // permissions are granted.
      readyNotifier.value = false;
      return;
    }

    // Permissions granted — mark ready and attempt camera init/start.
    readyNotifier.value = true;

    // Start front camera and begin recording (best-effort; failures are logged).
    try {
      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.isNotEmpty
            ? cameras.first
            : throw Exception('No camera available'),
      );
      _cameraController = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      // Give encoder time to fully initialize on first startup (especially on older devices)
      await Future.delayed(const Duration(milliseconds: 500));
      // start initial recording
      await _startRecordingSegment();
    } on CameraException catch (e) {
      debugPrint('Camera init error: $e');
    } catch (e) {
      debugPrint('Camera init unknown error: $e');
    }
  }

  // Helper to restart camera on fatal errors
  Future<void> _restartCamera() async {
    // Force wait for lock to clear
    int retries = 0;
    while (_isProcessingCamera && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }
    _isProcessingCamera = true;

    debugPrint('♻ restarting camera subsystem...');
    try {
      if (_cameraController != null) {
        await _cameraController!.dispose();
      }
    } catch (e) {
      debugPrint('Error disposing camera during restart: $e');
    }
    _cameraController = null;
    _isRecording = false;
    recordingNotifier.value = false;
    _segmentTimer?.cancel();
    // Reset first segment flag so next init gets extended timeout
    _firstSegmentSaved = false;

    // Increased delay to 2000ms to allow hardware to fully reset
    await Future.delayed(const Duration(milliseconds: 2000));

    try {
      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.isNotEmpty
            ? cameras.first
            : throw Exception('No camera available'),
      );
      _cameraController = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
    } catch (e) {
      debugPrint('Fatal: Failed to restart camera: $e');
    } finally {
      _isProcessingCamera = false;
      // Start recording now that lock is free and controller is ready
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _startRecordingSegment();
      }
    }
  }

  // Set the segment duration; used to rotate saved files.
  void setSegmentDuration(Duration? dur) {
    _segmentDuration = dur;
    // restart timer to apply new duration on next tick
    if (_isRecording) {
      _segmentTimer?.cancel();
      // If a specific segment duration is provided, prefer end-of-ad rotation.
      // We still start a short fallback timer (duration + 5s) to avoid never-rotating.
      _startSegmentTimer();
    }
  }

  Future<void> _startRecordingSegment() async {
    // Wait for lock instead of returning immediately
    int retries = 0;
    while (_isProcessingCamera && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }

    if (_isProcessingCamera) {
      debugPrint(
        '⚠ _startRecordingSegment: Camera busy too long. Aborting start.',
      );
      return;
    }

    _isProcessingCamera = true;
    try {
      if (!_consented ||
          _cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }
      if (_isRecording) {
        // Already recording, fine.
        return;
      }

      // If the controller thinks it's already recording but our flag is false
      if (_cameraController!.value.isRecordingVideo) {
        _isRecording = true;
        recordingNotifier.value = true;
        _startSegmentTimer();
        debugPrint('Recovered recording state: Camera was already recording.');
        return;
      }

      try {
        await _cameraController!.startVideoRecording();
        _isRecording = true;
        recordingNotifier.value = true;
        _startSegmentTimer();
        debugPrint(
          'Started recording to segment (in-memory) — file will be saved on stop',
        );
      } catch (e) {
        if (e is CameraException &&
            e.description != null &&
            e.description!.contains('already started')) {
          debugPrint(
            'Caught "already started" exception. Treating as recording.',
          );
          _isRecording = true;
          recordingNotifier.value = true;
          _startSegmentTimer();
        } else {
          debugPrint('Failed to start recording: $e');
          _isRecording = false;
          recordingNotifier.value = false;
          // Try to restart if it's a serious error
          if (e is CameraException) {
            debugPrint('Fatal error starting recording. Scheduling restart.');
            // Schedule restart after lock release
            Future.delayed(const Duration(milliseconds: 500), _restartCamera);
          }
        }
      }
    } finally {
      _isProcessingCamera = false;
    }
  }

  void _startSegmentTimer() {
    final dur = _segmentDuration ?? const Duration(seconds: 10);
    if (_segmentDuration == null) {
      // Default behavior: rotate on strict timer when no external ad-duration provided.
      _segmentTimer = Timer(dur, () async {
        await _rotateSegment();
      });
    } else {
      // When an external segment duration is provided (end-of-ad), prefer
      // rotating when the parent notifies end-of-ad. Start a fallback timer
      // to ensure we don't get stuck (duration + small slack).
      final fallback = dur + const Duration(seconds: 5);
      _segmentTimer = Timer(fallback, () async {
        await _rotateSegment();
      });
    }
  }

  Future<void> _rotateSegment() async {
    if (_isProcessingCamera)
      return; // Skip if busy (e.g. notifySegmentEnd running)
    _isProcessingCamera = true;
    try {
      if (!_isRecording || _cameraController == null) return;

      try {
        try {
          final tmp = await _cameraController!.stopVideoRecording().timeout(
            const Duration(seconds: 5),
          );
          // Record the temp path for potential later saving
          _lastSegmentTempPath = tmp.path;
          debugPrint(
            '✓ Rotation: Stopped segment. Temp: $_lastSegmentTempPath',
          );
        } on TimeoutException {
          debugPrint(
            '⚠ Rotation: stopVideoRecording timeout. Encoder draining...',
          );
        } catch (e) {
          debugPrint('Failed to stop recording segment: $e');
        }
        // Don't save the clip here - only save when notifySegmentEnd() is called
        // This ensures clips are only saved when a video completes
      } catch (e) {
        debugPrint('Failed during rotateSegment stop: $e');
      }

      // Start next segment immediately
      _isRecording = false;
      recordingNotifier.value = false;
      _segmentTimer?.cancel();
    } finally {
      _isProcessingCamera = false;

      // Increased delay to drain camera fully
      await Future.delayed(const Duration(milliseconds: 1000));
      await _startRecordingSegment();
    }
  }

  Future<void> _stopRecordingIfNeeded() async {
    // Wait for ongoing operations best effort
    if (_isProcessingCamera) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessingCamera = true;
    try {
      _segmentTimer?.cancel();
      if (_isRecording && _cameraController != null) {
        try {
          final file = await _cameraController!.stopVideoRecording().timeout(
            const Duration(seconds: 5),
          );
          // record the temp path so notifySegmentEnd can use it if needed
          _lastSegmentTempPath = file.path;

          // move to documents
          final dir = await getApplicationDocumentsDirectory();
          final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
          // Always save only if docId is available
          if (_currentVideoDocId != null && _currentVideoDocId!.isNotEmpty) {
            final newPath = '${dir.path}/${_currentVideoDocId}_$ts.mp4';
            try {
              final src = File(file.path);
              await src.copy(newPath);
              debugPrint('Saved final clip with docId: $newPath');
            } catch (e) {
              debugPrint('Failed to copy final segment file: $e');
            }
          }
        } on TimeoutException {
          debugPrint(
            '⚠ Graceful shutdown timeout. Encoder may still be draining.',
          );
        } catch (e) {
          debugPrint('Error stopping recording: $e');
        }
        _isRecording = false;
        recordingNotifier.value = false;
      }
    } finally {
      _isProcessingCamera = false;
    }
  }

  /// Set the current video doc id so saved clips get prefixed with it.
  /// Pass `null` to clear.
  void setCurrentVideoDocId(String? id) {
    if (id != _currentVideoDocId) {
      debugPrint(
        'RecorderManager: Setting docId from "$_currentVideoDocId" to "$id"',
      );
    }
    _currentVideoDocId = id;
  }

  // Called by parent when an ad/video finishes playing so the recorder can
  // save the segment as a clip.
  /// Save the most recent recording segment when a file finishes playing.
  ///
  /// If `docId` is provided it will be used; otherwise the recorder's
  /// `_currentVideoDocId` is used. Passing the docId from the UI avoids
  /// races where the UI's start event hasn't yet updated the recorder state.
  Future<void> notifySegmentEnd([String? docId]) async {
    final captureDocId = docId ?? _currentVideoDocId; // prefer passed docId

    // Wait for ongoing operations to complete (up to 2 seconds)
    int retries = 0;
    while (_isProcessingCamera && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }

    if (_isProcessingCamera) {
      debugPrint(
        '⚠ notifySegmentEnd: Camera busy too long. Skipping save to prevent crash.',
      );
      return;
    }

    _isProcessingCamera = true;
    try {
      // Check internal flag AND official controller state just in case
      final isActuallyRecording =
          _isRecording || (_cameraController?.value.isRecordingVideo ?? false);

      // If we're not currently recording, we may still have a recently
      // produced temporary segment (from rotation) at `_lastSegmentTempPath`.
      if (!isActuallyRecording && _lastSegmentTempPath == null) {
        debugPrint(
          '⚠ notifySegmentEnd called but not recording and no temp segment available. Skipping. (DocID: $captureDocId)',
        );
        return;
      }

      _segmentTimer?.cancel();

      try {
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

        String? tempPath;

        if (isActuallyRecording) {
          try {
            // Use extended timeout for first segment (encoder initialization);
            // after that, use standard 5s timeout since encoder is warmed up.
            final timeout = _firstSegmentSaved
                ? const Duration(seconds: 5)
                : const Duration(seconds: 12);

            debugPrint(
              'Stopping recording (timeout=${timeout.inSeconds}s, firstSegment=${!_firstSegmentSaved})',
            );

            final file = await _cameraController!.stopVideoRecording().timeout(
              timeout,
            );
            tempPath = file.path;
            // store for potential later use
            _lastSegmentTempPath = tempPath;
            _firstSegmentSaved = true; // mark first segment as saved
            debugPrint(
              '✓ Stopped recording successfully. Temp file: $tempPath',
            );
          } on TimeoutException {
            debugPrint(
              '⚠ stopVideoRecording timeout (encoder still draining). Attempting recovery...',
            );
            // For first segment, retry after a longer wait
            if (!_firstSegmentSaved) {
              debugPrint(
                '⚡ First segment timeout - waiting 3s for encoder to catch up...',
              );
              await Future.delayed(const Duration(seconds: 3));
              try {
                final retryFile = await _cameraController!.stopVideoRecording();
                tempPath = retryFile.path;
                _lastSegmentTempPath = tempPath;
                _firstSegmentSaved = true;
                debugPrint('✓ Retry successful! Got temp file: $tempPath');
              } catch (retryE) {
                debugPrint('⚠ Retry also failed: $retryE');
                tempPath = null;
              }
            } else {
              tempPath = null;
            }
          } catch (e) {
            debugPrint('✗ Failed to stop recording for save: $e');
            tempPath = null;
          }
        } else {
          tempPath = _lastSegmentTempPath;
        }

        if (tempPath != null && tempPath.isNotEmpty) {
          if (captureDocId != null && captureDocId.isNotEmpty) {
            final newPath = '${dir.path}/${captureDocId}_$ts.mp4';
            try {
              final src = File(tempPath);
              if (await src.exists()) {
                await src.copy(newPath);
                debugPrint('✓ Saved clip with docId: $newPath');
                // clear last temp after successful save
                try {
                  await src.delete();
                } catch (_) {}
                _lastSegmentTempPath = null;
              } else {
                debugPrint('✗ Temp segment file does not exist: $tempPath');
              }
            } catch (e) {
              debugPrint('✗ Failed to copy segment file: $e');
            }
          } else {
            debugPrint(
              '✗ Cannot save clip: docId is null or empty. (Captured: "$captureDocId")',
            );
          }
        } else {
          debugPrint('✗ No temp segment available to save.');
        }

        // Restart recording for next segment
        _isRecording = false;
        recordingNotifier.value = false;
      } on Exception {
        _isProcessingCamera = false;
        // Increase delay to 1000ms to give camera hardware time to drain/reset
        await Future.delayed(const Duration(milliseconds: 1000));
        await _startRecordingSegment();
      } catch (e) {
        debugPrint('Unexpected error in notifySegmentEnd: $e');
      }
    } catch (e) {
      debugPrint('Unexpected error in notifySegmentEnd: $e');
    } finally {
      // Ensure we release processing lock and resume recording loop.
      _isProcessingCamera = false;
      // Small delay to give camera hardware time to drain/reset
      await Future.delayed(const Duration(milliseconds: 1000));
      await _startRecordingSegment();
    }
  }

  /// Returns the saved clips directory path. Useful for building a UI button
  /// that opens the folder. This returns the application documents dir.
  Future<String> getSavedClipsDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// Attempts to open the saved clips folder using platform-appropriate
  /// mechanisms. Requires `open_file` package in pubspec.
  Future<void> openSavedClips() async {
    try {
      final path = await getSavedClipsDirectoryPath();
      await OpenFile.open(path);
    } catch (e) {
      debugPrint('Failed to open saved clips location: $e');
    }
  }

  /// Pause recording because the user navigated to another UI (e.g., clip browser).
  /// Records whether recording was active so it can be resumed later.
  Future<void> pauseRecordingForUi() async {
    if (!_consented) return;
    if (_isRecording) {
      _wasRecordingBeforePause = true;
      await _stopRecordingIfNeeded();
    } else {
      _wasRecordingBeforePause = false;
    }
  }

  /// Resume recording if it was active before the UI pause.
  Future<void> resumeRecordingAfterUi() async {
    if (!_consented) return;
    if (_wasRecordingBeforePause) {
      _wasRecordingBeforePause = false;
      await _startRecordingSegment();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_consented) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // app going to background — stop recording
      if (_isRecording) {
        _wasRecordingBeforePause = true;
        _stopRecordingIfNeeded();
      }
    } else if (state == AppLifecycleState.resumed) {
      // resume recording
      if (_wasRecordingBeforePause) {
        _wasRecordingBeforePause = false;
        _startRecordingSegment();
      }
    }
  }
}
