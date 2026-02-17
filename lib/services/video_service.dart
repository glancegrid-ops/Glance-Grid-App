import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/file_model.dart';


class VideoService {
  static final VideoService instance = VideoService._internal();
  VideoService._internal();

  final CollectionReference _videosCollection =
      FirebaseFirestore.instance.collection('videos');

  Future<List<FileModel>> fetchVideosForDevice(String deviceId) async {
    final snapshot = await _videosCollection.get();
    final List<FileModel> items = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final file = FileModel.fromJson(data, docId: doc.id);

      // Filter: Check if deviceId is in the allowed list
      if (file.userIds.contains(deviceId)) {
        items.add(file);
      }
    }
    return items;
  }
}

