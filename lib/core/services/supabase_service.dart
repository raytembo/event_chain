// lib/core/services/supabase_service.dart
//
// Thin singleton wrapper around the Supabase client.
// Call SupabaseService.init() once from main() before runApp().

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  // ── Initialise — call once in main() ─────────────────────────────────────
  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  // ── Client accessor ───────────────────────────────────────────────────────
  SupabaseClient get client => Supabase.instance.client;

  GoTrueClient get auth => client.auth;

  // ── Profiles table helpers ────────────────────────────────────────────────
  SupabaseQueryBuilder get profiles => client.from('profiles');
}