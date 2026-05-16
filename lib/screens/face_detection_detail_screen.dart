import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class FaceDetectionDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const FaceDetectionDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final timestamp = data['timestamp'] as Timestamp?;
    final formattedTime = timestamp != null
        ? timestamp.toDate().toString()
        : 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final faceData = data['data'];

    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timestamp: $formattedTime',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Video ID: ${data['videoId'] ?? 'N/A'}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Device ID: ${data['deviceId'] ?? 'N/A'}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (imageUrl != null) ...[
              const Text(
                'Captured Image:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Image.network(imageUrl, fit: BoxFit.contain),
              const SizedBox(height: 16),
            ],
            const Text(
              'Analysis Data:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.grey[200],
              child: Text(
                const JsonEncoder.withIndent('  ').convert(faceData),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
