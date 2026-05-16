import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/device_id_service.dart';
import 'face_detection_detail_screen.dart';

class FaceDetectionListScreen extends StatefulWidget {
  const FaceDetectionListScreen({super.key});

  @override
  State<FaceDetectionListScreen> createState() =>
      _FaceDetectionListScreenState();
}

class _FaceDetectionListScreenState extends State<FaceDetectionListScreen> {
  late Future<List<Map<String, dynamic>>> _faceDataFuture;

  @override
  void initState() {
    super.initState();
    _faceDataFuture = _loadFaceData();
  }

  Future<List<Map<String, dynamic>>> _loadFaceData() async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final snapshot = await FirebaseFirestore.instance
        .collection('faceDetectionData')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection Data')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _faceDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('No face detection data found.'));
          }
          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final item = data[index];
              final timestamp = item['timestamp'] as Timestamp?;
              final formattedTime = timestamp != null
                  ? timestamp.toDate().toString()
                  : 'Unknown';
              return ListTile(
                title: Text('Face Detection at $formattedTime'),
                subtitle: Text('Video ID: ${item['videoId'] ?? 'N/A'}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          FaceDetectionDetailScreen(data: item),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
