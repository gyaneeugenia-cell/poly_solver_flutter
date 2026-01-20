import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'state/session.dart' as app_session;
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://hjpvjqttenxhokifulpw.supabase.co',
    anonKey: 'sb_publishable_94OoXnsI5LsZ-5sck-Ozkw_M95mvGAS',
  );

  final session = app_session.Session(
    api: ApiClient(
      baseUrl: 'https://poly-backend-o5f1.onrender.com',
    ),
    supabase: Supabase.instance.client,
  );

  runApp(PolySolverApp(session: session));
}

class PolySolverApp extends StatefulWidget {
  final app_session.Session session;
  const PolySolverApp({super.key, required this.session});

  @override
  State<PolySolverApp> createState() => _PolySolverAppState();
}

class _PolySolverAppState extends State<PolySolverApp> {
  StreamSubscription? _linkSub;
  Widget _home = const SizedBox();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle cold start
    final initialUri = await getInitialUri();
    _handleUri(initialUri);

    // Handle app already open
    _linkSub = uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  void _handleUri(Uri? uri) {
    if (uri == null) {
      setState(() {
        _home = LoginScreen(session: widget.session);
      });
      return;
    }

    // https://.../reset-password?email=...&token=...
    if (uri.path.contains('reset-password')) {
      final email = uri.queryParameters['email'];
      final token = uri.queryParameters['token'];

      if (email != null && token != null) {
        setState(() {
          _home = ResetPasswordScreen(
            session: widget.session,
            email: email,
            token: token,
          );
        });
        return;
      }
    }

    // Fallback
    setState(() {
      _home = LoginScreen(session: widget.session);
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _home,
    );
  }
}
