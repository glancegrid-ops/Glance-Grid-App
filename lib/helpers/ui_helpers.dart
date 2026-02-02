import 'package:flutter/material.dart';

class UiHelpers {
  static Future<bool> showPasswordDialog(BuildContext context) async {
    final pwd = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String input = '';
        return AlertDialog(
          title: const Text('Enter Password'),
          content: TextField(
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Password'),
            onChanged: (v) => input = v,
            onSubmitted: (_) => Navigator.of(ctx).pop(input),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(input),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (pwd == 'Glancegrid@123') {
      return true;
    } else {
      if (context.mounted) {
         try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect password - AppBar will be hidden'),
            ),
          );
        } catch (_) {}
      }
      return false;
    }
  }
}
