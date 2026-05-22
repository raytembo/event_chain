// lib/features/events/events_provider.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../../core/services/supabase_storage_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────
class EventsState {
  
  final List<String> eventNames;
  final bool loading;
  final String? error;
  final Set<String> syncing;

  const EventsState({
    this.eventNames = const [],
    this.loading = false,
    this.error,
    this.syncing = const {},
  });

  EventsState copyWith({
    List<String>? eventNames,
    bool? loading,
    String? error,
    bool clearError = false,
    Set<String>? syncing,
  }) =>
      EventsState(
        eventNames: eventNames ?? this.eventNames,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
        syncing: syncing ?? this.syncing,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class EventsNotifier extends Notifier<EventsState> {
  final _ffi = EventChainFFI.instance;
  final _storage = SupabaseStorageService.instance;
  final _supabase = Supabase.instance.client;

  @override
  EventsState build() => const EventsState(loading: true);

  void refresh() {
    try {
      state = state.copyWith(
        eventNames: _ffi.listEvents(),
        loading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> loadRemoteChain(String eventName) async {
    state = state.copyWith(syncing: {...state.syncing, eventName});
    try {
      final eventsDir = await _eventsDir();
      final ok = await _storage.downloadBlockchainFile(
        eventName: eventName,
        localEventsDir: eventsDir,
      );
      if (ok) {
        _ffi.loadEvent(eventName);
        refresh();
      }
      state = state.copyWith(
        syncing: state.syncing.where((e) => e != eventName).toSet(),
      );
      return ok;
    } catch (e) {
      state = state.copyWith(
        syncing: state.syncing.where((e) => e != eventName).toSet(),
        error: e.toString(),
      );
      return false;
    }
  }

  Future<Map<String, double>> getTicketPrices(String eventId) async {
    try {
      final res = await _supabase
          .from('event_ticket_types')
          .select('ticket_type, price')
          .eq('event_id', eventId);

      return {
        for (final row in List<Map<String, dynamic>>.from(res))
          row['ticket_type'] as String: (row['price'] as num).toDouble(),
      };
    } catch (e) {
      debugPrint('❌ Failed to load ticket prices: $e');
      return {};
    }
  }

  /// Creates a ticket, embeds it via steganography, and syncs everything to
  /// Supabase storage.  Returns `(true, localStegoPath)` on full success.
  Future<(bool success, String? stegoLocalPath)> addTicket({
    required String eventName,
    required String eventId,
    required String posterUrl,
    required String ownerName,
    required String ownerID,
    required String eventDate,
    required String venue,
    required String ticketType,
    required double price,
  }) async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      debugPrint('=== TICKET CREATION START ===');
      debugPrint(
          'Event: $eventName | ID: $eventId | Type: $ticketType | Price: MWK $price');

      // FIX: resolve BOTH directories up-front so we can search all candidate
      // locations when looking for the blockchain file later.
      final appDocDir = (await getApplicationDocumentsDirectory()).path;
      final eventsDir = '$appDocDir/events';
      await Directory(eventsDir).create(recursive: true);

      final tempPath = (await getTemporaryDirectory()).path;

      // ── Step 1: Build ticket model ─────────────────────────────────────────
      final ticket = TicketModel(
        ticketID: const Uuid().v4().substring(0, 8).toUpperCase(),
        eventName: eventName,
        eventDate: eventDate,
        venue: venue,
        ownerName: ownerName,
        ownerID: ownerID,
        ticketType: ticketType,
        price: price,
      );

      // ── Step 2: Mine block in C++ ──────────────────────────────────────────
      final mined = await _ffi.addTicket(eventName, ticket);
      if (!mined) throw Exception('Mining failed in native layer');

      // blockIndex is 0-based (C++ chain index).
      // storageIndex is 1-based so filenames match: ticket_1, ticket_2, …
      final blockIndex = _ffi.getEventSize(eventName) - 1;
      final storageIndex = blockIndex + 1;

      debugPrint(
          '✅ Block mined — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 3: Download poster + embed steganography ──────────────────────
      final coverLocalPath = await _storage.downloadEventPosterToTemp(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempPath,
      );

      // C++ writes PNG directly via stb_image_write.
      final finalStegoPath = '$tempPath/stego_${ticket.ticketID}.png';

      bool embedOk;
      if (coverLocalPath != null && await File(coverLocalPath).exists()) {
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          coverPath: coverLocalPath,
          stegoPath: finalStegoPath,
        );
      } else {
        debugPrint('⚠️  No poster available — using synthetic cover');
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          stegoPath: finalStegoPath,
        );
      }

      if (!embedOk) throw Exception('embedTicket returned false');
      if (!await File(finalStegoPath).exists()) {
        throw Exception('Stego file missing after embed: $finalStegoPath');
      }
      debugPrint('✅ Stego image created: $finalStegoPath');

      // ── Step 4: Upload stego image to Supabase ─────────────────────────────
      // Uses storageIndex (1-based) so download calls match the same index.
      final stegoUrl = await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: storageIndex,
        stegoFile: File(finalStegoPath),
      );
      if (stegoUrl == null) {
        throw Exception(
            'uploadStegoTicket failed — file not persisted to storage');
      }
      debugPrint(
          '✅ Stego ticket uploaded (storageIndex $storageIndex): $stegoUrl');

      // ── Step 5: Locate + upload blockchain file ────────────────────────────
      // FIX: The FFI typically writes to {appDocDir}/{safeName}.web3chain
      // (NOT the /events/ subfolder).  We now search both locations so the
      // upload never silently falls through.
      final chainFile = await _findChainFile(
        eventsDir: eventsDir,
        appDocDir: appDocDir,
        eventName: eventName,
      );

      if (chainFile == null) {
        // Non-fatal: warn loudly so the path mismatch is obvious in logs.
        debugPrint('⚠️  Blockchain file not found in either:\n'
            '    $eventsDir\n'
            '    $appDocDir\n'
            '    Verify that EventChainFFI writes to one of these paths.');
      } else {
        debugPrint('📂 Found blockchain file: ${chainFile.path}');
        final chainUploaded = await _storage.uploadBlockchainFile(
          eventName: eventName,
          chainFile: chainFile,
        );
        if (!chainUploaded) {
          debugPrint('⚠️  Blockchain upload failed — local copy still intact.');
        } else {
          debugPrint('✅ Blockchain file uploaded: ${chainFile.path}');
        }
      }

      // ── Step 6: Persist ticket record to Supabase DB ──────────────────────
      // FIX: stegoUrl was obtained in Step 4 but was never added to the insert,
      // causing a NOT NULL violation on the stego_url column and silently
      // aborting every ticket insert.
      await _supabase.from('tickets').insert({
        'event_id': eventId,
        'event_name': eventName,
        'block_index': storageIndex, // 1-based, consistent with storage paths
        'ticket_id': ticket.ticketID,
        'owner_name': ticket.ownerName,
        'owner_id': ticket.ownerID,
        'ticket_type': ticket.ticketType,
        'price': ticket.price,
        'event_date': ticket.eventDate,
        'venue': ticket.venue,
        'stego_url': stegoUrl, // FIX: was missing — caused NOT NULL failure
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      refresh();
      state = state.copyWith(loading: false);
      debugPrint('=== TICKET CREATION SUCCESS === $finalStegoPath');
      return (true, finalStegoPath);
    } catch (e, stack) {
      debugPrint('=== TICKET CREATION FAILED ===\nError: $e\n$stack');
      state = state.copyWith(loading: false, error: e.toString());
      return (false, null);
    }
  }

  Future<bool> validateEvent(String eventName) => _ffi.validateEvent(eventName);

  List<BlockModel> getChain(String eventName) {
    final size = _ffi.getEventSize(eventName);
    return [
      for (int i = 0; i < size; i++)
        if (_ffi.getTicket(eventName, i) case final t?)
          BlockModel(index: i, ticket: t),
    ];
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Returns the shared local events directory (used for remote chain
  /// downloads).  The FFI may write blockchain files to the parent
  /// appDocDir instead — see [_findChainFile].
  Future<String> _eventsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/events';
    await Directory(path).create(recursive: true);
    return path;
  }

  /// Locates the `.web3chain` file for [eventName], searching:
  ///   1. `{eventsDir}/{safeName}.web3chain`  (download target)
  ///   2. `{appDocDir}/{safeName}.web3chain`  (FFI native write location)
  ///   3. A case-insensitive scan of both directories for any `.web3chain`
  ///      whose stem matches the safe name.
  ///   4. The sole `.web3chain` in either directory if only one exists.
  Future<File?> _findChainFile({
    required String eventsDir,
    required String appDocDir,
    required String eventName,
  }) async {
    final safeName =
        eventName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    // 1 & 2 — exact match in both candidate directories.
    for (final dir in [eventsDir, appDocDir]) {
      final f = File('$dir/$safeName.web3chain');
      if (await f.exists()) {
        debugPrint('📂 Chain file found (exact): ${f.path}');
        return f;
      }
    }

    // 3 & 4 — directory scan fallback.
    final allCandidates = <File>[];
    for (final dirPath in [eventsDir, appDocDir]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        final found = await dir
            .list()
            .where((e) => e is File && e.path.endsWith('.web3chain'))
            .cast<File>()
            .toList();
        allCandidates.addAll(found);
      } catch (e) {
        debugPrint('⚠️  Error scanning $dirPath for chain file: $e');
      }
    }

    // Case-insensitive stem match across all candidates.
    for (final f in allCandidates) {
      final stem = f.uri.pathSegments.last.replaceAll('.web3chain', '');
      if (stem.toLowerCase() == safeName.toLowerCase()) {
        debugPrint('📂 Chain file found (scan match): ${f.path}');
        return f;
      }
    }

    // Last resort: exactly one .web3chain across both dirs.
    if (allCandidates.length == 1) {
      debugPrint(
          '📂 Chain file found (sole candidate): ${allCandidates.first.path}');
      return allCandidates.first;
    }

    return null;
  }
}

final eventsProvider = NotifierProvider<EventsNotifier, EventsState>(
  EventsNotifier.new,
);
