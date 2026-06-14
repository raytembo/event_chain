// Widget test for EventChainApp.
//
// EventChainApp is pumped directly (we never call main()), so the real
// SupabaseService and EventChainFFI singletons are never touched.
// authProvider is overridden with a fake AuthNotifier so _AuthRouter can
// build and route correctly without a live Supabase connection or the
// native libEventChain.so.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eventchain/main.dart';
import 'package:eventchain/features/auth/auth_provider.dart';
import 'package:eventchain/features/auth/login_screen.dart';

/// Minimal [AuthNotifier] double that returns a fixed [AuthState] without
/// subscribing to Supabase's onAuthStateChange stream.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

void main() {
  testWidgets('shows the login screen when no user is signed in',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(const AuthState(loading: false)),
          ),
        ],
        child: const EventChainApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('EVENTCHAIN'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while the session is restoring',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(const AuthState(loading: true)),
          ),
        ],
        child: const EventChainApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
