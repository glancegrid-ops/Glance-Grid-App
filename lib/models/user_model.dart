class UserModel {
  final String? id;
  final String userName;
  final String description;
  final String deviceId;
  final List? locations; // Array of location data with timestamps

  UserModel({
    this.id,
    required this.userName,
    required this.description,
    required this.deviceId,
    this.locations,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? id}) {
    final locList = json['locations'] != null
        ? (json['locations'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              []
        : [];

    return UserModel(
      id: id,
      userName: json['userName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      locations: locList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'description': description,
      'deviceId': deviceId,
      'locations': locations ?? [],
    };
  }
}
