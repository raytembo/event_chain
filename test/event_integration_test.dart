// integration_test/event_integration_test.dart
//
// Integration test for the native EventChain shared library.
//
// ── How to run ────────────────────────────────────────────────────────────────
// This test requires:
//   1. The native library to be compiled:
//        • Android/Linux : libEventChain.so  (placed in android/app/src/main/jniLibs/<ABI>/)
//        • macOS         : libEventChain.dylib (placed in macos/Runner/)
//   2. A connected device or simulator:
//        flutter test integration_test/event_integration_test.dart
//
// When the library is not present (e.g. in CI before the C++ build step),
// the test skips automatically rather than failing the suite.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eventchain/core/ffi_bridge/eventchain_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EventChain Native Shared Library Integration Tests', () {
    late Directory workDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('eventchain_integ_');
    });

    tearDownAll(() async {
      // Ensure the handle is released even if a test throws.
      EventChainFFI.instance.dispose();
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    testWidgets(
      'Verify real libEventChain selfTest diagnostics routine execution',
      (tester) async {
        final bridge = EventChainFFI.instance;

        // ── Skip gracefully when the native library has not been built yet ──
        try {
          await bridge.init(workDir.path);
        } on ArgumentError catch (e) {
          // dlopen / LoadLibrary failed — library not present.
          // markTestSkipped ends the test as "skipped", not "failed".
          markTestSkipped(
            'Native library not available — build libEventChain first. '
            'Details: $e',
          );
          return;
        } on StateError catch (e) {
          markTestSkipped('eventchain_create() returned null: $e');
          return;
        }

        // ── Library loaded; run the real diagnostics ──────────────────────
        final diagnosticLog = bridge.selfTest(workDir: workDir.path);

        expect(diagnosticLog, isNotNull);
        expect(diagnosticLog, isNotEmpty);
        expect(
          diagnosticLog.toLowerCase(),
          contains('pass'),
          reason:
              'selfTest output should contain "pass" when all checks succeed',
        );
      },
    );
  });
}
