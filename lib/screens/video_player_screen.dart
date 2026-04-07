import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../widgets/adaptive_video_grid.dart';
import '../recorder/foreground_recorder.dart';
import '../services/video_service.dart';
import '../models/file_model.dart'; // Import FileModel for FileType enum
import '../services/device_id_service.dart';
import 'clip_browser.dart';
import '../helpers/ui_helpers.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // Items with path + docId
  List<Map<String, String>> _videoItems = [];
  bool _loading = true; // Start as loading
  bool _passwordValid = false;
  String? _currentVideoDocId; // Track docId directly

  @override
  void initState() {
    super.initState();
    _initScreenSettings();
    _videoItems = [];

    // Initialize things after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPassword();
      RecorderManager.instance.init(context);

      // Load videos when recorder is ready (or if already ready)
      RecorderManager.instance.readyNotifier.addListener(() {
        if (RecorderManager.instance.readyNotifier.value) {
          _loadVideos();
        }
      });

      if (RecorderManager.instance.readyNotifier.value) {
        _loadVideos();
      }
    });
  }

  Future<void> _initScreenSettings() async {
    try {
      await WakelockPlus.enable();
      await ScreenBrightness().setScreenBrightness(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    ScreenBrightness().resetScreenBrightness();
    super.dispose();
  }

  Future<void> _checkPassword() async {
    final isValid = await UiHelpers.showPasswordDialog(context);
    if (mounted) {
      setState(() {
        _passwordValid = isValid;
      });
    }
  }

  Future<void> _loadVideos() async {
    setState(() => _loading = true);
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();
      final videos = await VideoService.instance.fetchVideosForDevice(deviceId);

      final items = videos
          .map(
            (v) => {
              'path': v.url,
              'docId': v.docId ?? '',
              'type': v.type == FileType.image ? 'image' : 'video',
              'duration': v.duration.toString(),
            },
          )
          .toList();

      debugPrint('Loaded video items: $items');

      if (mounted) {
        setState(() {
          _videoItems = items;
          _loading = false;
        });

        if (items.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No videos found for this user')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paths = _videoItems.map((it) => it['path']!).toList(growable: false);

    return Scaffold(
      appBar: _passwordValid
          ? AppBar(
              title: const Text('Glance Grid - Video Player'),
              backgroundColor: Colors.white,
              elevation: 0,
              actions: [
                // Recording indicator
                ValueListenableBuilder<bool>(
                  valueListenable: RecorderManager.instance.recordingNotifier,
                  builder: (context, isRecording, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: isRecording
                          ? const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.red,
                            )
                          : const SizedBox(width: 24, height: 24),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Open saved clips',
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    try {
                      // Pause recorder while user browses clips
                      await RecorderManager.instance.pauseRecordingForUi();
                      if (context.mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ClipBrowserScreen(),
                          ),
                        );
                      }
                    } catch (e) {
                      try {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Unable to open clips'),
                            ),
                          );
                        }
                      } catch (_) {}
                    } finally {
                      // Resume recording if it was active before navigation
                      try {
                        await RecorderManager.instance.resumeRecordingAfterUi();
                      } catch (_) {}
                    }
                  },
                ),
              ],
            )
          : null,
      body: _loading
          ? Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Loading videos...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          : paths.isEmpty
          ? const Center(child: Text('No videos available'))
          : AdaptiveVideoGrid(
              videoUrls: paths,
              videoItems: _videoItems,
              onVideoStarted: (docId) {
                setState(() {
                  _currentVideoDocId = docId;
                });

                if (docId.isNotEmpty) {
                  debugPrint('✓ Video started with docId: $docId');
                  RecorderManager.instance.setCurrentVideoDocId(docId);
                } else {
                  debugPrint('⚠️ WARNING: Video started with empty docId');
                }
              },
              onVideoCompleted: (docId) async {
                if (_currentVideoDocId == docId) {
                  // Video completed
                }

                if (docId.isNotEmpty) {
                  debugPrint(
                    '✓ Video completed. Saving clip for docId: $docId',
                  );
                }

                // Save the clip (pass docId to avoid race where recorder state
                // hasn't yet updated its internal docId)
                try {
                  await RecorderManager.instance.notifySegmentEnd(docId);
                } catch (e) {
                  debugPrint('✗ Error calling notifySegmentEnd: $e');
                }
                // Clear docId
                RecorderManager.instance.setCurrentVideoDocId(null);
                if (mounted) {
                  setState(() {
                    _currentVideoDocId = null;
                  });
                }
              },
              onVideoDuration: (dur) {
                RecorderManager.instance.setSegmentDuration(dur);
              },
            ),
    );
  }
}
