import 'package:flutter/material.dart';
import '../state/session.dart';
import 'login_screen.dart';
class ChangeExpiredPasswordScreen extends StatefulWidget {
  final Session session;
  final String username;

  const ChangeExpiredPasswordScreen({
    super.key,
    required this.session,
    required this.username,
  });

  @override
  State<ChangeExpiredPasswordScreen> createState() =>
      _ChangeExpiredPasswordScreenState();
}

class _ChangeExpiredPasswordScreenState
    extends State<ChangeExpiredPasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.session.api.changeExpiredPassword(
        username: widget.username,
        oldPassword: _oldCtrl.text,
        newPassword: _newCtrl.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Please login.')),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(session: widget.session),
        ),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Old password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}
