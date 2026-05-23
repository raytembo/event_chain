// lib/features/events/events_provider.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../../core/models/ticket_record.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/supabase_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ownerEventsProvider
//
// Fetches the signed-in owner's events, joined with their ticket-type rows so
// the events list can show sold / remaining counts without a second query.
// ─────────────────────────────────────────────────────────────────────────────
final ownerEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = SupabaseService.instance;
  final userId = svc.currentUserId;
  if (userId == null) return [];

  final res = await svc.events
      .select(
        '*, event_ticket_types(ticket_type, price, quantity_available, quantity_sold)',
      )
      .eq('owner_id', userId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(res);
});

// ─────────────────────────────────────────────────────────────────────────────
// EventsState
// ─────────────────────────────────────────────────────────────────────────────
class EventsState {
  /// Names of blockchain events loaded locally on this device.
  final List<String> eventNames;
  final bool loading;

  /// User-facing message (non-technical). Null when everything is fine.
  final String? message;

  /// Events that are currently syncing with the cloud.
  final Set<String> syncing;

  const EventsState({
    this.eventNames = const [],
    this.loading = false,
    this.message,
    this.syncing = const {},
  });

  EventsState copyWith({
    List<String>? eventNames,
    bool? loading,
    String? message,
    bool clearMessage = false,
    Set<String>? syncing,
  }) =>
      EventsState(
        eventNames: eventNames ?? this.eventNames,
        loading: loading ?? this.loading,
        message: clearMessage ? null : message ?? this.message,
        syncing: syncing ?? this.syncing,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EventsNotifier
// ─────────────────────────────────────────────────────────────────────────────
class EventsNotifier extends Notifier<EventsState> {
  final _ffi = EventChainFFI.instance;
  final _storage = SupabaseStorageService.instance;
  final _svc = SupabaseService.instance;

  @override
  EventsState build() => const EventsState(loading: true);

  // ── Local chain list ───────────────────────────────────────────────────────

  /// Refreshes the list of locally-known event names from the FFI layer.
  void refresh() {
    try {
      state = state.copyWith(
        eventNames: _ffi.listEvents(),
        loading: false,
        clearMessage: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        message: 'Could not load your events. Please try again.',
      );
    }
  }

  // ── Remote chain sync ──────────────────────────────────────────────────────

  /// Downloads the blockchain file for [eventName] from the cloud and loads
  /// it into the local FFI instance.
  Future<bool> loadRemoteChain(String eventName) async {
    state = state.copyWith(syncing: {...state.syncing, eventName});
    try {
      final eventsDir = await _localEventsDir();
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
        message: 'Could not download event data. Check your connection.',
      );
      return false;
    }
  }

  // ── Ticket prices & capacity ───────────────────────────────────────────────

  /// Returns { 'General': 5000.0, 'VIP': 15000.0, … } for [eventId].
  Future<Map<String, double>> getTicketPrices(String eventId) async {
    try {
      final res = await _svc.eventTicketTypes
          .select('ticket_type, price, quantity_available, quantity_sold')
          .eq('event_id', eventId);
      return {
        for (final row in List<Map<String, dynamic>>.from(res))
          row['ticket_type'] as String: (row['price'] as num).toDouble(),
      };
    } catch (e) {
      debugPrint('❌ getTicketPrices: $e');
      return {};
    }
  }

  /// Returns true if at least one slot remains for [ticketType] in [eventId].
  /// Queries the DB directly so the check is always live.
  Future<bool> _hasCapacity({
    required String eventId,
    required String ticketType,
  }) async {
    try {
      final res = await _svc.eventTicketTypes
          .select('quantity_available, quantity_sold')
          .eq('event_id', eventId)
          .eq('ticket_type', ticketType)
          .single();
      final available = (res['quantity_available'] as num).toInt();
      final sold = (res['quantity_sold'] as num).toInt();
      return (available - sold) > 0;
    } catch (e) {
      debugPrint('❌ _hasCapacity: $e');
      return false;
    }
  }

  // ── Add ticket ─────────────────────────────────────────────────────────────

  /// Full ticket-creation pipeline:
  ///   1. Capacity check
  ///   2. Mine a new block in the local C++ blockchain
  ///   3. Embed ticket data steganographically into the event poster
  ///   4. Upload the stego image to Supabase Storage
  ///   5. Upload the updated blockchain file to Supabase Storage
  ///   6. Insert the ticket row into the Supabase database
  ///
  /// [blockIndex] in the DB uses the raw 0-based C++ chain index.
  /// [storageIndex] (blockIndex + 1) is used only for Storage file paths.
  ///
  /// Returns (true, localStegoPath) on full success.
  Future<(bool success, String? stegoLocalPath)> addTicket({
    required String eventName,
    required String eventId,
    required String posterUrl,
    required String ownerName,
    required String ownerID, // FFI / stego payload only
    required String eventDate, // FFI / stego payload only
    required String venue, // FFI / stego payload only
    required String ticketType,
    required double price,
  }) async {
    state = state.copyWith(loading: true, clearMessage: true);

    try {
      // ── Guard: auth session ──────────────────────────────────────────────
      final authUser = _svc.auth.currentUser;
      if (authUser == null) throw Exception('You are not signed in.');

      // ── Guard: ticket availability ───────────────────────────────────────
      final hasSlot = await _hasCapacity(
        eventId: eventId,
        ticketType: ticketType,
      );
      if (!hasSlot) {
        throw Exception(
          'Sorry, there are no $ticketType tickets left for this event.',
        );
      }

      // ── Directories ──────────────────────────────────────────────────────
      final appDocDir = (await getApplicationDocumentsDirectory()).path;
      final eventsDir = '$appDocDir/events';
      await Directory(eventsDir).create(recursive: true);
      final tempPath = (await getTemporaryDirectory()).path;

      // ── Step 1: Build the FFI ticket model ───────────────────────────────
      final ticket = TicketModel(
        ticketID: 'TKT-${DateTime.now().millisecondsSinceEpoch}',
        eventName: eventName,
        eventDate: eventDate,
        venue: venue,
        ownerName: ownerName,
        ownerID: ownerID,
        ticketType: ticketType,
        price: price,
      );

      // ── Step 2: Mine the block locally ───────────────────────────────────
      final mined = await _ffi.addTicket(eventName, ticket);
      if (!mined)
        throw Exception(
            'Something went wrong while creating your ticket. Please try again.');

      // blockIndex is 0-based (matches C++ chain and DB block_index column).
      // storageIndex is 1-based — used only for Storage file names.
      final blockIndex = _ffi.getEventSize(eventName) - 1;
      final storageIndex = blockIndex + 1; // ticket_1.png, ticket_2.png, …

      debugPrint(
          '✅ Block mined — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 3: Embed ticket data into the event poster ──────────────────
      final coverLocalPath = await _storage.downloadEventPosterToTemp(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempPath,
      );

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

      if (!embedOk)
        throw Exception(
            'Could not generate your ticket image. Please try again.');
      if (!await File(finalStegoPath).exists()) {
        throw Exception('Ticket image was not saved. Please try again.');
      }

      // ── Step 4: Upload stego image to Supabase Storage ───────────────────
      final stegoUrl = await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: storageIndex, // 1-based for storage paths
        stegoFile: File(finalStegoPath),
      );
      if (stegoUrl == null) {
        throw Exception(
            'Could not upload your ticket image. Please check your connection.');
      }

      // ── Step 5: Upload updated blockchain file to cloud ──────────────────
      final chainFile = await _findChainFile(
        eventsDir: eventsDir,
        appDocDir: appDocDir,
        eventName: eventName,
      );
      if (chainFile == null) {
        // Non-fatal — ticket is still created; blockchain backup will retry.
        debugPrint('⚠️  Blockchain file not found — local copy still intact.');
        state = state.copyWith(
          message:
              'Your ticket was created. The cloud backup will sync next time you open the event.',
        );
      } else {
        final chainUploaded = await _storage.uploadBlockchainFile(
          eventName: eventName,
          chainFile: chainFile,
        );
        if (!chainUploaded) {
          debugPrint('⚠️  Blockchain upload failed — local copy intact.');
          state = state.copyWith(
            message:
                'Your ticket was created. Cloud backup will retry on next launch.',
          );
        }
      }

      // ── Step 6: Insert ticket row into the database ──────────────────────
      // block_index stores the 0-based C++ chain index so it lines up with
      // FFI lookups. storageIndex is only for Storage file-name resolution.
      await _svc.tickets.insert({
        'event_id': eventId,
        'ticket_id': ticket.ticketID,
        'block_index':
            blockIndex, // 0-based — matches getTicket(eventName, blockIndex)
        'owner_id': authUser.id,
        'owner_name': ticket.ownerName,
        'ticket_type': ticket.ticketType,
        'price': ticket.price,
        'stego_url': stegoUrl,
        'is_sold': false,
      });

      refresh();
      state = state.copyWith(loading: false);
      return (true, finalStegoPath);
    } on PostgrestException catch (e) {
      debugPrint('❌ DB error: ${e.message}');
      state = state.copyWith(
        loading: false,
        message: 'Could not save your ticket. Please try again.',
      );
      return (false, null);
    } catch (e, stack) {
      debugPrint('❌ addTicket failed: $e\n$stack');
      state = state.copyWith(loading: false, message: e.toString());
      return (false, null);
    }
  }

  // ── Chain queries ──────────────────────────────────────────────────────────

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

  Future<String> _localEventsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/events';
    await Directory(path).create(recursive: true);
    return path;
  }

  /// Locates the `.web3chain` file for [eventName], trying multiple strategies
  /// because the C++ layer and the Dart download target may use different paths.
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
      if (await f.exists()) return f;
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
        debugPrint('⚠️  Error scanning $dirPath: $e');
      }
    }

    for (final f in allCandidates) {
      final stem = f.uri.pathSegments.last.replaceAll('.web3chain', '');
      if (stem.toLowerCase() == safeName.toLowerCase()) return f;
    }

    if (allCandidates.length == 1) return allCandidates.first;
    return null;
  }
}

final eventsProvider = NotifierProvider<EventsNotifier, EventsState>(
  EventsNotifier.new,
);
