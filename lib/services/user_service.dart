import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService instance = UserService._internal();
  UserService._internal();

  final CollectionReference _usersCollection = FirebaseFirestore.instance
      .collection('users');

  /// Create or update a user document using `deviceId` as the Firestore document ID.
  /// This ensures the user's document ID equals their device identifier.
  Future<void> addOrUpdateUser(UserModel user) async {
    final docId = user.deviceId;
    if (docId.isEmpty) {
      throw ArgumentError('deviceId cannot be empty');
    }
    await _usersCollection
        .doc(docId)
        .set(user.toJson(), SetOptions(merge: true));
  }

  /// Retrieve a user by deviceId (used as the document ID).
  Future<UserModel?> getUserByDeviceId(String deviceId) async {
    if (deviceId.isEmpty) return null;
    final doc = await _usersCollection.doc(deviceId).get();
    if (!doc.exists) return null;
    return UserModel.fromJson(doc.data() as Map<String, dynamic>, id: doc.id);
  }

  /// Delete a user document by deviceId (document ID).
  Future<void> deleteUserByDeviceId(String deviceId) async {
    if (deviceId.isEmpty) return;
    await _usersCollection.doc(deviceId).delete();
  }
}
