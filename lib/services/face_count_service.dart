import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class FaceCountService {
  FaceCountService._internal();
  static final FaceCountService instance = FaceCountService._internal();

  static const MethodChannel _channel = MethodChannel('facecount');

  Future<bool> initRuntime({String? configPath}) async {
    final result = await _channel.invokeMethod<bool>('initRuntime', {
      'configPath': configPath,
    });
    return result ?? false;
  }

  Future<Map<String, dynamic>> analyzeJpegBytes(Uint8List jpegBytes) async {
    try {
      final String response =
          await _channel.invokeMethod<String>('analyzeJpegBytes', {
            'jpegBytes': jpegBytes,
          }) ??
          '';

      if (response.isEmpty) {
        return {
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          'error': 'empty_response',
          'face_count': 0,
          'faces': [],
          'deepface_enabled': false,
        };
      }

      final data = json.decode(response);
      if (data is Map<String, dynamic>) return data;

      return {
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        'error': 'invalid_response',
        'face_count': 0,
        'faces': [],
        'deepface_enabled': false,
      };
    } on PlatformException catch (error) {
      // Common failure: Python side not having cv2 available.
      return {
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        'error': 'python_platform_error',
        'error_message': error.message ?? error.toString(),
        'face_count': 0,
        'faces': [],
        'deepface_enabled': false,
      };
    } catch (error) {
      return {
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        'error': 'unexpected_error',
        'error_message': error.toString(),
        'face_count': 0,
        'faces': [],
        'deepface_enabled': false,
      };
    }
  }

  Future<void> saveFaceCountResult({
    required String clipId,
    required String deviceId,
    required Map<String, dynamic> payload,
  }) async {
    final collection = FirebaseFirestore.instance.collection(
      'face_count_results',
    );
    await collection.add({
      'clipId': clipId,
      'deviceId': deviceId,
      'payload': payload,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
