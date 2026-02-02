import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/video_model.dart';


class VideoService {
  static final VideoService instance = VideoService._internal();
  VideoService._internal();

  final CollectionReference _videosCollection =
      FirebaseFirestore.instance.collection('videos');

  Future<List<VideoModel>> fetchVideosForDevice(String deviceId) async {
    final snapshot = await _videosCollection.get();
    final List<VideoModel> videos = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final video = VideoModel.fromJson(data, docId: doc.id);

      // Filter: Check if deviceId is in the allowed list
      if (video.userIds.contains(deviceId)) {
        videos.add(video);
      }
    }
    return videos;
  }
}
