// lib/main.dart
//
// Entry point. Initialises:
//   1. Supabase (auth + profiles)
//   2. EventChainFFI (native C++ blockchain)
// Then routes:
//   • Not logged in      → LoginScreen
//   • UserRole.owner     → OwnerRootScaffold
//   • UserRole.customer  → CustomerRootScaffold

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ffi_bridge/eventchain_ffi.dart';
import 'core/models/user_model.dart';
import 'core/services/supabase_service.dart';
import 'shared/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/owner/owner_root_scaffold.dart';
import 'features/customer/customer_root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialise Supabase (replaces Isar)
  await SupabaseService.init(
    url: 'https://oiqjukecidjjyvskgacs.supabase.co',
    anonKey: 'sb_publishable_bxVDb-O1-ME-tkM3w05MQg_QodsVeOR',
  );

  // 2. Initialise native blockchain library
  final docsDir      = await getApplicationDocumentsDirectory();
  final eventsFolder = Directory('${docsDir.path}/events');
  if (!eventsFolder.existsSync()) eventsFolder.createSync(recursive: true);
  await EventChainFFI.instance.init(eventsFolder.path);

  runApp(const ProviderScope(child: EventChainApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
class EventChainApp extends StatelessWidget {
  const EventChainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                     'EventChain',
      debugShowCheckedModeBanner: false,
      theme:                     AppTheme.dark(),
      home:                      const _AuthRouter(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Watches authProvider and rebuilds the root widget when auth state changes.
// ─────────────────────────────────────────────────────────────────────────────
class _AuthRouter extends ConsumerWidget {
  const _AuthRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    // Full-screen loader while session is being restored on first frame.
    if (!auth.isLoggedIn && auth.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
        ),
      );
    }

    if (!auth.isLoggedIn) return const LoginScreen();

    // Switch on the concrete UserRole value — null case handled above.
    return switch (auth.role) {
      UserRole.owner    => const OwnerRootScaffold(),
      UserRole.customer => const CustomerRootScaffold(),
      _                 => const LoginScreen(),   // covers null + future roles
    };
  }
}