// lib/core/services/supabase_storage_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseStorageService {
  SupabaseStorageService._();
  static final SupabaseStorageService instance = SupabaseStorageService._();

  final _client = Supabase.instance.client;

  static const _posterBucket = 'event-posters';
  static const _stegoBucket = 'stego-tickets';
  static const _blockchainBucket = 'blockchains';

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT POSTERS  (bucket: event-posters)
  // Path pattern:  events/{eventId}/poster.{ext}
  // ═══════════════════════════════════════════════════════════════════════════

  /// CREATE / UPDATE — upserts the poster image for [eventId].
  /// CREATE / UPDATE — upserts the poster image for [eventId].
  /// Retries up to [maxAttempts] times with exponential back-off to handle
  /// transient "Connection reset by peer" errors on mobile networks.
  Future<String?> uploadEventPoster({
    required String eventId,
    required File imageFile,
    int maxAttempts = 3,
  }) async {
    try {
      if (!await _assertFileReady(imageFile)) return null;

      final ext = _ext(imageFile.path);
      if (!_validImageExts.contains(ext)) {
        debugPrint('❌ Invalid poster extension: $ext');
        return null;
      }

      final path = 'events/$eventId/poster.$ext';

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await _client.storage.from(_posterBucket).upload(
                path,
                imageFile,
                fileOptions:
                    FileOptions(upsert: true, contentType: _mimeFor(ext)),
              );

          final url = _client.storage.from(_posterBucket).getPublicUrl(path);
          debugPrint('✅ Poster uploaded (attempt $attempt): $url');
          return url;
        } on StorageException catch (e) {
          // Storage-level errors (auth, bucket missing, etc.) are not
          // retryable — surface them immediately.
          debugPrint(
              '❌ StorageException (poster upload, attempt $attempt): ${e.message}');
          return null;
        } catch (e) {
          final isConnectionError = e.toString().contains('Connection reset') ||
              e.toString().contains('SocketException') ||
              e.toString().contains('Connection closed') ||
              e.toString().contains('ClientException');

          if (!isConnectionError || attempt == maxAttempts) {
            debugPrint('❌ Poster upload failed after $attempt attempt(s): $e');
            return null;
          }

          final delay = Duration(seconds: 1 << (attempt - 1)); // 1s, 2s, 4s
          debugPrint(
              '⚠️  Poster upload attempt $attempt failed (${e.runtimeType}). '
              'Retrying in ${delay.inSeconds}s…');
          await Future.delayed(delay);
        }
      }

      return null; // unreachable, but satisfies the type checker
    } catch (e, st) {
      debugPrint('❌ Unexpected error uploading poster: $e\n$st');
      return null;
    }
  }

  /// READ — downloads poster for [eventId] into [tempDir], returns local path.
  Future<String?> downloadEventPosterToTemp({
    required String eventId,
    required String posterUrl,
    required String tempDir,
  }) async {
    try {
      // Derive extension from the public URL (strip query params first).
      final ext = posterUrl.split('.').last.split('?').first.toLowerCase();
      final remotePath = 'events/$eventId/poster.$ext';
      final bytes =
          await _client.storage.from(_posterBucket).download(remotePath);
      final savePath = '$tempDir/cover_$eventId.$ext';
      await File(savePath).writeAsBytes(bytes);
      debugPrint('✅ Poster downloaded to: $savePath');
      return savePath;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (poster download): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to download poster: $e');
      return null;
    }
  }

  /// DELETE — removes poster for [eventId] (tries all valid extensions).
  Future<void> deleteEventPoster(String eventId) async {
    try {
      final candidates =
          _validImageExts.map((ext) => 'events/$eventId/poster.$ext').toList();
      await _client.storage.from(_posterBucket).remove(candidates);
      debugPrint('✅ Poster deleted for event: $eventId');
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (delete poster): ${e.message}');
    } catch (e) {
      debugPrint('❌ Unexpected error deleting poster: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEGO TICKETS  (bucket: stego-tickets)
  // Path pattern:  events/{eventId}/ticket_{blockIndex}.{ext}
  // NOTE: blockIndex is 1-based (ticket_1, ticket_2, …) to match C++ output.
  // ═══════════════════════════════════════════════════════════════════════════

  /// CREATE / UPDATE — upserts a single stego ticket file.
  Future<String?> uploadStegoTicket({
    required String eventId,
    required int blockIndex, // 1-based
    required File stegoFile,
  }) async {
    try {
      if (!await _assertFileReady(stegoFile)) return null;

      // Honour whatever extension C++ wrote (PNG or BMP).
      final ext = _ext(stegoFile.path);
      final path = 'events/$eventId/ticket_$blockIndex.$ext';

      await _client.storage.from(_stegoBucket).upload(
            path,
            stegoFile,
            fileOptions: FileOptions(upsert: true, contentType: _mimeFor(ext)),
          );

      final url = _client.storage.from(_stegoBucket).getPublicUrl(path);
      debugPrint('✅ Stego ticket uploaded: $url');
      return url;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (stego upload): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Unexpected error uploading stego ticket: $e');
      return null;
    }
  }

  /// READ — downloads ticket [blockIndex] for [eventId] into [tempDir].
  ///
  /// Try order: BMP → PNG
  /// (Existing tickets in storage are BMP; PNG covers future C++ output.)
  Future<String?> downloadStegoTicketToTemp({
    required String eventId,
    required int blockIndex, // 1-based
    required String tempDir,
  }) async {
    for (final ext in ['bmp', 'png']) {
      try {
        final path = 'events/$eventId/ticket_$blockIndex.$ext';
        final bytes = await _client.storage.from(_stegoBucket).download(path);
        final savePath = '$tempDir/stego_${eventId}_$blockIndex.$ext';
        await File(savePath).writeAsBytes(bytes);
        debugPrint('✅ Stego ticket downloaded ($ext): $path');
        return savePath;
      } on StorageException catch (e) {
        final body = e.message;
        // 404 → try next extension; anything else → bail out immediately.
        if (!body.contains('not_found') && !body.contains('404')) {
          debugPrint('❌ StorageException (stego download): ${e.message}');
          return null;
        }
      } catch (e) {
        debugPrint('❌ Failed to download stego ticket: $e');
        return null;
      }
    }
    debugPrint(
      '❌ Stego ticket not found in storage: '
      'events/$eventId/ticket_$blockIndex.[bmp|png]',
    );
    return null;
  }

  /// DELETE — removes a single stego ticket (tries BMP and PNG).
  Future<void> deleteStegoTicket({
    required String eventId,
    required int blockIndex, // 1-based
  }) async {
    try {
      final candidates = ['bmp', 'png']
          .map((ext) => 'events/$eventId/ticket_$blockIndex.$ext')
          .toList();
      await _client.storage.from(_stegoBucket).remove(candidates);
      debugPrint('✅ Stego ticket deleted: events/$eventId/ticket_$blockIndex');
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (delete stego ticket): ${e.message}');
    } catch (e) {
      debugPrint('❌ Unexpected error deleting stego ticket: $e');
    }
  }

  /// DELETE ALL — removes every ticket in the events/{eventId}/ prefix.
  /// Call this when deleting an entire event.
  Future<void> deleteAllStegoTicketsForEvent(String eventId) async {
    try {
      // List every file under events/{eventId}/ then bulk-remove them.
      final files = await _client.storage
          .from(_stegoBucket)
          .list(path: 'events/$eventId');
      if (files.isEmpty) {
        debugPrint('ℹ️ No stego tickets found for event: $eventId');
        return;
      }
      final paths = files
          .where((f) => f.name.isNotEmpty)
          .map((f) => 'events/$eventId/${f.name}')
          .toList();
      await _client.storage.from(_stegoBucket).remove(paths);
      debugPrint(
          '✅ Deleted ${paths.length} stego ticket(s) for event: $eventId');
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (delete all stego tickets): ${e.message}');
    } catch (e) {
      debugPrint('❌ Unexpected error deleting stego tickets: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLOCKCHAIN FILES  (bucket: blockchains)
  // Path pattern:  {safeName}.web3chain
  // ═══════════════════════════════════════════════════════════════════════════

  /// CREATE / UPDATE — upserts the .web3chain file for [eventName].
  Future<bool> uploadBlockchainFile({
    required String eventName,
    required File chainFile,
  }) async {
    try {
      if (!await _assertFileReady(chainFile)) return false;

      final path = '${_safeName(eventName)}.web3chain';
      await _client.storage.from(_blockchainBucket).upload(
            path,
            chainFile,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'application/octet-stream',
            ),
          );
      debugPrint('✅ Blockchain file uploaded: $path');
      return true;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (blockchain upload): ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error uploading blockchain: $e');
      return false;
    }
  }

  /// READ — downloads the .web3chain file for [eventName] to [localEventsDir].
  Future<bool> downloadBlockchainFile({
    required String eventName,
    required String localEventsDir,
  }) async {
    try {
      final safeName = _safeName(eventName);
      final bytes = await _client.storage
          .from(_blockchainBucket)
          .download('$safeName.web3chain');
      final savePath = '$localEventsDir/$safeName.web3chain';
      await File(savePath).writeAsBytes(bytes);
      debugPrint('✅ Blockchain file downloaded: $savePath');
      return true;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (blockchain download): ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Failed to download blockchain: $e');
      return false;
    }
  }

  /// DELETE — removes the .web3chain file for [eventName].
  Future<void> deleteBlockchainFile(String eventName) async {
    try {
      final safeName = _safeName(eventName);
      await _client.storage
          .from(_blockchainBucket)
          .remove(['$safeName.web3chain']);
      debugPrint('✅ Blockchain file deleted: $safeName.web3chain');
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (delete blockchain): ${e.message}');
    } catch (e) {
      debugPrint('❌ Unexpected error deleting blockchain: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVENIENCE — full event teardown
  // ═══════════════════════════════════════════════════════════════════════════

  /// Deletes the poster, all stego tickets, and the blockchain file for an
  /// event in parallel.  Safe to call even if some assets were never created.
  Future<void> deleteAllAssetsForEvent({
    required String eventId,
    required String eventName,
  }) async {
    await Future.wait([
      deleteEventPoster(eventId),
      deleteAllStegoTicketsForEvent(eventId),
      deleteBlockchainFile(eventName),
    ]);
    debugPrint('✅ All assets deleted for event: $eventId ($eventName)');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  static const _validImageExts = ['jpg', 'jpeg', 'png', 'bmp', 'webp'];

  String _ext(String path) => path.split('.').last.toLowerCase();

  String _safeName(String name) =>
      name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _mimeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  /// Returns false (and prints a reason) if the file doesn't exist or is empty.
  Future<bool> _assertFileReady(File file) async {
    if (!await file.exists()) {
      debugPrint('❌ File does not exist: ${file.path}');
      return false;
    }
    if (await file.length() == 0) {
      debugPrint('❌ File is empty (0 bytes): ${file.path}');
      return false;
    }
    return true;
  }
}
