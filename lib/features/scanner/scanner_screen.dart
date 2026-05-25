// lib/features/scanner/scanner_screen.dart
//
// Gate-staff ticket scanner.
// The C++ layer uses stb_image for decoding, which natively supports JPEG,
// PNG, and BMP — no Dart-side format conversion is required.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../shared/theme/app_theme.dart';
import '../events/events_provider.dart';
import 'verification_result_screen.dart';

// ── Structured errors ─────────────────────────────────────────────────────

sealed class ScanError implements Exception {
  final String message;
  const ScanError(this.message);
  @override
  String toString() => message;
}

final class ImageReadError extends ScanError {
  const ImageReadError(super.message);
}

final class NoChainsError extends ScanError {
  const NoChainsError() : super('No event chains available');
}

final class VerificationInterrupted extends ScanError {
  const VerificationInterrupted() : super('Scan interrupted');
}

// ── Auto-delete file helper ───────────────────────────────────────────────

class _AutoDeleteFile {
  final String path;
  bool _deleted = false;
  _AutoDeleteFile(this.path);

  void dispose() {
    if (_deleted) return;
    _deleted = true;
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  bool _scanning = false;
  String _statusMessage = '';
  Future<void>? _pendingScan;

  // ── Safe setState ─────────────────────────────────────────────────────
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _setStatus(String msg) => _safeSetState(() => _statusMessage = msg);

  // ── Image sources ─────────────────────────────────────────────────────
  Future<void> _scanWithCamera() => _startScan(ImageSource.camera);
  Future<void> _pickFromGallery() => _startScan(ImageSource.gallery);

  Future<void> _startScan(ImageSource source) async {
    if (_pendingScan != null) return;
    final completer = Completer<void>();
    _pendingScan = completer.future;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        // FIX (Bug 1): Do NOT set maxWidth / maxHeight here.
        //
        // On Android, specifying either dimension forces the platform to
        // re-encode the image before handing it back to Dart, even when
        // imageQuality is 100. Re-encoding alters every LSB in the file
        // and silently destroys the steganographic payload, causing
        // extractAndVerify() to always return false.
        //
        // The C++ stb_image layer accepts any size natively, so no
        // client-side resize is needed.
        imageQuality: 100,
      );
      if (picked != null) await _verifyImage(picked.path);
    } finally {
      completer.complete();
      _pendingScan = null;
    }
  }

  // ── Core pipeline ─────────────────────────────────────────────────────
  Future<void> _verifyImage(String sourcePath) async {
    _safeSetState(() {
      _scanning = true;
      _statusMessage = 'Reading image…';
    });

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : 'jpg';

    // Persist a stable copy — the picker's temp path may be evicted.
    final String persistentPath;
    try {
      final src = File(sourcePath);
      if (!await src.exists()) {
        throw const ImageReadError('Source image no longer exists');
      }
      persistentPath = '${tempDir.path}/scan_orig_$ts.$ext';
      await src.copy(persistentPath);
    } on ScanError {
      rethrow;
    } catch (e) {
      throw ImageReadError('Could not read image: $e');
    }

    final persistentFile = _AutoDeleteFile(persistentPath);

    try {
      final fileBytes = await File(persistentPath).length();
      if (fileBytes < 1024) {
        throw ImageReadError(
            'Image too small (${fileBytes}B) — likely corrupt');
      }

      debugPrint(
          '[Scanner] Image ready: $persistentPath (${(fileBytes / 1024).toStringAsFixed(1)} KB)');

      // Ensure chains are loaded
      final ffi = EventChainFFI.instance;
      List<String> eventNames = ffi.listEvents();

      if (eventNames.isEmpty) {
        _setStatus('Fetching event chains from server…');
        eventNames = await _tryDownloadChains();
      }

      if (eventNames.isEmpty) throw const NoChainsError();

      // FFI verification — C++ stb_image reads JPEG, PNG, and BMP natively
      final result = await _runVerification(ffi, eventNames, persistentPath);

      // Supabase cross-check
      Map<String, dynamic>? dbData;
      if (result.verified &&
          result.eventName != null &&
          result.blockIndex != null) {
        _setStatus('Loading ticket details…');
        dbData =
            await _supabaseLookupByBlock(result.eventName!, result.blockIndex!);
      } else {
        _setStatus('Checking ticket database…');
        dbData = await _supabaseLookupByImageHash(persistentPath);
      }

      if (!mounted) throw const VerificationInterrupted();

      _safeSetState(() => _scanning = false);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationResultScreen(
            authentic: result.verified,
            imagePath: persistentPath,
            eventName: result.eventName,
            blockIndex: result.blockIndex,
            supabaseTicketData: dbData,
          ),
        ),
      );
    } on VerificationInterrupted {
      debugPrint('[Scanner] Widget unmounted during scan');
    } on ScanError catch (e) {
      _safeSetState(() => _scanning = false);
      _showError(e.message);
    } catch (e, stack) {
      debugPrint('[Scanner] Unexpected error: $e\n$stack');
      _safeSetState(() => _scanning = false);
      _showError('Unexpected error: $e');
    } finally {
      persistentFile.dispose();
    }
  }

  // ── Verification loop ─────────────────────────────────────────────────
  Future<_ScanResult> _runVerification(
    EventChainFFI ffi,
    List<String> eventNames,
    String imagePath,
  ) async {
    for (final eventName in eventNames) {
      if (!mounted) break;

      final chainSize = ffi.getEventSize(eventName);
      if (chainSize <= 1) continue;

      for (int i = 1; i < chainSize; i++) {
        if (!mounted) break;

        _setStatus('Checking $eventName · block $i / ${chainSize - 1}…');

        try {
          final ok = await ffi.extractAndVerify(
            stegoPath: imagePath,
            eventName: eventName,
            blockIndex: i,
          );
          if (ok) {
            debugPrint('[Scanner] MATCH → $eventName block $i');
            return _ScanResult(
                verified: true, eventName: eventName, blockIndex: i);
          }
        } catch (e, stack) {
          debugPrint('[Scanner] block $i error (skipping): $e\n$stack');
          continue;
        }
      }
    }
    return const _ScanResult(verified: false);
  }

  // ── Chain download ────────────────────────────────────────────────────
  Future<List<String>> _tryDownloadChains() async {
    try {
      final supabase = Supabase.instance.client;
      final rows =
          await supabase.from('events').select('id, event_name').limit(50);

      // FIX (Bug 4): Guard against widget disposal between the await above
      // and the ref.read call below. In Riverpod 2.x, accessing a WidgetRef
      // after disposal throws StateError. Returning [] is safe — the caller
      // will throw NoChainsError which shows a readable snackbar.
      if (!mounted) return [];

      final notifier = ref.read(eventsProvider.notifier);
      final events = List<Map<String, dynamic>>.from(rows);

      // Download up to 4 chains concurrently
      final chunks = _chunk(events, 4);
      for (final chunk in chunks) {
        await Future.wait(chunk.map((row) async {
          final name = row['event_name'] as String?;
          if (name != null) await notifier.loadRemoteChain(name);
        }));
      }

      return EventChainFFI.instance.listEvents();
    } catch (e) {
      debugPrint('[Scanner] chain download error: $e');
      return [];
    }
  }

  List<List<T>> _chunk<T>(List<T> list, int size) => [
        for (int i = 0; i < list.length; i += size)
          list.sublist(i, (i + size < list.length) ? i + size : list.length),
      ];

  // ── Supabase lookups ──────────────────────────────────────────────────

  // FIX (Bug 2): Query the `v_ticket_detail` view instead of the raw
  // `tickets` table.
  //
  // The `tickets` table stores `event_id` (a UUID FK to `events`), NOT
  // `event_name`. Querying `.eq('event_name', ...)` against `tickets`
  // causes PostgREST to throw a 400 "column does not exist" error every
  // time, which was silently swallowed — meaning `dbData` was always null
  // on a successful local verification and the DB record was never shown.
  //
  // `v_ticket_detail` is the joined view that exposes `event_name` (and
  // venue, event_date, poster_url, etc.) alongside all `tickets` columns.
  // This is the same view used by `TicketRecord.fromMap` / `toFFIModel`.
  Future<Map<String, dynamic>?> _supabaseLookupByBlock(
    String eventName,
    int blockIndex,
  ) async {
    try {
      return await Supabase.instance.client
          .from('v_ticket_detail')
          .select()
          .eq('event_name', eventName)
          .eq('block_index', blockIndex)
          .maybeSingle();
    } catch (e) {
      debugPrint('[Scanner] Supabase block lookup error: $e');
      return null;
    }
  }

  /// Fallback: perceptual hash lookup (not yet implemented).
  Future<Map<String, dynamic>?> _supabaseLookupByImageHash(
      String imagePath) async {
    // TODO: implement ImageHasher.perceptualHash(imagePath)
    return null;
  }

  // ── UI helpers ────────────────────────────────────────────────────────
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: Text('Ticket Scanner', style: AppTheme.merri(fontSize: 20)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _scanning ? _buildScanning() : _buildIdle(),
      ),
    );
  }

  Widget _buildScanning() {
    return Center(
      key: const ValueKey('scanning'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'VERIFYING TICKET',
              style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _statusMessage,
                key: ValueKey(_statusMessage),
                textAlign: TextAlign.center,
                style:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Center(
      key: const ValueKey('idle'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                width: 3,
              ),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              size: 80,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Scan Ticket',
            style: AppTheme.merri(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Point the camera at a ticket image\nor pick one from your gallery.',
            textAlign: TextAlign.center,
            style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
          ),
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _scanWithCamera,
                icon: const Icon(Icons.camera_alt, size: 22),
                label: Text(
                  'OPEN CAMERA',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _pickFromGallery,
            icon: const Icon(
              Icons.photo_library_outlined,
              color: AppTheme.subTextColor,
              size: 20,
            ),
            label: Text(
              'Choose from Gallery',
              style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

// ── Internal result type ──────────────────────────────────────────────────
class _ScanResult {
  final bool verified;
  final String? eventName;
  final int? blockIndex;
  const _ScanResult({
    required this.verified,
    this.eventName,
    this.blockIndex,
  });
}
