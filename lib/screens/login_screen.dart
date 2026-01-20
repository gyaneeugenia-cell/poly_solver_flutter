import 'package:flutter/material.dart';

import '../state/session.dart';
import 'register_screen.dart';
import 'solver_screen.dart';
import 'change_expired_password_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _showPassword = false;

Future<void> _login() async {
  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    final username = _userCtrl.text.trim();

    // ✅ FASTAPI LOGIN (NOT SUPABASE)
    await widget.session.api.login(
      username: username,
      password: _passCtrl.text,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login successful')),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SolverScreen(
          session: widget.session,
          userName: username,
          onLogout: _handleLogout,
        ),
      ),
    );
  } catch (e) {
    final msg = e.toString();

    // 🔒 PASSWORD EXPIRED FLOW
if (msg.contains('PASSWORD_EXPIRED')) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Password expired. Please change password to log in.',
      ),
      duration: Duration(seconds: 2),
    ),
  );

  await Future.delayed(const Duration(seconds: 2));

  if (!mounted) return;

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => ChangeExpiredPasswordScreen(
        session: widget.session,
        username: _userCtrl.text.trim(),
      ),
    ),
  );
  return;
}


    // ❌ NORMAL LOGIN ERROR
    setState(() {
      _error = msg.replaceAll('Exception: ', '');
    });
  } finally {
    setState(() {
      _loading = false;
    });
  }
}


  void _handleLogout() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(session: widget.session),
      ),
    );
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Polynomial Solver',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
              ),
              const SizedBox(height: 10),
TextButton(
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          session: widget.session,
        ),
      ),
    );
  },
  child: const Text('Forgot password?'),
),
const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            RegisterScreen(session: widget.session),
                      ),
                    );
                  },
                  child: const Text('Register new user'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
