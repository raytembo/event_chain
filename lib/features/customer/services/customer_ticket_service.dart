// lib/features/customer/services/customer_ticket_service.dart
//
// Full customer ticket-purchase pipeline:
//   1. Sync the event's blockchain from Supabase Storage
//   2. Build a TicketModel for the buyer
//   3. Mine a new block in the local C++ blockchain
//   4. Embed ticket data steganographically (using event poster or synthetic cover)
//   5. Upload the stego image to Supabase Storage
//   6. Upload the updated blockchain file to Supabase Storage
//   7. Insert the ticket row into the DB
//   8. Insert a completed payment row into the DB

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ffi_bridge/eventchain_ffi.dart';
import '../../../core/models/ticket_model.dart';
import '../../../core/models/ticket_record.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/supabase_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────────────────────────────────────
class PurchaseResult {
  final bool success;
  final String? stegoLocalPath;
  final String? stegoUrl;
  final String? ticketId;
  final String? error;

  const PurchaseResult._({
    required this.success,
    this.stegoLocalPath,
    this.stegoUrl,
    this.ticketId,
    this.error,
  });

  factory PurchaseResult.success({
    required String stegoLocalPath,
    required String stegoUrl,
    required String ticketId,
  }) =>
      PurchaseResult._(
        success: true,
        stegoLocalPath: stegoLocalPath,
        stegoUrl: stegoUrl,
        ticketId: ticketId,
      );

  factory PurchaseResult.failure(String error) =>
      PurchaseResult._(success: false, error: error);
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────
class CustomerTicketService {
  static final CustomerTicketService instance = CustomerTicketService._();
  CustomerTicketService._();

  final _ffi = EventChainFFI.instance;
  final _svc = SupabaseService.instance;
  final _storage = SupabaseStorageService.instance;

  // ── Public entry point ─────────────────────────────────────────────────────

  Future<PurchaseResult> purchaseTicket({
    required String eventId,
    required String eventName,
    required String posterUrl,
    required String eventDate,
    required String venue,
    required String ticketType,
    required double price,
  }) async {
    try {
      // ── Auth guard ───────────────────────────────────────────────────────
      final authUser = _svc.auth.currentUser;
      if (authUser == null) throw Exception('You are not signed in.');

      // ── Resolve buyer display name ────────────────────────────────────────
      final profile = await _svc.client
          .from('profiles')
          .select('display_name')
          .eq('id', authUser.id)
          .maybeSingle();
      final buyerName =
          (profile?['display_name'] as String?)?.trim().isNotEmpty == true
              ? profile!['display_name'] as String
              : authUser.email?.split('@').first ?? 'customer';

      // ── Directory setup ───────────────────────────────────────────────────
      final appDocDir = (await getApplicationDocumentsDirectory()).path;
      final eventsDir = '$appDocDir/events';
      await Directory(eventsDir).create(recursive: true);
      final tempPath = (await getTemporaryDirectory()).path;

      // ── Step 1: Sync the event's blockchain file from Supabase Storage ────
      //
      // The blockchain file is owned by the event organiser but shared via
      // Supabase Storage so customers can append new blocks to it.
      await _syncBlockchain(eventName: eventName, eventsDir: eventsDir);

      // ── Step 2: Build the TicketModel ─────────────────────────────────────
      final ticket = TicketModel(
        ticketID: 'TKT-${DateTime.now().millisecondsSinceEpoch}',
        eventName: eventName,
        eventDate: eventDate,
        venue: venue,
        ownerName: buyerName,
        ownerID: authUser.id,
        ticketType: ticketType,
        price: price,
      );

      // ── Step 3: Mine a new block locally ──────────────────────────────────
      final mined = await _ffi.addTicket(eventName, ticket);
      if (!mined) {
        throw Exception('Failed to create your ticket. Please try again.');
      }

      final blockIndex = _ffi.getEventSize(eventName) - 1;
      final storageIndex = blockIndex + 1; // 1-based for storage paths

      debugPrint(
          '✅ Block mined — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 4: Embed ticket data steganographically ──────────────────────
      //
      // The C++ stego layer only accepts lossless cover images (PNG/BMP).
      // Download the event poster and convert it before embedding.
      final rawCoverPath = await _downloadPosterWithFallback(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempPath,
      );

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
        throw Exception(
            'Ticket image was not saved correctly. Please try again.');
      }

      // ── Step 5: Upload stego image to Supabase Storage ────────────────────
      final stegoUrl = await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: storageIndex,
        stegoFile: File(finalStegoPath),
      );
      if (stegoUrl == null) {
        throw Exception(
            'Could not upload your ticket image. Check your connection.');
      }

      // ── Step 6: Upload updated blockchain file ────────────────────────────
      await _uploadBlockchain(
        eventsDir: eventsDir,
        appDocDir: appDocDir,
        eventName: eventName,
      );

      // ── Step 7: Insert ticket row ─────────────────────────────────────────
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
        throw Exception('Could not save ticket to database. Please try again.');
      }

