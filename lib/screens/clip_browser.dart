import 'dart:io';

import 'package:flutter/material.dart';
import '../recorder/foreground_recorder.dart';
import 'clip_player.dart';

class ClipBrowserScreen extends StatefulWidget {
  const ClipBrowserScreen({super.key});

  @override
  State<ClipBrowserScreen> createState() => _ClipBrowserScreenState();
}

class _ClipBrowserScreenState extends State<ClipBrowserScreen> {
  late Future<List<File>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<File>> _loadFiles() async {
    try {
      final path = await RecorderManager.instance.getSavedClipsDirectoryPath();
      final dir = Directory(path);
      if (!await dir.exists()) return [];
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.mp4'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      return files;
    } catch (e) {
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _filesFuture = _loadFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Clips'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _filesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snap.data ?? [];
          if (files.isEmpty) {
            return const Center(child: Text('No saved clips found'));
          }
          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, i) {
              final f = files[i];
              final name = f.path.split(Platform.pathSeparator).last;
              final modified = f.statSync().modified;
              final sizeKb = (f.lengthSync() / 1024).toStringAsFixed(0);
              return ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(name),
                subtitle: Text('${modified.toLocal()} • $sizeKb KB'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ClipPlayerScreen(file: f),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete clip?'),
                            content: Text('Delete "$name"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          try {
                            await f.delete();
                            _refresh();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Delete failed')),
                            );
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ClipPlayerScreen(file: f),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
