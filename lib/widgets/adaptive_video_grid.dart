import 'dart:io';
import 'package:flutter/foundation.dart'; // for listEquals
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/video_sync.dart';

import 'dart:async'; // Add this for Timer

class FileGridItem extends StatefulWidget {
  final String url;
  final String docId; // docId for recorder
  final String type; // 'video' or 'image'
  final int duration; // duration in seconds
  final ValueChanged<String>? onStarted; // returns docId
  final ValueChanged<String>? onCompleted; // returns docId
  final VoidCallback onDurationComplete; // helper to go next
  final ValueChanged<double>? onProgress;
  final ValueChanged<Duration?>?
  onVideoDuration; // mostly for video recorder sync

  const FileGridItem({
    super.key,
    required this.url,
    required this.docId,
    required this.type,
    required this.duration,
    this.onStarted,
    this.onCompleted,
    required this.onDurationComplete,
    this.onProgress,
    this.onVideoDuration,
  });

  @override
  State<FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<FileGridItem> {
  // Video specific
  VideoPlayerController? _videoController;

  // Image specific
  Timer? _imageTimer;
  Timer? _progressTimer;

  bool _isInitialized = false;
  bool _onCompletedCalled = false;

  @override
  void initState() {
    super.initState();
    _tryInitialize();
  }

  @override
  void didUpdateWidget(FileGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the URL changed (e.g., from network to local after download), reinitialize
    if (oldWidget.url != widget.url) {
      _disposeControllers();
      _isInitialized = false;
      _onCompletedCalled = false;
      _tryInitialize();
    }
  }

  void _disposeControllers() {
    _videoController?.removeListener(_onVideoControllerUpdate);
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;

    _imageTimer?.cancel();
    _imageTimer = null;

    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _tryInitialize() async {
    try {
      if (widget.type == 'image') {
        _initializeImage();
      } else {
        await _initializeVideo();
      }
    } catch (e) {
      debugPrint('Error initializing file item: $e');
      // If it's a local file that failed, logic to delete/retry could go here similar to before
    }
  }

  void _initializeImage() {
    setState(() {
      _isInitialized = true;
    });

    // Execute state updates after the current frame to avoid build conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Notify started
      widget.onStarted?.call(widget.docId);

      // Default 10s if 0
      final durationSeconds = widget.duration > 0 ? widget.duration : 10;
      final totalDuration = Duration(seconds: durationSeconds);

      // Report "video duration" to the parent
      widget.onVideoDuration?.call(totalDuration);

      final startTime = DateTime.now();

      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().difference(startTime);
        final progress = (elapsed.inMilliseconds / totalDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        widget.onProgress?.call(progress);

        if (progress >= 1.0) {
          timer.cancel();
        }
      });

      _imageTimer = Timer(totalDuration, () {
        if (!mounted) return;
        if (!_onCompletedCalled) {
          _onCompletedCalled = true;
          widget.onCompleted?.call(widget.docId);
          widget.onDurationComplete();
        }
      });
    });
  }

  Future<void> _initializeVideo() async {
    final isLocalFile =
        widget.url.startsWith('/') || widget.url.contains('documents');

    if (isLocalFile) {
      _videoController = VideoPlayerController.file(File(widget.url));
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
    }

    await _videoController!.initialize();
    if (!mounted) return;

    setState(() {
      _isInitialized = true;
    });

    // Report duration
    final dur = _videoController!.value.duration;
    widget.onVideoDuration?.call(dur > Duration.zero ? dur : null);

    _videoController!.play();
    widget.onStarted?.call(widget.docId);

    _videoController!.addListener(_onVideoControllerUpdate);
  }

  void _onVideoControllerUpdate() {
    if (!mounted || _videoController == null) return;
    final val = _videoController!.value;

    if (!val.isInitialized) return;
    final duration = val.duration;
    if (duration <= const Duration(milliseconds: 500)) return;

    final position = val.position;
    widget.onProgress?.call(
      (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
    );

    // Check if video is near the end
    const margin = Duration(milliseconds: 200);
    // Use widget.duration if provided and valid? usually video uses its own length.
    // Logic: if position >= duration - margin
    if (!_onCompletedCalled) {
      if (position >= duration - margin) {
        _onCompletedCalled = true;
        widget.onCompleted?.call(widget.docId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onDurationComplete();
        });
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.type == 'image') {
      final isLocal = widget.url.startsWith('/');
      return Container(
        color: Colors.black,
        child: SizedBox.expand(
          child: isLocal
              ? Image.file(File(widget.url), fit: BoxFit.contain)
              : Image.network(widget.url, fit: BoxFit.contain),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: SizedBox.expand(child: VideoPlayer(_videoController!)),
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
      final type = item['type'];
      final localPath = await VideoSync.instance.downloadSingleFile(
        docId!,
        url,
        type: type,
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

    return PageView.builder(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
        // Trigger download for the new page
        _downloadIfNeeded(index);

        // Handle swipe wrap-around
        if (index == 0 && _currentIndex == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              final page = _pageController.page ?? 0.0;
              if (page < -0.5) {
                _pageController.jumpToPage(widget.videoUrls.length - 1);
              }
            }
          });
        }
      },
      itemCount: widget.videoUrls.length,
      itemBuilder: (context, index) {
        final item = widget.videoItems?[index];
        // Use the path from item if available (contains updated local path), else fallback to url list
        final url = item?['path'] ?? widget.videoUrls[index];
        final docId = item?['docId'] ?? 'unknown_$index';
        final type = item?['type'] ?? 'video';
        final durationStr = item?['duration'];
        final duration = int.tryParse(durationStr ?? '10') ?? 10;

        return FileGridItem(
          url: url,
          docId: docId,
          type: type,
          duration: duration,
          onStarted: widget.onVideoStarted,
          onCompleted: widget.onVideoCompleted,
          onDurationComplete: _goToNextPage,
          onProgress: (progress) {
            // Progress update if needed for UI in grid item itself?
            // Since we removed _currentProgress usage from parent, we can just ignore it or remove the callback.
            // But FileGridItem expects it. We can keep it empty or use it if we want a global progress bar.
            // For now just empty or keep local to avoid breaking changes if planned to use later.
          },
          onVideoDuration: widget.onVideoDuration,
        );
      },
    );
  }
}
