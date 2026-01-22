import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ClipPlayerScreen extends StatefulWidget {
  final File file;
  const ClipPlayerScreen({super.key, required this.file});

  @override
  State<ClipPlayerScreen> createState() => _ClipPlayerScreenState();
}

class _ClipPlayerScreenState extends State<ClipPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize()
          .then((_) {
            setState(() => _initialized = true);
            _controller.play();
          })
          .catchError((e) {
            // Silently handle initialization error
          });
  }

  @override
  void dispose() {
    try {
      _controller.pause();
      _controller.dispose();
    } catch (_) {}
    super.dispose();
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: () {
            setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          onPressed: () {
            _controller.pause();
            _controller.seekTo(Duration.zero);
            setState(() {});
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.file.path.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _initialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: _buildControls(),
          ),
        ],
      ),
    );
  }
}
