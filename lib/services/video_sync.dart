import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

class VideoSync {
  VideoSync._();
  static final instance = VideoSync._();

  /// Fetch Firestore `videos` collection metadata without downloading.
  /// Each doc must have a `videoUrl` or `url` field.
  /// Returns { 'items': List<Map<String,dynamic>> }
  Future<Map<String, Object>> syncWithFirestore() async {
    final firestore = FirebaseFirestore.instance;

    try {
      final remote = await firestore.collection('videos').get();
      final List<Map<String, dynamic>> items = [];

      for (final doc in remote.docs) {
        final docId = doc.id;
        final data = doc.data();
        // Support legacy 'videoUrl' and new 'url'
        final url = (data['url'] as String?) ?? (data['videoUrl'] as String?);
        final type = (data['type'] as String?) ?? 'video';

        if (url == null || url.isEmpty) {
          continue;
        }

        items.add({'path': url, 'docId': docId, 'type': type});
      }

      return {'items': items};
    } catch (e) {
      rethrow;
    }
  }

  /// Download a single file on-demand by docId and url.
  /// Returns the local file path if successful, null otherwise.
  Future<String?> downloadSingleFile(String docId, String url, {String? type}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      
      final isImage = type == 'image';
      final folderName = isImage ? 'images' : 'videos';
      final directory = Directory('${dir.path}/$folderName');
      
      if (!await directory.exists()) await directory.create(recursive: true);

      // Simple extension check or assumption based on type
      // For videos we used .mp4. For images we will use .jpg (or try to detect from url if possible).
      // Assuming generic cache file for now.
      final extension = isImage ? '.jpg' : '.mp4';
      
      final localPath = '${directory.path}/${docId}_file$extension';
      final localFile = File(localPath);

      // If already exists, return immediately
      if (await localFile.exists()) {
        return localPath;
      }

      // Download the file
      final response = await HttpClient().getUrl(Uri.parse(url));
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

  // Legacy support for older calls if any remain
  Future<String?> downloadSingleVideo(String docId, String videoUrl) {
    return downloadSingleFile(docId, videoUrl, type: 'video');
  }
}
