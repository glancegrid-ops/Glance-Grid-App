import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../services/face_count_service.dart';

class TestOutputScreen extends StatefulWidget {
  const TestOutputScreen({super.key});
  static const defaultAssetPath = 'assets/images/test.png';
  @override
  State<TestOutputScreen> createState() => _TestOutputScreenState();
}

class _TestOutputScreenState extends State<TestOutputScreen> {
  bool _isAnalyzing = false;
  String _status = 'Ready';
  String _jsonOutput = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Output Screen')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Text(
              'Displaying test image from assets',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            //  const SizedBox(height: 12),
            // Text(
            //   TestOutputScreen.defaultAssetPath,
            //   style: const TextStyle(fontSize: 12, color: Colors.black54),
            //   textAlign: TextAlign.center,
            // ),
            // const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                TestOutputScreen.defaultAssetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Text(
                      'Unable to load image from assets.\nCheck pubspec.yaml and path.',
                      style: TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            //  const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isAnalyzing ? null : _analyzeFace,
              child: _isAnalyzing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Analyze face from test image'),
            ),
            const SizedBox(height: 16),
            Text(
              _jsonOutput.isEmpty
                  ? 'JSON output will appear here.'
                  : _jsonOutput,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _analyzeFace() async {
    setState(() {
      _isAnalyzing = true;
      _status = 'Reading ~image bytes...';
      _jsonOutput = '';
    });

    try {
      final byteData = await rootBundle.load(TestOutputScreen.defaultAssetPath);
      final bytes = byteData.buffer.asUint8List();
      setState(() => _status = 'Analyzing face data...');

      final result = await FaceCountService.instance.analyzeJpegBytes(bytes);
      final prettyJson = const JsonEncoder.withIndent('  ').convert(result);

      setState(() {
        _status = 'Analysis complete';
        _jsonOutput = prettyJson;
        print(_status);
        print(_jsonOutput);
      });
    } catch (error, stack) {
      setState(() {
        _status = 'Analysis failed: $error';

        _jsonOutput = stack.toString();
      });
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }
}
