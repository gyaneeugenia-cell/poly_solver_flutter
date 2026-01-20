import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  String? _token;

  ApiClient({required this.baseUrl});

  // --------------------
  // LOGIN
  // --------------------
Future<void> login({
  required String username,
  required String password,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/login'),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    },
    body: {
      'username': username,
      'password': password,
    },
  );

if (response.statusCode != 200) {
  final body = jsonDecode(response.body);
  throw Exception(body['detail'] ?? 'Login failed');
}


  final data = jsonDecode(response.body);
  _token = data['access_token'];
}



  // --------------------
  // REGISTER
  // --------------------
Future<void> register({
  required String username,
  required String password,
}) async {

  // Frontend validation to match backend rules
  if (password.length < 6) {
    throw Exception('Password must be at least 6 characters long');
  }

  final response = await http
      .post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      )
      .timeout(const Duration(seconds: 60));

  if (response.statusCode != 200) {
    throw Exception('Registration failed: ${response.body}');
  }
}



  // --------------------
  // SOLVE POLYNOMIAL
  // --------------------
  Future<SolveResult> solve({
    required int degree,
    required List<double> coeffs,
    required double xMin,
    required double xMax,
  }) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/solve'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'degree': degree,
        'coeffs': coeffs,
        'x_min': xMin,
        'x_max': xMax,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Solve failed');
    }

    return SolveResult.fromJson(jsonDecode(response.body));
  }
    // --------------------
  // LOAD ADMIN HISTORY
  // --------------------
  Future<List<Map<String, dynamic>>> adminHistory({int limit = 100}) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/admin/history'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Not admin');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = decoded['items'] as List<dynamic>;
    return items.cast<Map<String, dynamic>>();
  }
  // --------------------
  // LOAD HISTORY
  // --------------------
  Future<List<Map<String, dynamic>>> history({int limit = 50}) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/history?limit=$limit');

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load history');
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
    // --------------------
  // FORGOT PASSWORD
  // --------------------
  Future<void> forgotPassword({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/forgot-password'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send reset email');
    }
  }

  // --------------------
  // RESET PASSWORD
  // --------------------
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reset-password'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'token': token,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

  // --------------------
  // CHANGE EXPIRED PASSWORD
  // --------------------
  Future<void> changeExpiredPassword({
    required String username,
    required String oldPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/change-expired-password'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

}



// --------------------
// RESULT MODEL
// --------------------
class SolveResult {
  final String equation;
  final List<ComplexRoot> roots;

  SolveResult({
    required this.equation,
    required this.roots,
  });

  factory SolveResult.fromJson(Map<String, dynamic> json) {
    return SolveResult(
      equation: json['equation'],
      roots: (json['roots'] as List)
          .map((e) => ComplexRoot.fromJson(e))
          .toList(),
    );
  }
}

class ComplexRoot {
  final double re;
  final double im;

  ComplexRoot({
    required this.re,
    required this.im,
  });

  factory ComplexRoot.fromJson(Map<String, dynamic> json) {
    return ComplexRoot(
      re: (json['re'] as num).toDouble(),
      im: (json['im'] as num).toDouble(),
    );
  }
}
