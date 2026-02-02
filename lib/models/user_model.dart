class UserModel {
  final String? id;
  final String userName;
  final String description;
  final String deviceId;

  UserModel({
    this.id,
    required this.userName,
    required this.description,
    required this.deviceId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return UserModel(
      id: id,
      userName: json['userName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'description': description,
      'deviceId': deviceId,
    };
  }
}
