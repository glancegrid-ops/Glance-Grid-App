import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService instance = UserService._internal();
  UserService._internal();

  final CollectionReference _usersCollection =
      FirebaseFirestore.instance.collection('users');

  Future<void> addUser(UserModel user) async {
    // Check if user with this deviceId already exists
    final querySnapshot = await _usersCollection
        .where('deviceId', isEqualTo: user.deviceId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      // Update existing
      final docId = querySnapshot.docs.first.id;
      await _usersCollection.doc(docId).update(user.toJson());
    } else {
      // Add new
      await _usersCollection.add(user.toJson());
    }
  }

  Future<UserModel?> getUserByDeviceId(String deviceId) async {
    final querySnapshot = await _usersCollection
        .where('deviceId', isEqualTo: deviceId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      return UserModel.fromJson(
        doc.data() as Map<String, dynamic>,
        id: doc.id,
      );
    }
    return null;
  }

  Future<void> deleteUser(String id) async {
    await _usersCollection.doc(id).delete();
  }
}
