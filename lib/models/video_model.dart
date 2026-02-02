class VideoModel {
  final String? docId;
  final String videoUrl;
  final List<String> userIds;

  VideoModel({this.docId, required this.videoUrl, required this.userIds});

  factory VideoModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    return VideoModel(
      docId: docId,
      videoUrl: json['videoUrl'] as String? ?? '',
      userIds:
          (json['userIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'videoUrl': videoUrl, 'userIds': userIds};
  }
}
