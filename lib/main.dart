import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  await SupabaseService.init(
    url: 'https://oiqjukecidjjyvskgacs.supabase.co',
    anonKey: 'sb_publishable_bxVDb-O1-ME-tkM3w05MQg_QodsVeOR',
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
      home: const _DebugOverlay(child: _AuthRouter()),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TEMPORARY DEBUG WIDGET — tap the red bug button to run the native self-test
// ═════════════════════════════════════════════════════════════════════════════

class _DebugOverlay extends StatelessWidget {
  final Widget child;
  const _DebugOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'selfTestFab',
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              onPressed: () => _runSelfTest(context),
              child: const Icon(Icons.bug_report),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runSelfTest(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Running native self-test…')),
    );

    try {
      final tmp = await getTemporaryDirectory();
      final report = EventChainFFI.instance.selfTest(workDir: tmp.path);

      if (!context.mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D21),
          title: const Text('Self-Test Report'),
          content: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: report)),
              child: const Text('COPY'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (e, stack) {
      debugPrint('[SelfTest] ERROR: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Self-test crashed: $e')),
        );
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AUTH ROUTER
// ═════════════════════════════════════════════════════════════════════════════

class _AuthRouter extends ConsumerWidget {
  const _AuthRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.isLoggedIn && auth.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (!auth.isLoggedIn) return const LoginScreen();

    return switch (auth.role) {
      UserRole.owner => const OwnerRootScaffold(),
      UserRole.customer => const CustomerRootScaffold(),
      _ => const LoginScreen(),
    };
  }
}
