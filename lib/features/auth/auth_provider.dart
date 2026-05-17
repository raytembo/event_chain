// lib/features/auth/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/user_model.dart';
import '../../core/services/supabase_service.dart';

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

class AuthNotifier extends Notifier<AuthState> {
  static const _lastEmailKey = 'ec_last_email';

  SupabaseService get _supa => SupabaseService.instance;

  @override
  AuthState build() {
    _init();
    return const AuthState();
  }

  Future<void> _init() async {
    final currentUser = _supa.auth.currentUser;
    if (currentUser != null) {
      final profile = await _fetchProfile(currentUser.id);
      if (profile != null) {
        state = state.copyWith(user: profile);
        await _persistLastEmail(profile.email);
      }
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final normalised = email.trim().toLowerCase();

      final response = await _supa.auth.signUp(
        email: normalised,
        password: password,
      );

      final authUser = response.user;
      if (authUser == null) {
        state = state.copyWith(
          loading: false,
          error: 'Registration failed — please try again.',
        );
        return false;
      }

      final user = AppUser(
        id: authUser.id,
        email: normalised,
        displayName: displayName.trim(),
        role: role,
        createdAt: DateTime.now(),
        phone: phone?.trim(),
        bio: bio?.trim(),
        avatarUrl: avatarUrl?.trim(),
      );

      await _supa.profiles.insert(user.toMap());
      await _persistLastEmail(normalised);
      state = state.copyWith(loading: false, user: user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
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
        state = state.copyWith(loading: false, error: 'Profile not found.');
        return false;
      }

      await _persistLastEmail(normalised);
      state = state.copyWith(loading: false, user: profile);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    await _supa.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastEmailKey);
    state = state.copyWith(clearUser: true, clearError: true);
  }

  Future<AppUser?> _fetchProfile(String uid) async {
    final data = await _supa.profiles
        .select()
        .eq('id', uid)
        .maybeSingle();
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