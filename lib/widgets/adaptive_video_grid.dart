import 'dart:io';
import 'package:flutter/foundation.dart'; // for listEquals
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/video_sync.dart';

class VideoGridItem extends StatefulWidget {
  final String videoUrl;
  final String videoId; // docId for recorder
  final Duration? videoDuration;
  final ValueChanged<String>? onStarted; // returns videoId
  final ValueChanged<String>? onCompleted; // returns videoId
  final VoidCallback onDurationComplete;
  final ValueChanged<double>? onProgress;
  final ValueChanged<Duration?>? onVideoDuration;

  const VideoGridItem({
    super.key,
    required this.videoUrl,
    required this.videoId,
    this.videoDuration,
    this.onStarted,
    this.onCompleted,
    required this.onDurationComplete,
    this.onProgress,
    this.onVideoDuration,
  });

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _onCompletedCalled = false;

  @override
  void initState() {
    super.initState();
    _tryInitialize();
  }

  @override
  void didUpdateWidget(VideoGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the video URL changed (e.g., from network to local after download), reinitialize
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller.removeListener(_onControllerUpdate);
      _controller.pause();
      _controller.dispose();
      _isInitialized = false;
      _onCompletedCalled = false;
      _tryInitialize();
    }
  }

  Future<void> _tryInitialize() async {
    try {
      final isLocalFile =
          widget.videoUrl.startsWith('/') ||
          widget.videoUrl.contains('documents');

      if (isLocalFile) {
        _controller = VideoPlayerController.file(File(widget.videoUrl));
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
      }

      await _controller.initialize();
      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      // Report duration to parent
      final dur = _controller.value.duration;
      widget.onVideoDuration?.call(dur > Duration.zero ? dur : null);

      _controller.play();
      // Pass the stable videoId instead of potential local path
      widget.onStarted?.call(widget.videoId);

      _addControllerListener();
    } catch (e) {
      // If it's a local file that failed to initialize, delete it and retry with network URL
      if (widget.videoUrl.startsWith('/') ||
          widget.videoUrl.contains('documents')) {
        try {
          final file = File(widget.videoUrl);
          if (await file.exists()) {
            await file.delete();
            debugPrint('Deleted corrupted local file: ${widget.videoUrl}');
          }

          // Request re-download from VideoSync (handled by parent logic usually)
          // For now just error out or let parent handle retry logic
        } catch (deleteError) {
          debugPrint('Error handling corrupted file: $deleteError');
        }
      }
    }
  }

  void _addControllerListener() {
    _controller.removeListener(_onControllerUpdate);
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final val = _controller.value;

    if (!val.isInitialized) return;
    final duration = val.duration;
    if (duration <= Duration(milliseconds: 500)) return;

    final position = val.position;
    widget.onProgress?.call(
      (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
    );

    // Check if video is near the end
    const margin = Duration(milliseconds: 200);
    if (!_onCompletedCalled && widget.videoDuration == null) {
      if (position >= duration - margin) {
        _onCompletedCalled = true;
        // Pass stable videoId
        widget.onCompleted?.call(widget.videoId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onDurationComplete();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: Colors.black,
      child: SizedBox.expand(child: VideoPlayer(_controller)),
    );
  }
}

class AdaptiveVideoGrid extends StatefulWidget {
  final List<String> videoUrls; // List of paths (can change dynamically)
  final List<Map<String, String>>? videoItems; // Items with docId and path
  final Duration? videoDuration;
  final ValueChanged<String>? onVideoStarted; // Returns videoId
  final ValueChanged<String>? onVideoCompleted; // Returns videoId
  final ValueChanged<Duration?>? onVideoDuration;

  const AdaptiveVideoGrid({
    super.key,
    required this.videoUrls,
    this.videoItems,
    this.videoDuration,
    this.onVideoStarted,
    this.onVideoCompleted,
    this.onVideoDuration,
  });

  @override
  State<AdaptiveVideoGrid> createState() => _AdaptiveVideoGridState();
}

class _AdaptiveVideoGridState extends State<AdaptiveVideoGrid> {
  late PageController _pageController;
  int _currentIndex = 0;
  double _currentProgress = 0.0;
  // Removed blocking loader state variables

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Preload all videos on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadAllVideos();
    });
  }

  Future<void> _preloadAllVideos() async {
    if (widget.videoItems == null) return;

    for (int i = 0; i < widget.videoItems!.length; i++) {
      await _downloadIfNeeded(i);
    }
  }

  @override
  void didUpdateWidget(AdaptiveVideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Use listEquals to prevent unnecessary resets if the content is effectively the same
    final urlsChanged = !listEquals(widget.videoUrls, oldWidget.videoUrls);
    
    // Only reset if URLs actually changed and it's not just a reference change 
    if (urlsChanged) {
      // If the length changed or content changed significantly, we might need to reset.
      // But if it's just a local path update in place, we should try to keep position.
      if (widget.videoUrls.length != oldWidget.videoUrls.length) {
         _pageController.dispose();
         _pageController = PageController();
         _currentIndex = 0;
         _currentProgress = 0.0;
      } else {
         // Length is same, probably just a path update (network -> local). Keep index.
         // Do not dispose controller.
      }
    }
  }

  Future<void> _downloadIfNeeded(int index) async {
    if (widget.videoItems == null || index >= widget.videoItems!.length) {
      return;
    }

    final item = widget.videoItems![index];
    final docId = item['docId'];
    final url = item['path'];

    // Check if already downloaded (starts with / means local file)
    if (url == null || url.isEmpty || url.startsWith('/')) {
      return;
    }

    // Checking globally if downloading might be overkill; 
    // we can just fire and forget download for cache.
    // Logic here was updating state for blocking loader. We removed blocking loader.
    
    try {
      final localPath = await VideoSync.instance.downloadSingleVideo(
        docId!,
        url,
      );
      if (localPath != null) {
        // Update the URL in the parent's items list (in-place)
        if (mounted) {
          // This triggers parent rebuild if parent is listening to this structure, 
          // or we force valid path usage next build
          widget.videoItems![index]['path'] = localPath;
          
          // Re-trigger build to switch to local file
          setState(() {}); 
        }
      }
    } catch (e) {
      // Silently handle download errors
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (widget.videoUrls.isEmpty || !_pageController.hasClients) return;

    // Get the actual current page from the controller
    final currentPage = _pageController.page?.round() ?? _currentIndex;
    final lastIndex = widget.videoUrls.length - 1;

    if (currentPage < lastIndex) {
      final nextIndex = currentPage + 1;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Loop back to first video
      _pageController.jumpToPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Robust check for current index
    if (_currentIndex >= widget.videoUrls.length) {
      _currentIndex = 0;
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                        _currentProgress = 0.0;
                      });
                      // Trigger download for the new page
                      _downloadIfNeeded(index);

                      // Handle swipe wrap-around
                      if (index == 0 && _currentIndex == 0) {
                         WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_pageController.hasClients) {
                            final page = _pageController.page ?? 0.0;
                            if (page < -0.5) {
                              _pageController.jumpToPage(
                                widget.videoUrls.length - 1,
                              );
                            }
                          }
                        });
                      }
                    },
                    itemCount: widget.videoUrls.length,
                    itemBuilder: (context, index) {
                      final item = widget.videoItems?[index];
                      // Use the path from item if available (contains updated local path), else fallback to url list
                      final videoUrl = item?['path'] ?? widget.videoUrls[index];
                      // Fallback if item structure is broken
                      final docId = item?['docId'] ?? 'unknown_$index';
                      
                      return VideoGridItem(
                        videoUrl: videoUrl,
                        videoId: docId, // Pass ID explicitly
                        videoDuration: widget.videoDuration,
                        onStarted: widget.onVideoStarted,
                        onCompleted: widget.onVideoCompleted,
                        onDurationComplete: _goToNextPage,
                        onProgress: (progress) {
                          setState(() {
                            _currentProgress = progress;
                          });
                        },
                        onVideoDuration: widget.onVideoDuration,
                      );
                    },
                  ),
                  // Dot indicator in bottom right corner
                  Positioned(
                    bottom: 20, 
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          widget.videoUrls.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _currentIndex
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Progress bar at bottom
            LinearProgressIndicator(
              value: _currentProgress,
              minHeight: 3,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
            ),
          ],
        ),
         // Removed the blocking container that was here
      ],
    );
  }
}
