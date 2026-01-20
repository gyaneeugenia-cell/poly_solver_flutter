import 'package:flutter/material.dart';
import '../state/session.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final Session session;

  const ForgotPasswordScreen({super.key, required this.session});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);

    await widget.session.api.forgotPassword(
      email: _emailCtrl.text.trim(),
    );

    setState(() => _loading = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Check your email for reset link')),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Enter your email to receive an email for password reset',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: const Text('Send reset email'),
            ),
          ],
        ),
      ),
    );
  }
}
