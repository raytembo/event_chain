// Widget tests for LoginScreen (lib/features/auth/login_screen.dart).
//
// AuthNotifier.login() normally calls Supabase, which isn't available in a
// plain `flutter test` run. We swap it out with FakeAuthNotifier, a small
// test double that:
//   - skips the real onAuthStateChange subscription in build()
//   - lets each test script whether login() succeeds or fails, and inspect
//     what email/password were submitted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eventchain/core/models/user_model.dart';
import 'package:eventchain/features/auth/auth_provider.dart';
import 'package:eventchain/features/auth/login_screen.dart';

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier({this.loginResult = true, this.loginError});

  /// What login() should return.
  final bool loginResult;

  /// Error message to set on state when [loginResult] is false.
  final String? loginError;

  int loginCallCount = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  AuthState build() => const AuthState(loading: false);

  @override
  Future<bool> login({required String email, required String password}) async {
    loginCallCount++;
    lastEmail = email;
    lastPassword = password;

    if (loginResult) {
      state = state.copyWith(
        loading: false,
        clearError: true,
        user: AppUser(
          id: 'usr-1',
          email: email,
          displayName: 'Test User',
          role: UserRole.customer,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      state = state.copyWith(
        loading: false,
        error: loginError ?? 'Login failed — please try again.',
      );
    }
    return loginResult;
  }
}

Future<void> _pumpLoginScreen(
  WidgetTester tester,
  AuthNotifier Function() notifier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(notifier)],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  // One extra frame for the looping pulse animation. Avoid pumpAndSettle()
  // here — the logo animation repeats forever and would never "settle".
  await tester.pump();
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders branding and the email/password form', (tester) async {
      await _pumpLoginScreen(tester, FakeAuthNotifier.new);

      expect(find.text('EVENTCHAIN'), findsOneWidget);
      expect(find.text('EMAIL'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('shows "Required" for both fields when submitted empty',
        (tester) async {
      await _pumpLoginScreen(tester, FakeAuthNotifier.new);

      await tester.tap(find.text('SIGN IN'));
      await tester.pump();

      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('shows an error when the email is missing an @',
        (tester) async {
      await _pumpLoginScreen(tester, FakeAuthNotifier.new);

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('SIGN IN'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('submits the entered email and password to AuthNotifier.login',
        (tester) async {
      final fake = FakeAuthNotifier();
      await _pumpLoginScreen(tester, () => fake);

      await tester.enterText(
          find.byType(TextFormField).first, 'ray@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'sup3rSecret');
      await tester.tap(find.text('SIGN IN'));
      await tester.pump();

      expect(fake.loginCallCount, 1);
      expect(fake.lastEmail, 'ray@example.com');
      expect(fake.lastPassword, 'sup3rSecret');
    });

    testWidgets('shows a snackbar with the error message on failed login',
        (tester) async {
      await _pumpLoginScreen(
        tester,
        () => FakeAuthNotifier(
          loginResult: false,
          loginError: 'Profile not found. Please contact support.',
        ),
      );

      await tester.enterText(
          find.byType(TextFormField).first, 'ray@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'wrongpass');
      await tester.tap(find.text('SIGN IN'));
      await tester.pump(); // run the async login()
      await tester
          .pump(const Duration(milliseconds: 300)); // animate the SnackBar in

      expect(find.text('Profile not found. Please contact support.'),
          findsOneWidget);
    });

    testWidgets('toggles password visibility via the eye icon', (tester) async {
      await _pumpLoginScreen(tester, FakeAuthNotifier.new);

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });
  });
}
