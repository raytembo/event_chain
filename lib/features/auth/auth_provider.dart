// lib/features/auth/auth_provider.dart
//
// Session restore is driven by Supabase's onAuthStateChange stream instead of
// a fire-and-forget _init() call.  The stream ALWAYS emits at least one event
// on startup (session present OR null), so `loading` is guaranteed to clear.
//
// login() / register() still mutate state directly for immediate UI feedback
// and to capture profile-not-found errors.  The stream listener ignores events
// that arrive while an explicit login/register is in progress to avoid a
// redundant double-fetch.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/user_model.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthState
// ─────────────────────────────────────────────────────────────────────────────
class AuthState {
  final AppUser? user;
  final bool loading;
  final String? error;

  const AuthState({
    this.user,
    this.loading = false,
    this.error,
  });

  bool get isLoggedIn => user != null;
  UserRole? get role => user?.role;

  AuthState copyWith({
    AppUser? user,
    bool clearUser = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      AuthState(
        user: clearUser ? null : user ?? this.user,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthNotifier
// ─────────────────────────────────────────────────────────────────────────────
class AuthNotifier extends Notifier<AuthState> {
  static const _lastEmailKey = 'ec_last_email';

  // While login() or register() is running we own the state update, so we
  // tell the stream listener to stand down.
  bool _explicitAuthInProgress = false;

  SupabaseService get _supa => SupabaseService.instance;

  @override
  AuthState build() {
    _subscribeToAuthChanges();
    // Stream fires immediately on startup — loading is cleared by the first event.
    return const AuthState(loading: true);
  }

  // ── Stream-based session restore ───────────────────────────────────────────
  //
  // onAuthStateChange emits one event as soon as the Supabase client is ready:
  //   • session == null  →  no stored session  →  clear loading, show login
  //   • session != null  →  restore session    →  fetch profile, update state
  //
  // This replaces the old fire-and-forget _init() which could hang silently.

  void _subscribeToAuthChanges() {
    final sub = _supa.auth.onAuthStateChange.listen(
      (event) async {
        // login() / register() handle their own state; skip the stream update.
        if (_explicitAuthInProgress) return;

        final session = event.session;

        if (session == null) {
          // No session: go straight to login screen.
          state = state.copyWith(clearUser: true, loading: false, clearError: true);
          return;
        }

        // Session present: fetch the profile row.
        try {
          final profile = await _fetchProfile(session.user.id)
              .timeout(const Duration(seconds: 8));

          if (profile != null) {
            state = state.copyWith(user: profile, loading: false);
            await _persistLastEmail(profile.email);
          } else {
            // Trigger exists but profile row is missing — treat as logged out.
            state = state.copyWith(clearUser: true, loading: false);
          }
        } catch (_) {
          // Timeout, network error, RLS block, bad anon key, etc.
          // Non-fatal — fall through to logged-out state.
          state = state.copyWith(clearUser: true, loading: false);
        }
      },
      onError: (_) {
        // Stream-level error (e.g. bad config) — always clear the spinner.
        if (!_explicitAuthInProgress) {
          state = state.copyWith(clearUser: true, loading: false);
        }
      },
    );

    // Cancel the subscription when the notifier is disposed.
    ref.onDispose(sub.cancel);
  }

  // ── Register ───────────────────────────────────────────────────────────────

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    _explicitAuthInProgress = true;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final normalised = email.trim().toLowerCase();

      // Pass full_name + role in metadata so the handle_new_user() Postgres
      // trigger can create the profiles row correctly.
      final response = await _supa.auth.signUp(
        email: normalised,
        password: password,
        data: {
          'full_name': displayName.trim(),
          'role': role.name, // 'owner' | 'customer'
        },
      );

      final authUser = response.user;
      if (authUser == null) {
        state = state.copyWith(
          loading: false,
          error: 'Registration failed — please try again.',
        );
        return false;
      }

      // The trigger only writes id, email, display_name, role.
      // Optional fields need a follow-up UPDATE.
      final extras = <String, dynamic>{
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
          'avatar_url': avatarUrl.trim(),
      };
      if (extras.isNotEmpty) {
        await _supa.profiles.update(extras).eq('id', authUser.id);
      }

      final profile = await _fetchProfile(authUser.id);
      if (profile != null) {
        await _persistLastEmail(normalised);
        state = state.copyWith(loading: false, user: profile);
      } else {
        state = state.copyWith(loading: false);
      }

      return true;
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    } finally {
      _explicitAuthInProgress = false;
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _explicitAuthInProgress = true;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final normalised = email.trim().toLowerCase();

      final response = await _supa.auth.signInWithPassword(
        email: normalised,
        password: password,
      );

      final authUser = response.user;
      if (authUser == null) {
        state = state.copyWith(
          loading: false,
          error: 'Login failed — please try again.',
        );
        return false;
      }

      final profile = await _fetchProfile(authUser.id);
      if (profile == null) {
        state = state.copyWith(
          loading: false,
          error: 'Profile not found. Please contact support.',
        );
        return false;
      }

      await _persistLastEmail(normalised);
      // Setting user here causes _AuthRouter to rebuild and route correctly.
      state = state.copyWith(loading: false, user: profile);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    } finally {
      _explicitAuthInProgress = false;
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _supa.auth.signOut();
    // signOut() triggers onAuthStateChange with session == null, which will
    // clear the state via the stream listener.  We also clear prefs here.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastEmailKey);
  }

  // ── Update profile ─────────────────────────────────────────────────────────

  Future<bool> updateProfile(Map<String, dynamic> fields) async {
    final uid = state.user?.id;
    if (uid == null) return false;

    state = state.copyWith(loading: true, clearError: true);
    try {
      await _supa.profiles.update(fields).eq('id', uid);
      final updated = await _fetchProfile(uid);
      state = state.copyWith(loading: false, user: updated);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<AppUser?> _fetchProfile(String uid) async {
    final data = await _supa.profiles.select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return AppUser.fromMap(data);
  }

  Future<void> _persistLastEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastEmailKey, email);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);