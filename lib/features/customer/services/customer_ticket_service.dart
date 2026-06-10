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
    required String ticketTypeId,
    required double price,
    required String buyerId,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
    required String nationalId,
    required String paymentMethod,
  }) async {
    // ── Entry — log all inputs so mismatches are immediately visible ─────────
    debugPrint('▶ purchaseTicket() START');
    debugPrint('  paymentMethod : "$paymentMethod"');
    debugPrint('  ticketType    : "$ticketType"');
    debugPrint('  ticketTypeId  : "$ticketTypeId"');
    debugPrint('  eventId       : "$eventId"');
    debugPrint('  buyerId       : "$buyerId"');
    debugPrint('  buyerName     : "$buyerName"');
    debugPrint('  buyerEmail    : "$buyerEmail"');
    // Only log phone prefix — never log the full number
    final phonePreview = buyerPhone.length >= 3
        ? '${buyerPhone.substring(0, 3)}XXXXXXX (len=${buyerPhone.length})'
        : '(empty)';
    debugPrint('  buyerPhone    : $phonePreview');
    debugPrint('  price         : $price');

    try {
      // ── Auth guard ───────────────────────────────────────────────────────
      final authUser = _svc.auth.currentUser;
      if (authUser == null) throw Exception('You are not signed in.');
      debugPrint('  authUser.id   : "${authUser.id}"');

      // ── Directory setup ───────────────────────────────────────────────────
      final appDocDir = (await getApplicationDocumentsDirectory()).path;
      final eventsDir = '$appDocDir/events';
      await Directory(eventsDir).create(recursive: true);
      final tempPath = (await getTemporaryDirectory()).path;

      // ── Step 1: Sync blockchain ───────────────────────────────────────────
      debugPrint('▶ Step 1: syncing blockchain for "$eventName"');
      await _syncBlockchain(eventName: eventName, eventsDir: eventsDir);
      debugPrint('✅ Step 1 done');

      // ── Step 2: Build TicketModel ─────────────────────────────────────────
      debugPrint('▶ Step 2: building TicketModel');
      final finalBuyerName = buyerName.trim().isNotEmpty
          ? buyerName.trim()
          : (authUser.email?.split('@').first ?? 'customer');

      final ticket = TicketModel(
        ticketID: 'TKT-${DateTime.now().millisecondsSinceEpoch}',
        eventName: eventName,
        eventDate: eventDate,
        venue: venue,
        ownerName: finalBuyerName,
        ownerID: buyerId,
        ticketType: ticketType,
        price: price,
      );
      debugPrint('✅ Step 2 done — ticketID: "${ticket.ticketID}"');

      // ── Step 3: Mine block ────────────────────────────────────────────────
      debugPrint('▶ Step 3: mining block via FFI');
      final mined = await _ffi.addTicket(eventName, ticket);
      if (!mined) {
        debugPrint('❌ Step 3 FAILED — FFI.addTicket returned false');
        throw Exception('Failed to create your ticket. Please try again.');
      }

      final blockIndex = _ffi.getEventSize(eventName) - 1;
      final storageIndex = blockIndex + 1;
      debugPrint(
          '✅ Step 3 done — blockIndex: $blockIndex  storageIndex: $storageIndex');

      // ── Step 4: Steganographic embed ──────────────────────────────────────
      debugPrint('▶ Step 4: steganographic embed (posterUrl: '
          '"${posterUrl.isNotEmpty ? posterUrl.substring(0, posterUrl.length.clamp(0, 60)) : 'empty'}")');

      final rawCoverPath = await _downloadPosterWithFallback(
        eventId: eventId,
        posterUrl: posterUrl,
        tempDir: tempPath,
      );
      debugPrint(
          '  rawCoverPath  : ${rawCoverPath ?? 'null — no poster found'}');

      final coverLocalPath = (rawCoverPath != null &&
              !rawCoverPath.endsWith('.png') &&
              !rawCoverPath.endsWith('.bmp'))
          ? await _convertImageToPng(rawCoverPath, tempPath)
          : rawCoverPath;
      debugPrint(
          '  coverLocalPath: ${coverLocalPath ?? 'null — PNG conversion failed'}');

      final finalStegoPath = '$tempPath/stego_${ticket.ticketID}.png';
      bool embedOk;

      if (coverLocalPath != null && await File(coverLocalPath).exists()) {
        debugPrint('  using cover image for embed');
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          coverPath: coverLocalPath,
          stegoPath: finalStegoPath,
        );
      } else {
        debugPrint('  no cover image — embedding without poster');
        embedOk = await _ffi.embedTicket(
          eventName: eventName,
          blockIndex: blockIndex,
          stegoPath: finalStegoPath,
        );
      }

      final stegoFileExists = await File(finalStegoPath).exists();
      debugPrint('  embedOk=$embedOk  stegoFileExists=$stegoFileExists'
          '  stegoPath="$finalStegoPath"');

      if (!embedOk || !stegoFileExists) {
        debugPrint(
            '❌ Step 4 FAILED — embedOk=$embedOk, fileExists=$stegoFileExists');
        throw Exception(
            'Could not generate your ticket image. Please try again.');
      }
      debugPrint('✅ Step 4 done');

      // ── Step 5: Upload stego image ────────────────────────────────────────
      debugPrint('▶ Step 5: uploading stego image to Storage');
      final stegoUrl = await _storage.uploadStegoTicket(
        eventId: eventId,
        blockIndex: storageIndex,
        stegoFile: File(finalStegoPath),
      );
      if (stegoUrl == null) {
        debugPrint('❌ Step 5 FAILED — uploadStegoTicket returned null');
        throw Exception(
            'Could not upload your ticket image. Check your connection.');
      }
      debugPrint('✅ Step 5 done — stegoUrl: "$stegoUrl"');

      // ── Step 6: Upload blockchain ─────────────────────────────────────────
      debugPrint('▶ Step 6: uploading blockchain file');
      await _uploadBlockchain(
        eventsDir: eventsDir,
        appDocDir: appDocDir,
        eventName: eventName,
      );
      debugPrint('✅ Step 6 done');

      // ── Step 7: Insert tickets row ────────────────────────────────────────
      // NOTE: insertTicket does not receive buyerId/buyerEmail/buyerPhone
      // so sold_to, buyer_email, buyer_phone on the ticket row will be NULL
      // unless SupabaseService.insertTicket sets them internally.
      debugPrint('▶ Step 7: inserting ticket row');
      debugPrint('  insertTicket args — ticketId="${ticket.ticketID}"'
          '  blockIndex=$blockIndex  eventId="$eventId"'
          '  ownerName="${ticket.ownerName}"'
          '  ticketType="${ticket.ticketType}"  price=${ticket.price}');
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
        debugPrint('❌ Step 7 FAILED — insertTicket returned null');
        throw Exception('Could not save ticket to database. Please try again.');
      }
      debugPrint('✅ Step 7 done — DB record.id="${record.id}"');

      // ── Step 8: Insert payments row ───────────────────────────────────────
      final ticketDbId = record.id;

      // Map UI display strings → DB enum values.
      // If this throws a PostgrestException with "invalid input value for enum
      // payment_method", the enum in the DB does not contain this exact string.
      // Run:  SELECT enum_range(NULL::payment_method);  to see the actual values.
      String dbPaymentMethod;
      switch (paymentMethod) {
        case 'TNM Mpamba':
          dbPaymentMethod = 'TNM Mpamba';
          break;
        case 'Airtel Money':
          dbPaymentMethod = 'Airtel Money';
          break;
        case 'Card':
        default:
          dbPaymentMethod = 'Card';
          break;
      }

      debugPrint('▶ Step 8: inserting payment row');
      debugPrint('  paymentMethod (raw)   : "$paymentMethod"');
      debugPrint('  dbPaymentMethod (enum): "$dbPaymentMethod"');
      debugPrint('  ticketDbId            : "$ticketDbId"');
      debugPrint('  buyer_email           : "${buyerEmail.trim()}"');
      debugPrint('  buyer_phone prefix    : $phonePreview');

      await _svc.client.from('payments').insert({
        'ticket_id': ticketDbId,
        'event_id': eventId,
        'buyer_id': buyerId,
        'amount': price,
        'currency': 'MWK',
        'status': 'completed',
        'processed_at': DateTime.now().toIso8601String(),
        'buyer_name': finalBuyerName,
        'buyer_email': buyerEmail.trim(),
        'buyer_phone': buyerPhone.trim(),
        'payment_method': dbPaymentMethod,
      });
      debugPrint('✅ Step 8 done');

      // ── Step 9: Decrement ticket-type capacity ────────────────────────────
      debugPrint('▶ Step 9: updating event_ticket_types capacity'
          '  (ticketTypeId="$ticketTypeId")');
      final currentType = await _svc.client
          .from('event_ticket_types')
          .select('quantity_available, quantity_sold')
          .eq('id', ticketTypeId)
          .maybeSingle();

      if (currentType == null) {
        // Row not found — log and skip rather than crash, ticket is already
        // committed at this point.
        debugPrint('⚠️  Step 9: event_ticket_types row not found for'
            ' id="$ticketTypeId" — capacity NOT decremented');
      } else {
        final avail = (currentType['quantity_available'] as num?)?.toInt() ?? 1;
        final sold = (currentType['quantity_sold'] as num?)?.toInt() ?? 0;
        final newAvail = (avail - 1).clamp(0, avail);
        final newSold = sold + 1;

        debugPrint('  before: quantity_available=$avail  quantity_sold=$sold');
        debugPrint(
            '  after : quantity_available=$newAvail  quantity_sold=$newSold');

        await _svc.client.from('event_ticket_types').update({
          'quantity_available': newAvail,
          'quantity_sold': newSold,
        }).eq('id', ticketTypeId);

        debugPrint('✅ Step 9 done — capacity decremented');
      }

      debugPrint('✅ purchaseTicket() COMPLETE — ticketId: "${ticket.ticketID}"'
          '  paymentMethod: "$paymentMethod"');
      return PurchaseResult.success(
        stegoLocalPath: finalStegoPath,
        stegoUrl: stegoUrl,
        ticketId: ticket.ticketID,
      );
    } on PostgrestException catch (e, stack) {
      // A PostgrestException means a DB / RLS / enum constraint fired.
      // The `details` and `hint` fields often carry the exact Postgres error.
      debugPrint('❌ purchaseTicket FAILED — PostgrestException');
      debugPrint('  message : "${e.message}"');
      debugPrint('  details : "${e.details}"');
      debugPrint('  hint    : "${e.hint}"');
      debugPrint('  code    : "${e.code}"');
      debugPrint('  stack   :\n$stack');
      return PurchaseResult.failure('Database error: ${e.message}');
    } catch (e, stack) {
      debugPrint('❌ purchaseTicket FAILED — ${e.runtimeType}: $e');
      debugPrint('  stack:\n$stack');
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
      debugPrint('  _syncBlockchain: downloading chain for "$eventName"'
          '  localDir="$eventsDir"');
      final ok = await _storage.downloadBlockchainFile(
        eventName: eventName,
        localEventsDir: eventsDir,
      );
      debugPrint('  _syncBlockchain: download ok=$ok');
      if (ok) {
        _ffi.loadEvent(eventName);
        debugPrint('  _syncBlockchain: FFI.loadEvent() called');
      } else {
        debugPrint('  _syncBlockchain: download returned false — will mine'
            ' on top of any existing local chain');
      }
    } catch (e) {
      debugPrint('⚠️  _syncBlockchain error: $e');
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
    debugPrint('  _uploadBlockchain: safeName="$safeName"');

    for (final dirPath in [eventsDir, appDocDir]) {
      final file = File('$dirPath/$safeName.web3chain');
      final exists = await file.exists();
      debugPrint('  _uploadBlockchain: checking "$dirPath/$safeName.web3chain"'
          '  exists=$exists');
      if (exists) {
        await _storage.uploadBlockchainFile(
            eventName: eventName, chainFile: file);
        debugPrint('  _uploadBlockchain: uploaded from "$dirPath"');
        return;
      }
    }
    debugPrint('⚠️  _uploadBlockchain: .web3chain file not found in either'
        ' directory — blockchain NOT uploaded');
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
