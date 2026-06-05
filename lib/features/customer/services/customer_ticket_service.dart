// lib/features/customer/services/customer_ticket_service.dart

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
    required String ticketTypeId, // Added: ID required to decrement stock
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
      final storageIndex = blockIndex + 1;

      debugPrint(
          '✅ Block mined — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 4: Embed ticket data steganographically ──────────────────────
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
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          stegoPath: finalStegoPath,
        );
      }

      if (!embedOk || !await File(finalStegoPath).exists()) {
        throw Exception(
            'Could not generate your ticket image. Please try again.');
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
      final ticketDbId = record.id;

      await _svc.client.from('payments').insert({
        'ticket_id': ticketDbId,
        'event_id': eventId,
        'buyer_id': authUser.id,
        'amount': price,
        'currency': 'MWK',
        'status': 'completed',
        'processed_at': DateTime.now().toIso8601String(),
        'buyer_name': buyerName,
        'buyer_email': authUser.email ?? '',
      });

      // ── Step 9: Update Ticket Type Capacity ───────────────────────────────
      final currentType = await _svc.client
          .from('event_ticket_types')
          .select('quantity_available, quantity_sold')
          .eq('id', ticketTypeId)
          .maybeSingle();

      if (currentType != null) {
        final avail = (currentType['quantity_available'] as num?)?.toInt() ?? 1;
        final sold = (currentType['quantity_sold'] as num?)?.toInt() ?? 0;

        await _svc.client.from('event_ticket_types').update({
          'quantity_available': (avail - 1).clamp(0, avail), // Safely decrement
          'quantity_sold': sold + 1, // Log as sold
        }).eq('id', ticketTypeId);
      }

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
          e.toString().replaceFirst('Exception: ', ''));
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
      }
    } catch (e) {
      debugPrint('⚠️  Blockchain sync error: $e');
    }
  }

  Future<void> _uploadBlockchain({
    required String eventsDir,
    required String appDocDir,
    required String eventName,
  }) async {
    _ffi.saveEvent(eventName);
    final safeName =
        eventName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    for (final dirPath in [eventsDir, appDocDir]) {
      final file = File('$dirPath/$safeName.web3chain');
      if (await file.exists()) {
        await _storage.uploadBlockchainFile(
            eventName: eventName, chainFile: file);
        return;
      }
    }
  }

  Future<String?> _downloadPosterWithFallback({
    required String eventId,
    required String posterUrl,
    required String tempDir,
  }) async {
    final storage = Supabase.instance.client.storage;

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
            return savePath;
          }
        }
      } catch (_) {}
    }

    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp']) {
      try {
        final remotePath = 'events/$eventId/poster.$ext';
        final bytes = await storage.from('event-posters').download(remotePath);
        final savePath = '$tempDir/cover_$eventId.$ext';
        await File(savePath).writeAsBytes(bytes);
        return savePath;
      } on StorageException catch (e) {
        if (!e.message.contains('not_found') && !e.message.contains('404')) {
          debugPrint('❌ StorageException ($ext): ${e.message}');
        }
      } catch (_) {}
    }
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
      return pngPath;
    } catch (e) {
      return null;
    }
  }
}
