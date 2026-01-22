import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

class VideoSync {
  VideoSync._();
  static final instance = VideoSync._();

  /// Fetch Firestore `videos` collection metadata without downloading.
  /// Each doc must have a `videoUrl` field (network URL to the video).
  /// Returns { 'items': List<Map<String,String>> }
  /// Items contain: 'path' (videoUrl), 'docId' (Firestore doc ID)
  Future<Map<String, Object>> syncWithFirestore() async {
    final firestore = FirebaseFirestore.instance;

    try {
      final remote = await firestore.collection('videos').get();
      final List<Map<String, String>> items = [];

      // Simply fetch metadata from Firestore without downloading
      for (final doc in remote.docs) {
        final docId = doc.id;
        final data = doc.data();
        final videoUrl = data['videoUrl'] as String?;

        if (videoUrl == null || videoUrl.isEmpty) {
          continue;
        }

        items.add({'path': videoUrl, 'docId': docId});
      }

      return {'items': items};
    } catch (e) {
      rethrow;
    }
  }

  /// Download a single video on-demand by docId and videoUrl.
  /// Returns the local file path if successful, null otherwise.
  Future<String?> downloadSingleVideo(String docId, String videoUrl) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${dir.path}/videos');
      if (!await videosDir.exists()) await videosDir.create(recursive: true);

      final localPath = '${videosDir.path}/${docId}_video.mp4';
      final localFile = File(localPath);

      // If already exists, return immediately
      if (await localFile.exists()) {
        return localPath;
      }

      // Download the video
      final response = await HttpClient().getUrl(Uri.parse(videoUrl));
      final httpResponse = await response.close();

      if (httpResponse.statusCode == 200) {
        await localFile.create(recursive: true);
        await httpResponse.pipe(localFile.openWrite());
        return localPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
