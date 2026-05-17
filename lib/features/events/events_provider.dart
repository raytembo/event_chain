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
  final bool         loading;
  final String?      error;
  final Set<String>  syncing;

  const EventsState({
    this.eventNames = const [],
    this.loading    = false,
    this.error,
    this.syncing    = const {},
  });

  EventsState copyWith({
    List<String>? eventNames,
    bool?         loading,
    String?       error,
    bool          clearError = false,
    Set<String>?  syncing,
  }) =>
      EventsState(
        eventNames: eventNames ?? this.eventNames,
        loading:    loading    ?? this.loading,
        error:      clearError ? null : error ?? this.error,
        syncing:    syncing    ?? this.syncing,
      );
}

// ── Notifier ─────────────────────────────────────────────────────────────────
class EventsNotifier extends Notifier<EventsState> {
  final _ffi     = EventChainFFI.instance;
  final _storage = SupabaseStorageService.instance;
  final _supabase = Supabase.instance.client;

  @override
  EventsState build() => const EventsState(loading: true);

  void refresh() {
    try {
      state = state.copyWith(
        eventNames: _ffi.listEvents(),
        loading:    false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> loadRemoteChain(String eventName) async {
    state = state.copyWith(syncing: {...state.syncing, eventName});
    try {
      final dir = await getApplicationDocumentsDirectory();
      final eventsDir = '${dir.path}/events';
      await Directory(eventsDir).create(recursive: true);

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

  /// Returns the pre-configured price for each ticket type of an event.
  Future<Map<String, double>> getTicketPrices(String eventId) async {
    try {
      final res = await _supabase
          .from('event_ticket_types')
          .select('ticket_type, price')
          .eq('event_id', eventId);

      final map = <String, double>{};
      for (final row in List<Map<String, dynamic>>.from(res)) {
        final type = row['ticket_type'] as String;
        final price = (row['price'] as num).toDouble();
        map[type] = price;
      }
      return map;
    } catch (e) {
      debugPrint('Failed to load ticket prices: $e');
      return {};
    }
  }

  /// Create a ticket with steganography.
  /// C++ outputs PNG directly via stb_image_write — no Dart conversion needed.
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
    String? finalStegoPath;

    try {
      debugPrint('=== TICKET CREATION START ===');
      debugPrint('Event: $eventName | ID: $eventId | Type: $ticketType | Price: MWK $price');

      final dir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      final eventsDir = '${dir.path}/events';
      await Directory(eventsDir).create(recursive: true);

      // ── Step 1: Build ticket model ────────────────────────────────────────
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

      // ── Step 2: Mine block in C++ ─────────────────────────────────────────
      final mined = await _ffi.addTicket(eventName, ticket);
      if (!mined) {
        throw Exception('Mining failed in native layer');
      }

      final blockIndex = _ffi.getEventSize(eventName) - 1;

      // ── Step 3: Download poster + embed steganography ─────────────────────
      final coverLocalPath = await _storage.downloadEventPosterToTemp(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempDir.path,
      );

      // C++ writes PNG directly via stb_image_write (no libpng dependency).
      finalStegoPath = '${tempDir.path}/stego_${ticket.ticketID}.png';

      bool embedOk = false;

      if (coverLocalPath != null && await File(coverLocalPath).exists()) {
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          coverPath: coverLocalPath,
          stegoPath: finalStegoPath,
        );
      } else {
        // No poster available — let C++ generate a synthetic PNG cover.
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          stegoPath: finalStegoPath,
        );
      }

      if (!embedOk || !await File(finalStegoPath).exists()) {
        throw Exception('Failed to create stego ticket image');
      }

      // ── Step 4: Upload stego PNG to Supabase ──────────────────────────────
      final stegoFile = File(finalStegoPath);
      await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: blockIndex,
        stegoFile: stegoFile,
      );

      // ── Step 5: Upload blockchain file ────────────────────────────────────
      final safeName = eventName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final chainFile = File('$eventsDir/$safeName.web3chain');
      if (await chainFile.exists()) {
        await _storage.uploadBlockchainFile(
          eventName: eventName,
          chainFile: chainFile,
        );
      }

      // ── Step 6: Save ticket record to Supabase ────────────────────────────
      final insertData = {
        'event_id': eventId,
        'event_name': eventName,
        'block_index': blockIndex,
        'ticket_id': ticket.ticketID,
        'owner_name': ticket.ownerName,
        'owner_id': ticket.ownerID,
        'ticket_type': ticket.ticketType,
        'price': ticket.price,
        'event_date': ticket.eventDate,
        'venue': ticket.venue,
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('tickets').insert(insertData);

      refresh();
      state = state.copyWith(loading: false);
      debugPrint('=== TICKET CREATION SUCCESS === Stego path: $finalStegoPath');
      return (true, finalStegoPath);

    } catch (e, stack) {
      debugPrint('=== TICKET CREATION FAILED ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      state = state.copyWith(loading: false, error: e.toString());
      return (false, null);
    }
  }

  Future<bool> validateEvent(String eventName) =>
      _ffi.validateEvent(eventName);

  List<BlockModel> getChain(String eventName) {
    final size = _ffi.getEventSize(eventName);
    final blocks = <BlockModel>[];
    for (int i = 0; i < size; i++) {
      final t = _ffi.getTicket(eventName, i);
      if (t != null) blocks.add(BlockModel(index: i, ticket: t));
    }
    return blocks;
  }
}

final eventsProvider = NotifierProvider<EventsNotifier, EventsState>(
  EventsNotifier.new,
);