import 'package:supabase_flutter/supabase_flutter.dart';
import '../api/api_client.dart';

class Session {
  Session({
    required this.api,
    required this.supabase,
  });

  final ApiClient api;
  final SupabaseClient supabase;
}
