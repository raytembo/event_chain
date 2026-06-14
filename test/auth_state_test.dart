// Unit tests for AuthState (lib/features/auth/auth_provider.dart).
//
// Tests only the plain data class — AuthNotifier itself talks to Supabase
// and is exercised indirectly via the fake notifier in login_screen_test.dart
// and widget_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:eventchain/core/models/user_model.dart';
import 'package:eventchain/features/auth/auth_provider.dart';

AppUser _dummyUser({UserRole role = UserRole.customer}) => AppUser(
      id: 'usr-1',
      email: 'test@example.com',
      displayName: 'Test User',
      role: role,
      createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
      updatedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
    );

void main() {
  group('AuthState', () {
    test('defaults to logged out, not loading, with no error', () {
      const state = AuthState();

      expect(state.isLoggedIn, isFalse);
      expect(state.role, isNull);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
    });

    test('isLoggedIn and role reflect the current user', () {
      final state = AuthState(user: _dummyUser(role: UserRole.owner));

      expect(state.isLoggedIn, isTrue);
      expect(state.role, UserRole.owner);
    });

    test('copyWith updates loading without affecting other fields', () {
      final original = AuthState(user: _dummyUser());
      final updated = original.copyWith(loading: true);

      expect(updated.loading, isTrue);
      expect(updated.user, original.user);
      expect(updated.error, original.error);
    });

    test('copyWith(clearUser: true) logs the user out', () {
      final loggedIn = AuthState(user: _dummyUser());
      final loggedOut = loggedIn.copyWith(clearUser: true, loading: false);

      expect(loggedOut.isLoggedIn, isFalse);
      expect(loggedOut.user, isNull);
      expect(loggedOut.role, isNull);
    });

    test('copyWith(clearError: true) removes an existing error', () {
      const withError = AuthState(error: 'Login failed');
      final cleared = withError.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith preserves the existing error when no new one is given', () {
      const withError = AuthState(error: 'Profile not found.');
      final stillLoading = withError.copyWith(loading: true);

      expect(stillLoading.error, 'Profile not found.');
      expect(stillLoading.loading, isTrue);
    });

    test('copyWith can set a new error message', () {
      const initial = AuthState();
      final withError = initial.copyWith(error: 'Network error');

      expect(withError.error, 'Network error');
    });
  });
}
