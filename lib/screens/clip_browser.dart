import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../recorder/foreground_recorder.dart';
import 'clip_player.dart';

class ClipBrowserScreen extends StatefulWidget {
  const ClipBrowserScreen({super.key});

  @override
  State<ClipBrowserScreen> createState() => _ClipBrowserScreenState();
}

class _ClipBrowserScreenState extends State<ClipBrowserScreen> {
  List<File> _files = [];
  bool _isLoading = true;
  Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final path = await RecorderManager.instance.getSavedClipsDirectoryPath();
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _files = [];
          _isLoading = false;
        });
        return;
      }
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.mp4'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_isSelectionMode) {
      _exitSelectionMode();
    }
    await _loadFiles();
  }

  void _enterSelectionMode(String path) {
    setState(() {
      _isSelectionMode = true;
      _selectedPaths.add(path);
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths = _files.map((f) => f.path).toSet();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPaths.clear();
    });
  }

  Future<void> _downloadSelected() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const Dialog(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Downloading...'),
                ],
              ),
            ),
          ),
    );

    int successCount = 0;
    try {
      // Check permissions implicitly by trying or could use Gal.hasAccess() if needed.
       // Gal requests permissions automatically on Android/iOS if not granted.
       for (final path in _selectedPaths) {
         await Gal.putVideo(path); // Save video
         successCount++;
       }
    } catch (e) {
      debugPrint('Download error: $e');
    }

    if (mounted) {
      Navigator.of(context).pop(); // Close progress dialog
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $successCount clips to Gallery')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:
            _isSelectionMode
                ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                )
                : null,
        title: Text(_isSelectionMode ? '${_selectedPaths.length}' : 'Saved Clips'),
        actions:
            _isSelectionMode
                ? [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: _downloadSelected,
                  ),
                ]
                : [
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
                ],
      ),
      body: Builder(
        builder: (context) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_files.isEmpty) {
            return const Center(child: Text('No saved clips found'));
          }
          return ListView.builder(
            itemCount: _files.length,
            itemBuilder: (ctx, i) {
              final f = _files[i];
              final name = f.path.split(Platform.pathSeparator).last;
              final modified = f.statSync().modified;
              final sizeKb = (f.lengthSync() / 1024).toStringAsFixed(0);
              final isSelected = _selectedPaths.contains(f.path);

              return ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(name),
                subtitle: Text('${modified.toLocal()} • $sizeKb KB'),
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(f.path);
                  } else {
                    Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => ClipPlayerScreen(file: f),
                      ),
                    );
                  }
                },
                onLongPress: () {
                  if (!_isSelectionMode) {
                    _enterSelectionMode(f.path);
                  } else {
                    _toggleSelection(f.path);
                  }
                },
                trailing:
                    _isSelectionMode
                        ? Checkbox(
                          value: isSelected,
                          onChanged: (v) => _toggleSelection(f.path),
                        )
                        : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: ctx,
                                  builder:
                                      (dialogCtx) => AlertDialog(
                                        title: const Text('Delete clip?'),
                                        content: Text('Delete "$name"?'),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(dialogCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(dialogCtx, true),
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
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Delete failed'),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () {
                                Navigator.of(ctx).push(
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