      // ── Step 8: Insert payment row ────────────────────────────────────────
      // FIXED: Accessing property directly via dot notation instead of Map brackets
      final ticketDbId = record.id;

      await _svc.client.from('payments').insert({
        'ticket_id': ticketDbId,
        'event_id': eventId,
        'buyer_id': authUser.id,
        'amount': price,
        'currency': 'MWK', // fix currency too
        'status': 'completed',
        'processed_at': DateTime.now().toIso8601String(), // ← add this
        'buyer_name': buyerName,
        'buyer_email': authUser.email ?? '',
      });

      debugPrint('✅ Purchase complete — ticketId: ${ticket.ticketID}');
      return PurchaseResult.success(
        stegoLocalPath: finalStegoPath,
        stegoUrl: stegoUrl,
        ticketId: ticket.ticketID,
      );
    } on PostgrestException catch (e) {
      debugPrint('❌ DB error: ${e.message}');
      return PurchaseResult.failure('Database error: ${e.message}');
    } catch (e, stack) {
      debugPrint('❌ purchaseTicket failed: $e\n$stack');
      return PurchaseResult.failure(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _syncBlockchain({
    required String eventName,
    required String eventsDir,
  }) async {
    try {
      final ok = await _storage.downloadBlockchainFile(
        eventName: eventName,
        localEventsDir: eventsDir,
      );
      if (ok) {
        _ffi.loadEvent(eventName);
        debugPrint('✅ Blockchain synced for: $eventName');
      } else {
        // No existing chain — the first purchase will create one.
        debugPrint(
            'ℹ️  No existing blockchain for "$eventName" — starting fresh');
      }
    } catch (e) {
      debugPrint('⚠️  Blockchain sync error (proceeding): $e');
    }
  }

  Future<void> _uploadBlockchain({
    required String eventsDir,
    required String appDocDir,
    required String eventName,
  }) async {
    // Flush the in-memory chain to disk first.
    _ffi.saveEvent(eventName);

    final safeName =
        eventName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    for (final dirPath in [eventsDir, appDocDir]) {
      final file = File('$dirPath/$safeName.web3chain');
      if (await file.exists()) {
        final uploaded = await _storage.uploadBlockchainFile(
          eventName: eventName,
          chainFile: file,
        );
        if (!uploaded) {
          debugPrint('⚠️  Blockchain upload failed — local copy intact');
        }
        return;
      }
    }
    debugPrint('⚠️  Blockchain file not found after save');
  }

  Future<String?> _downloadPosterWithFallback({
    required String eventId,
    required String posterUrl,
    required String tempDir,
  }) async {
    final storage = Supabase.instance.client.storage;

    // Strategy 1: extract exact storage path from the public URL
    if (posterUrl.isNotEmpty) {
      try {
        final uri = Uri.tryParse(posterUrl);
        if (uri != null) {
          final segments = uri.pathSegments;
          final bucketIndex = segments.indexOf('event-posters');
          if (bucketIndex != -1 && bucketIndex + 1 < segments.length) {
            final storagePath = segments.sublist(bucketIndex + 1).join('/');
            final fileName = segments.last;
            final ext =
                fileName.contains('.') ? fileName.split('.').last : 'jpg';
            final savePath = '$tempDir/cover_${eventId}_url.$ext';
            final bytes =
                await storage.from('event-posters').download(storagePath);
            await File(savePath).writeAsBytes(bytes);
            debugPrint('✅ Poster downloaded via URL path → $savePath');
            return savePath;
          }
        }
      } on StorageException catch (e) {
        debugPrint('⚠️  URL-path download failed: ${e.message}');
      } catch (e) {
        debugPrint('⚠️  Poster download error: $e');
      }
    }

    // Strategy 2: reconstruct path from eventId + common extensions
    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp']) {
      try {
        final remotePath = 'events/$eventId/poster.$ext';
        final bytes = await storage.from('event-posters').download(remotePath);
        final savePath = '$tempDir/cover_$eventId.$ext';
        await File(savePath).writeAsBytes(bytes);
        debugPrint('✅ Poster downloaded via eventId fallback ($ext)');
        return savePath;
      } on StorageException catch (e) {
        final body = e.message;
        if (body.contains('not_found') || body.contains('404')) continue;
        debugPrint('❌ StorageException ($ext): ${e.message}');
        return null;
      } catch (_) {}
    }

    debugPrint('⚠️  No poster found — will use synthetic cover');
    return null;
  }

  Future<String?> _convertImageToPng(String sourcePath, String tempDir) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (byteData == null) return null;
      final base =
          sourcePath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      final pngPath = '$tempDir/${base}_converted.png';
      await File(pngPath).writeAsBytes(byteData.buffer.asUint8List());
      debugPrint('✅ Converted cover to PNG: $pngPath');
      return pngPath;
    } catch (e) {
      debugPrint('❌ PNG conversion failed: $e');
      return null;
    }
  }
}
