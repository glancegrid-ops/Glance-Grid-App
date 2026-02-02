import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static final DeviceIdService instance = DeviceIdService._internal();
  DeviceIdService._internal();

  final _storage = const FlutterSecureStorage();
  final _uuid = const Uuid();
  static const _keyDeviceId = 'device_id';

  Future<String> getDeviceId() async {
    String? deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    return deviceId;
  }
}
