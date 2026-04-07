import 'package:flutter/material.dart';
import '../services/device_id_service.dart';
import '../services/face_count_service.dart';
import '../services/user_service.dart';
import 'video_player_screen.dart';
import 'user_form_screen.dart';

class StartupWrapper extends StatefulWidget {
  const StartupWrapper({super.key});

  @override
  State<StartupWrapper> createState() => _StartupWrapperState();
}

class _StartupWrapperState extends State<StartupWrapper> {
  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    try {
      await FaceCountService.instance.initRuntime();

      final deviceId = await DeviceIdService.instance.getDeviceId();
      final user = await UserService.instance.getUserByDeviceId(deviceId);

      if (!mounted) return;

      if (user != null) {
        // User exists, go to video player
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VideoPlayerScreen()),
        );
      } else {
        // New user, go to form
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UserFormScreen()),
        );
      }
    } catch (e) {
      // In case of error (e.g. offline), try to proceed to video player as fallback
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VideoPlayerScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
