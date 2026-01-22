import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/adaptive_video_grid.dart';
import 'recorder/foreground_recorder.dart';
import 'services/video_sync.dart';
import 'screens/clip_browser.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glance Grid - Video Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VideoPlayerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // now store items with path + docId
  List<Map<String, String>> _videoItems = [];
  bool _loading = false;
  bool _usingFirebase = false;
  bool _isPlaying = false;
  String? _currentPlayingUrl;
  bool _passwordValid = false;
  String? _currentVideoDocId; // Track docId directly

  @override
  void initState() {
    super.initState();
    _videoItems = [];
    // initialize recorder manager after first frame so we can show consent dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Show password dialog first
      _showPasswordDialog();

      // Initialize recorder (may show consent dialog once). When recorder
      // reports it is ready (permissions granted), load Firebase videos.
      //TODO-REMOVE COMMENT BELOW
      RecorderManager.instance.init(context);
      RecorderManager.instance.readyNotifier.addListener(() {
        if (RecorderManager.instance.readyNotifier.value) {
          // Fetch metadata from Firestore (no downloading)
          VideoSync.instance
              .syncWithFirestore()
              .then((res) {
                final items = (res['items'] as List)
                    .cast<Map<String, String>>();
                setState(() {
                  _videoItems = items;
                  _usingFirebase = true;
                  _loading = false;
                });
              })
              .catchError((e) {
                setState(() => _loading = false);
                // fallback: try to load from firebase URLs into memory (no download)
                _loadFromFirebase();
              });
        }
      });
    });
  }

  Future<void> _showPasswordDialog() async {
    final pwd = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String input = '';
        return AlertDialog(
          title: const Text('Enter Password'),
          content: TextField(
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Password'),
            onChanged: (v) => input = v,
            onSubmitted: (_) => Navigator.of(ctx).pop(input),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(input),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (pwd == 'Glancegrid@123') {
      setState(() {
        _passwordValid = true;
      });
    } else {
      setState(() {
        _passwordValid = false;
      });
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect password - AppBar will be hidden'),
            ),
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _loadFromFirebase() async {
    // If a Firebase video is currently playing, ignore the request
    if (_usingFirebase && _isPlaying) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase video already playing')),
        );
      } catch (_) {}
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final docs = await firestore.collection('videos').get();

      if (docs.docs.isEmpty) {
        setState(() {
          _loading = false;
        });
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No videos found in Firestore')),
          );
        } catch (_) {}
        return;
      }

      // Build items with videoUrl and docId
      final items = <Map<String, String>>[];
      for (final doc in docs.docs) {
        final docId = doc.id;
        final data = doc.data();
        final videoUrl = data['videoUrl'] as String?;

        if (videoUrl != null && videoUrl.isNotEmpty) {
          items.add({'path': videoUrl, 'docId': docId});
        }
      }

      if (items.isEmpty) {
        setState(() {
          _loading = false;
        });
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No videos with videoUrl found')),
          );
        } catch (_) {}
        return;
      }

      setState(() {
        _videoItems = items;
        _loading = false;
        _usingFirebase = true;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to open clips')),
                        );
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
          : Stack(
              children: [
                paths.isEmpty
                    ? const Center(child: Text('No videos available'))
                    : AdaptiveVideoGrid(
                        videoUrls: paths,
                        videoItems: _videoItems,
                          onVideoStarted: (docId) {
                            setState(() {
                              _isPlaying = true;
                              // _currentPlayingUrl is no longer authoritative for saving, docId is.
                              _currentVideoDocId = docId;
                            });

                            if (docId.isNotEmpty) {
                              debugPrint(
                                '✓ Video started with docId: $docId',
                              );
                              // Directly set the authoritative ID
                              RecorderManager.instance.setCurrentVideoDocId(
                                docId,
                              );
                            } else {
                              debugPrint(
                                '⚠️ WARNING: Video started with empty docId',
                              );
                            }
                          },
                          onVideoCompleted: (docId) async {
                            if (_currentVideoDocId == docId) {
                              setState(() {
                                _isPlaying = false;
                              });
                            }

                            // Log clip saving attempt
                            if (docId.isNotEmpty) {
                              debugPrint(
                                '✓ Video completed. Saving clip for docId: $docId',
                              );
                            } 

                            // Save the clip
                            try {
                              await RecorderManager.instance.notifySegmentEnd();
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
              ],
            ),
    );
  }
}
