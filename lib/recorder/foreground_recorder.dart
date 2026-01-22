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
      // start initial recording
      await _startRecordingSegment();
    } on CameraException catch (e) {
      debugPrint('Camera init error: $e');
    } catch (e) {
      debugPrint('Camera init unknown error: $e');
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
    if (!_consented ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized)
      return;
    if (_isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      _isRecording = true;
      recordingNotifier.value = true;
      _startSegmentTimer();
      debugPrint(
        'Started recording to segment (in-memory) — file will be saved on stop',
      );
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      _isRecording = false;
      recordingNotifier.value = false;
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
    if (!_isRecording || _cameraController == null) return;
    try {
      await _cameraController!.stopVideoRecording();
      // Don't save the clip here - only save when notifySegmentEnd() is called
      // This ensures clips are only saved when a video completes
    } catch (e) {
      debugPrint('Failed to stop recording segment: $e');
    }

    // Start next segment immediately
    _isRecording = false;
    recordingNotifier.value = false;
    _segmentTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 100));
    await _startRecordingSegment();
  }

  Future<void> _stopRecordingIfNeeded() async {
    _segmentTimer?.cancel();
    if (_isRecording && _cameraController != null) {
      try {
        final file = await _cameraController!.stopVideoRecording();
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
      } catch (e) {
        debugPrint('Error stopping recording: $e');
      }
      _isRecording = false;
      recordingNotifier.value = false;
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
  Future<void> notifySegmentEnd() async {
    if (!_isRecording) return;
    _segmentTimer?.cancel();

    try {
      final file = await _cameraController!.stopVideoRecording();
      // Save the clip only when video ends
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

      if (_currentVideoDocId != null && _currentVideoDocId!.isNotEmpty) {
        final newPath = '${dir.path}/${_currentVideoDocId}_$ts.mp4';
        try {
          final src = File(file.path);
          await src.copy(newPath);
          debugPrint('✓ Saved clip with docId at video end: $newPath');
        } catch (e) {
          debugPrint('✗ Failed to copy segment file: $e');
        }
      } else {
        debugPrint(
          '✗ Cannot save clip: docId is null or empty. Current docId: "$_currentVideoDocId"',
        );
      }
    } catch (e) {
      debugPrint('✗ Failed to save segment at video end: $e');
    }

    // Restart recording for next segment
    _isRecording = false;
    recordingNotifier.value = false;
    await Future.delayed(const Duration(milliseconds: 100));
    await _startRecordingSegment();
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
