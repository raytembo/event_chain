// lib/features/events/events_provider.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../../core/models/ticket_record.dart'; // used: TicketTypeX.fromString
import '../../core/services/supabase_service.dart';
import '../../core/services/supabase_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ownerEventsProvider
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
  final List<String> eventNames;
  final bool loading;
  final String? message;
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

  // ── Full sync (all events, not just one) ────────────────────────────────────

  Future<void>? _fullSyncFuture;

  /// Downloads/refreshes every event chain from Supabase to the local
  /// device, not just the ones already known locally.
  ///
  /// Intended to be called when a screen that needs up-to-date chain data
  /// is opened (e.g. the scanner or verifier dashboard) — it runs in the
  /// background and updates [state] as it goes, so widgets watching
  /// [eventsProvider] can show sync progress without blocking navigation.
  ///
  /// If a sync is already in flight, this returns the *same* future
  /// instead of starting a duplicate one — so callers can safely await it
  /// without triggering a second pass over every event.
  Future<void> syncAllEvents({bool force = false}) {
    if (_fullSyncFuture != null && !force) return _fullSyncFuture!;
    final future = _runFullSync();
    _fullSyncFuture = future;
    future.whenComplete(() => _fullSyncFuture = null);
    return future;
  }

  Future<void> _runFullSync() async {
    state = state.copyWith(loading: true, clearMessage: true);

    try {
      final remoteNames = await _fetchAllRemoteEventNames();

      if (remoteNames.isEmpty) {
        refresh();
        return;
      }

      // Download in small concurrent batches so we don't open dozens of
      // simultaneous Storage connections in a single sync pass.
      const batchSize = 4;
      for (var i = 0; i < remoteNames.length; i += batchSize) {
        final batch = remoteNames.skip(i).take(batchSize);
        await Future.wait(batch.map(loadRemoteChain));
      }

      refresh();
    } catch (e, stack) {
      debugPrint('❌ syncAllEvents failed: $e\n$stack');
      state = state.copyWith(
        loading: false,
        message: 'Could not sync the latest events. Check your connection.',
      );
    }
  }

  /// Pages through the `events` table to collect every event name.
  ///
  /// Uses `.range()` instead of `.limit()` so this scales past 50+ events
  /// instead of silently dropping anything beyond the first page (the bug
  /// in the scanner's old inline download logic).
  Future<List<String>> _fetchAllRemoteEventNames() async {
    final names = <String>[];
    const pageSize = 200;
    var from = 0;

    while (true) {
      final rows = await _svc.events
          .select('event_name')
          .range(from, from + pageSize - 1);

      final batch = List<Map<String, dynamic>>.from(rows);
      if (batch.isEmpty) break;

      for (final row in batch) {
        final name = row['event_name'] as String?;
        if (name != null && name.isNotEmpty) names.add(name);
      }

      if (batch.length < pageSize) break; // last page
      from += pageSize;
    }

    return names;
  }

  // ── Ticket prices & capacity ───────────────────────────────────────────────

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
  /// Returns (true, localStegoPath) on full success.
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
      if (!mined) {
        throw Exception(
            'Something went wrong while creating your ticket. Please try again.');
      }

      final blockIndex = _ffi.getEventSize(eventName) - 1;
      final storageIndex = blockIndex + 1; // 1-based for Storage paths

      debugPrint(
          '✅ Block mined — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 3: Embed ticket data into the event poster ──────────────────
      //
      // The C++ steganography layer only accepts lossless cover images
      // (PNG or BMP). Event posters are commonly uploaded as JPEG, so we
      // must convert any non-lossless download to PNG before calling
      // embedTicket — otherwise the C++ layer returns -1 silently.
      final rawCoverPath = await _downloadPosterWithFallback(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempPath,
      );

      // Convert to PNG if the downloaded file is not already lossless.
      final coverLocalPath = (rawCoverPath != null &&
              !rawCoverPath.endsWith('.png') &&
              !rawCoverPath.endsWith('.bmp'))
          ? await _convertImageToPng(rawCoverPath, tempPath)
          : rawCoverPath;

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

      if (!embedOk) {
        throw Exception(
            'Could not generate your ticket image. Please try again.');
      }
      if (!await File(finalStegoPath).exists()) {
        throw Exception('Ticket image was not saved. Please try again.');
      }

      // ── Step 4: Upload stego image to Supabase Storage ───────────────────
      final stegoUrl = await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: storageIndex,
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
      //
      // FIX: Use _svc.insertTicket() instead of a raw .tickets.insert({}).
      //
      // The raw insert was the source of two silent failures:
      //   a) Without .select(), newer Supabase SDK versions return null on
      //      success *and* on certain errors, so PostgrestException was never
      //      thrown and failures were invisible.
      //   b) It bypassed insertTicket()'s typed TicketType parameter, which
      //      meant Postgres enum coercion was not guaranteed and any RLS /
      //      constraint violation swallowed the error silently.
      //
      // blockIndex is 0-based — matches getTicket(eventName, blockIndex).
      final record = await _svc.insertTicket(
        ticketId: ticket.ticketID,
        blockIndex: blockIndex,
        eventId: eventId,
        ownerName: ticket.ownerName,
        ticketType: TicketTypeX.fromString(ticket.ticketType),
        price: ticket.price,
        stegoUrl: stegoUrl,
      );

      if (record == null) {
        // insertTicket() already logged the PostgREST error.
        throw Exception(
            'Could not save your ticket to the database. Please try again.');
      }

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

  // ── Ticket scanning ───────────────────────────────────────────────────────

  /// Returns the existing [scanned_at] timestamp string if the ticket has
  /// already been scanned, or null if it has never been scanned.
  Future<String?> checkTicketScanned(String ticketId) async {
    try {
      final row = await _svc.client
          .from('tickets')
          .select('scanned_at')
          .eq('ticket_id', ticketId)
          .maybeSingle();
      return row?['scanned_at'] as String?;
    } catch (e) {
      debugPrint('❌ checkTicketScanned: $e');
      return null;
    }
  }

  /// Stamps [scanned_at] on the ticket row identified by [ticketId].
  /// Returns true on success, false on any error.
  Future<bool> markTicketScanned(String ticketId) async {
    try {
      await _svc.client
          .from('tickets')
          .update({'scanned_at': DateTime.now().toUtc().toIso8601String()})
          .eq('ticket_id', ticketId)
          .select()
          .single();
      return true;
    } catch (e) {
      debugPrint('❌ markTicketScanned: $e');
      return false;
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

  /// Converts any image at [sourcePath] to a lossless PNG saved in [tempDir].
  ///
  /// The C++ steganography layer hard-rejects JPEG / WebP as cover images
  /// because those formats are lossy. Flutter's dart:ui codec can decode any
  /// format the OS supports and re-encode to raw PNG without an extra package.
  ///
  /// Returns the PNG path on success, or null if conversion fails (in which
  /// case the caller should fall through to the synthetic-cover path).
  Future<String?> _convertImageToPng(String sourcePath, String tempDir) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (byteData == null) {
        debugPrint('⚠️  PNG conversion produced null byte data: $sourcePath');
        return null;
      }
      // Place the converted file alongside the original, same base name.
      final base =
          sourcePath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      final pngPath = '$tempDir/${base}_converted.png';
      await File(pngPath).writeAsBytes(byteData.buffer.asUint8List());
      debugPrint('✅ Converted cover to PNG: $pngPath');
      return pngPath;
    } catch (e) {
      debugPrint('❌ PNG conversion failed ($sourcePath): $e');
      return null;
    }
  }

  /// Downloads the event poster to a temp file.
  ///
  /// Strategy (in order):
  ///   1. Extract the exact storage path from [posterUrl].
  ///      The Supabase public URL already encodes the real bucket path, so this
  ///      always works — even when the poster was uploaded under a different ID
  ///      than [eventId] (e.g. a timestamp used before the UUID was available).
  ///   2. Fall back to reconstructing the path from [eventId] + known extensions
  ///      in case the URL is empty or from a different host.
  Future<String?> _downloadPosterWithFallback({
    required String eventId,
    required String posterUrl,
    required String tempDir,
  }) async {
    final storage = Supabase.instance.client.storage;

    // ── Strategy 1: extract the exact path from the public URL ──────────────
    // URL format: https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path…>
    // Example:    …/public/event-posters/events/1779703034130/poster.jpg
    //                                           ↑ may differ from eventId UUID ↑
    if (posterUrl.isNotEmpty) {
      try {
        final uri = Uri.tryParse(posterUrl);
        if (uri != null) {
          // pathSegments: ['storage','v1','object','public','event-posters','events','<id>','poster.jpg']
          final segments = uri.pathSegments;
          final bucketIndex = segments.indexOf('event-posters');
          if (bucketIndex != -1 && bucketIndex + 1 < segments.length) {
            final storagePath = segments.sublist(bucketIndex + 1).join('/');
            // Derive a local filename from the last path segment.
            final fileName = segments.last; // e.g. poster.jpg
            final ext =
                fileName.contains('.') ? fileName.split('.').last : 'jpg';
            final savePath = '$tempDir/cover_${eventId}_url.$ext';
            final bytes =
                await storage.from('event-posters').download(storagePath);
            await File(savePath).writeAsBytes(bytes);
            debugPrint(
                '✅ Poster downloaded via URL path ($storagePath) → $savePath');
            return savePath;
          }
        }
      } on StorageException catch (e) {
        debugPrint(
            '⚠️  URL-path download failed: ${e.message} — trying eventId fallback');
      } catch (e) {
        debugPrint('⚠️  URL-path download error: $e — trying eventId fallback');
      }
    }

    // ── Strategy 2: reconstruct path from eventId + known extensions ─────────
    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp']) {
      try {
        final remotePath = 'events/$eventId/poster.$ext';
        final bytes = await storage.from('event-posters').download(remotePath);
        final savePath = '$tempDir/cover_$eventId.$ext';
        await File(savePath).writeAsBytes(bytes);
        debugPrint(
            '✅ Poster downloaded via eventId fallback ($ext) → $savePath');
        return savePath;
      } on StorageException catch (e) {
        final body = e.message;
        if (body.contains('not_found') || body.contains('404')) continue;
        debugPrint(
            '❌ StorageException downloading poster ($ext): ${e.message}');
        return null;
      } catch (e) {
        debugPrint('❌ Error downloading poster ($ext): $e');
        return null;
      }
    }

    debugPrint('⚠️  Poster not found in storage for event: $eventId');
    return null;
  }

  Future<File?> _findChainFile({
    required String eventsDir,
    required String appDocDir,
    required String eventName,
  }) async {
    final safeName =
        eventName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    for (final dir in [eventsDir, appDocDir]) {
      final f = File('$dir/$safeName.web3chain');
      if (await f.exists()) return f;
    }

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
