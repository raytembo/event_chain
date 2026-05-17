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

  Future<String?> uploadEventPoster({
    required String eventId,
    required File imageFile,
  }) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('❌ ERROR: Poster file does not exist at path: ${imageFile.path}');
        return null;
      }
      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        debugPrint('❌ ERROR: Poster file is empty (0 bytes)');
        return null;
      }

      final ext = imageFile.path.split('.').last.toLowerCase();
      final validExtensions = ['jpg', 'jpeg', 'png', 'bmp', 'webp'];
      if (!validExtensions.contains(ext)) {
        debugPrint('❌ ERROR: Invalid poster extension: $ext');
        return null;
      }

      final path = 'events/$eventId/poster.$ext';
      final mimeType = _mimeFor(ext);

      await _client.storage
          .from(_posterBucket)
          .upload(
        path,
        imageFile,
        fileOptions: FileOptions(
          upsert: true,
          contentType: mimeType,
        ),
      );

      final publicUrl = _client.storage.from(_posterBucket).getPublicUrl(path);
      debugPrint('✅ Poster uploaded successfully: $publicUrl');
      return publicUrl;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (poster): ${e.message}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('❌ Unexpected error uploading poster: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<String?> downloadEventPosterToTemp({
    required String eventId,
    required String posterUrl,
    required String tempDir,
  }) async {
    try {
      final ext = posterUrl.split('.').last.split('?').first;
      final savePath = '$tempDir/cover_$eventId.$ext';
      final bytes = await _client.storage
          .from(_posterBucket)
          .download('events/$eventId/poster.$ext');
      await File(savePath).writeAsBytes(bytes);
      return savePath;
    } catch (e) {
      debugPrint('❌ Failed to download poster: $e');
      return null;
    }
  }

  Future<String?> uploadStegoTicket({
    required String eventId,
    required int blockIndex,
    required File stegoFile,
  }) async {
    try {
      if (!await stegoFile.exists()) {
        debugPrint('❌ ERROR: Stego file does not exist at path: ${stegoFile.path}');
        return null;
      }
      final fileSize = await stegoFile.length();
      if (fileSize == 0) {
        debugPrint('❌ ERROR: Stego file is empty (0 bytes)');
        return null;
      }

      // Derive extension from the actual file — C++ outputs PNG by default
      // (via stb_image_write), so hardcoding .bmp would cause a 404 on download.
      final ext = stegoFile.path.split('.').last.toLowerCase();
      final path = 'events/$eventId/ticket_$blockIndex.$ext';

      await _client.storage
          .from(_stegoBucket)
          .upload(
        path,
        stegoFile,
        fileOptions: FileOptions(
          upsert: true,
          contentType: _mimeFor(ext),
        ),
      );

      final publicUrl = _client.storage.from(_stegoBucket).getPublicUrl(path);
      debugPrint('✅ Stego ticket uploaded successfully: $publicUrl');
      return publicUrl;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (stego): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Unexpected error uploading stego ticket: $e');
      return null;
    }
  }

  Future<String?> downloadStegoTicketToTemp({
    required String eventId,
    required int blockIndex,
    required String tempDir,
  }) async {
    // C++ writes PNG by default; older tickets may have been uploaded as BMP.
    // Try PNG first, fall back to BMP so legacy tickets still work.
    for (final ext in ['png', 'bmp']) {
      try {
        final path = 'events/$eventId/ticket_$blockIndex.$ext';
        final bytes = await _client.storage.from(_stegoBucket).download(path);
        final savePath = '$tempDir/stego_${eventId}_$blockIndex.$ext';
        await File(savePath).writeAsBytes(bytes);
        debugPrint('✅ Stego ticket downloaded: $path');
        return savePath;
      } on StorageException catch (e) {
        // 404 → try next extension; any other error → give up immediately.
        final body = e.message ?? '';
        if (!body.contains('not_found') && !body.contains('404')) {
          debugPrint('❌ StorageException (stego download): ${e.message}');
          return null;
        }
      } catch (e) {
        debugPrint('❌ Failed to download stego ticket: $e');
        return null;
      }
    }
    debugPrint('❌ Stego ticket not found in storage: events/$eventId/ticket_$blockIndex.[png|bmp]');
    return null;
  }

  Future<bool> uploadBlockchainFile({
    required String eventName,
    required File chainFile,
  }) async {
    try {
      if (!await chainFile.exists()) {
        debugPrint('❌ ERROR: Blockchain file does not exist at path: ${chainFile.path}');
        return false;
      }
      final fileSize = await chainFile.length();
      if (fileSize == 0) {
        debugPrint('❌ ERROR: Blockchain file is empty (0 bytes)');
        return false;
      }

      final safeName = _safeName(eventName);
      final path = '$safeName.web3chain';

      await _client.storage
          .from(_blockchainBucket)
          .upload(
        path,
        chainFile,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'application/octet-stream',
        ),
      );

      debugPrint('✅ Blockchain file uploaded successfully: $path');
      return true;
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (blockchain): ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error uploading blockchain: $e');
      return false;
    }
  }

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
      return true;
    } catch (e) {
      debugPrint('❌ Failed to download blockchain: $e');
      return false;
    }
  }

  // ── Delete helpers (used by event deletion flow) ──────────────────────────

  /// Removes the `.web3chain` file for the given [eventName] from storage.
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

  /// Removes the poster for [eventId] from storage.
  /// Tries all supported extensions since the original extension isn't stored
  /// separately — Supabase silently ignores paths that don't exist.
  Future<void> deleteEventPoster(String eventId) async {
    try {
      final candidates = ['jpg', 'jpeg', 'png', 'bmp', 'webp']
          .map((ext) => 'events/$eventId/poster.$ext')
          .toList();
      await _client.storage.from(_posterBucket).remove(candidates);
      debugPrint('✅ Poster deleted for event: $eventId');
    } on StorageException catch (e) {
      debugPrint('❌ StorageException (delete poster): ${e.message}');
    } catch (e) {
      debugPrint('❌ Unexpected error deleting poster: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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
}