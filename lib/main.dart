import 'dart:io';
import 'package:eventchain/features/scanner/verifier_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/ffi_bridge/eventchain_ffi.dart';
import 'core/models/user_model.dart';
import 'core/services/supabase_service.dart';
import 'shared/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/owner/owner_root_scaffold.dart';
import 'features/customer/customer_root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await SupabaseService.init(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final docsDir = await getApplicationDocumentsDirectory();
  final eventsFolder = Directory('${docsDir.path}/events');
  if (!eventsFolder.existsSync()) eventsFolder.createSync(recursive: true);
  await EventChainFFI.instance.init(eventsFolder.path);

  runApp(const ProviderScope(child: EventChainApp()));
}

class EventChainApp extends StatefulWidget {
  const EventChainApp({super.key});

  @override
  State<EventChainApp> createState() => _EventChainAppState();
}

class _EventChainAppState extends State<EventChainApp> {
  @override
  void dispose() {
    EventChainFFI.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EventChain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const _AuthRouter(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AUTH ROUTER
// ═════════════════════════════════════════════════════════════════════════════
//
// _AuthRouter must stay mounted for the entire time the user is logged out —
// this is the widget that watches authProvider and swaps to the correct root
// scaffold the instant login()/register() sets a user. Previously, the login
// and register screens used Navigator.pushReplacement on each other, which
// replaced _AuthRouter's own route and removed it from the tree entirely —
// after that, nothing was left listening for the auth state change, so the
// redirect silently failed until the next hot reload/restart remounted
// _AuthRouter fresh. _AuthGate below fixes this by toggling between login
// and register via local setState, so _AuthRouter (and its watch) never
// leaves the widget tree.

class _AuthRouter extends ConsumerWidget {
  const _AuthRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.isLoggedIn && auth.loading) {
      return Scaffold(
        backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (!auth.isLoggedIn) return const _AuthGate();

    // Route dynamically based on the decoded profile role
    return switch (auth.role) {
      UserRole.owner => const OwnerRootScaffold(),
      UserRole.customer => const CustomerRootScaffold(),
      UserRole.verifier =>
        const VerifierDashboardScreen(), // NEW: Verifier routing
      _ => const _AuthGate(),
    };
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AUTH GATE — swaps login/register in place, no Navigator involved
// ═════════════════════════════════════════════════════════════════════════════

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _showRegister = false;

  @override
  Widget build(BuildContext context) {
    return _showRegister
        ? RegisterScreen(
            onBackToLogin: () => setState(() => _showRegister = false),
          )
        : LoginScreen(
            onRegisterTap: () => setState(() => _showRegister = true),
          );
  }
}
