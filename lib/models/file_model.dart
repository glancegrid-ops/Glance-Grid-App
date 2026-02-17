enum FileType { video, image }

class FileModel {
  final String? docId;
  final String url;
  final List<String> userIds;
  final FileType type;
  final int duration;

  FileModel({
    this.docId,
    required this.url,
    required this.userIds,
    this.type = FileType.video,
    this.duration = 10,
  });

  factory FileModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    // Handle legacy 'videoUrl' or new 'url'
    final url = (json['url'] as String?) ?? (json['videoUrl'] as String?) ?? '';

    // Parse type
    FileType type = FileType.video;
    if (json['type'] == 'image') {
      type = FileType.image;
    }

    // Parse duration (default 10s for images, 0 or ignored for videos in existing logic?)
    // User requested dynamic duration from firebase.
    final duration = (json['duration'] as num?)?.toInt() ?? 10;

    return FileModel(
      docId: docId,
      url: url,
      userIds:
          (json['userIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      type: type,
      duration: duration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'userIds': userIds,
      'type': type == FileType.image ? 'image' : 'video',
      'duration': duration,
    };
  }
}
