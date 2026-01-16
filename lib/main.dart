import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'state/session.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const PolySolverApp());
}

class PolySolverApp extends StatelessWidget {
  const PolySolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polynomial Solver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: LoginScreen(
        session: Session(
          ApiClient(baseUrl: 'https://poly-backend-o5f1.onrender.com'),

        ),
      ),
    );
  }
}
