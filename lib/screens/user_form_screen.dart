import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/device_id_service.dart';
import '../services/user_service.dart';

import 'video_player_screen.dart';

class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String? _deviceId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    final id = await DeviceIdService.instance.getDeviceId();
    setState(() {
      _deviceId = id;
      _isLoading = false;
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate() && _deviceId != null) {
      setState(() => _isLoading = true);

      final user = UserModel(
        userName: _nameController.text.trim(),
        description: _descController.text.trim(),
        deviceId: _deviceId!,
      );

      try {
        await UserService.instance.addUser(user);

        if (mounted) {
          // Navigate to main video screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const VideoPlayerScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving user: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    // const SizedBox(height: 16),
                    // // Display Unique Device ID
                    // InputDecorator(
                    //   decoration: const InputDecoration(
                    //     labelText: 'Device ID',
                    //     border: OutlineInputBorder(),
                    //   ),
                    //   child: Text(
                    //     _deviceId ?? '',
                    //     style: const TextStyle(color: Colors.grey),
                    //   ),
                    // ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
