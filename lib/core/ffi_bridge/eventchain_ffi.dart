// lib/core/ffi_bridge/eventchain_ffi.dart
//
// High-level Dart wrapper around the C++ EventChain library.

import 'dart:async';
import 'dart:ffi';
import 'dart:convert';

import 'package:ffi/ffi.dart';

import 'eventchain_bindings.dart';
import '../models/ticket_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Image Format Constants
//
// The C++ steganography layer (stb_image_write + CImg) supports exactly two
// lossless output formats:
//
//   png  — written via stb_image_write  ✓ recommended for stego output
//   bmp  — written via CImg             ✓ accepted
//
// JPEG and WebP are NOT listed here. Both are rejected by the C++ layer
// (returns -1) because lossy re-quantisation destroys the embedded payload.
// There is also no Dart-side image-processing package in this project to
// perform the conversion. If lossy sharing is ever needed, add a package
// (e.g. flutter_image_compress) and convert AFTER the stego PNG is produced —
// never pass a lossy file back into embedTicket() or extractAndVerify().
// ─────────────────────────────────────────────────────────────────────────────
class ImageFormat {
  static const int png = 0;
  static const int bmp = 1;

  /// Returns true if [format] is safe to use as a stego container.
  static bool isStegoSafe(int format) => format == png || format == bmp;
}

// ─────────────────────────────────────────────────────────────────────────────
// Singleton
// ─────────────────────────────────────────────────────────────────────────────
class EventChainFFI {
  EventChainFFI._();
  static final EventChainFFI instance = EventChainFFI._();

  late final EventChainBindings _bindings;
  late final Pointer<Void> _handle;
  bool _initialized = false;

  Future<void> init(String storageFolder) async {
    if (_initialized) return;

    final lib = DynamicLibrary.open('libEventChain.so');
    _bindings = EventChainBindings(lib);

    final folderPtr = storageFolder.toNativeUtf8();
    _handle = _bindings.create(folderPtr, 2);
    calloc.free(folderPtr);

    if (_handle == nullptr) {
      throw StateError('eventchain_create() returned null');
    }
    _initialized = true;
  }

  void dispose() {
    if (_initialized) {
      _bindings.destroy(_handle);
      _initialized = false;
    }
  }

  String _readAndFree(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return '';
    final s = ptr.toDartString();
    _bindings.freeString(ptr);
    return s;
  }

  // ── Blockchain ────────────────────────────────────────────────────────────

  Future<bool> addTicket(String eventName, TicketModel ticket) async {
    final enPtr = eventName.toNativeUtf8();
    final jsPtr = jsonEncode(ticket.toJson()).toNativeUtf8();
    final result = _bindings.addTicket(_handle, enPtr, jsPtr);
    calloc.free(enPtr);
    calloc.free(jsPtr);
    return result == 0;
  }

  Future<bool> validateEvent(String eventName) async {
    final ptr = eventName.toNativeUtf8();
    final r = _bindings.validate(_handle, ptr);
    calloc.free(ptr);
    return r == 1;
  }

  int getEventSize(String eventName) {
    final ptr = eventName.toNativeUtf8();
    final r = _bindings.getSize(_handle, ptr);
    calloc.free(ptr);
    return r;
  }

  Future<List<Map<String, dynamic>>> getChainJson(String eventName) async {
    final ptr = eventName.toNativeUtf8();
    final rPtr = _bindings.getChainJson(_handle, ptr);
    calloc.free(ptr);
    if (rPtr == nullptr) return [];
    final s = _readAndFree(rPtr);
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  Future<bool> transferOwnership({
    required String eventName,
    required int blockIndex,
    required String newOwnerName,
    required String newOwnerID,
  }) async {
    final enPtr = eventName.toNativeUtf8();
    final noPtr = newOwnerName.toNativeUtf8();
    final idPtr = newOwnerID.toNativeUtf8();
    final r =
        _bindings.transferOwnership(_handle, enPtr, blockIndex, noPtr, idPtr);
    calloc.free(enPtr);
    calloc.free(noPtr);
    calloc.free(idPtr);
    return r == 0;
  }

  TicketModel? getTicket(String eventName, int blockIndex) {
    final enPtr = eventName.toNativeUtf8();
    final rPtr = _bindings.getTicketJson(_handle, enPtr, blockIndex);
    calloc.free(enPtr);
    if (rPtr == nullptr) return null;
    final json = _readAndFree(rPtr);
    try {
      return TicketModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool saveEvent(String eventName) {
    final ptr = eventName.toNativeUtf8();
    final r = _bindings.save(_handle, ptr);
    calloc.free(ptr);
    return r == 0;
  }

  bool loadEvent(String eventName) {
    final ptr = eventName.toNativeUtf8();
    final r = _bindings.load(_handle, ptr);
    calloc.free(ptr);
    return r == 0;
  }

  List<String> listEvents() {
    final rPtr = _bindings.listEvents(_handle);
    if (rPtr == nullptr) return [];
    final s = _readAndFree(rPtr);
    try {
      return (jsonDecode(s) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  // ── Steganography ─────────────────────────────────────────────────────────

  /// Generate a synthetic cover image at [outputPath].
  ///
  /// [outputPath] must end in `.png` (recommended) or `.bmp`.
  /// Any other extension is rejected by the C++ layer and returns false.
  Future<bool> generateCover({
    required String outputPath,
    int width = 512,
    int height = 512,
  }) async {
    assert(
      outputPath.endsWith('.png') || outputPath.endsWith('.bmp'),
      'generateCover: outputPath must end in .png or .bmp — '
      'lossy formats are rejected by the C++ layer.',
    );
    final ptr = outputPath.toNativeUtf8();
    final r = _bindings.generateCover(ptr, width, height);
    calloc.free(ptr);
    return r == 0;
  }

  /// Embed the ticket at [blockIndex] into a stego image.
  ///
  /// [stegoPath] must end in `.png` (recommended) or `.bmp`.
  /// The C++ layer hard-rejects `.jpg` / `.webp` paths (returns -1).
  ///
  /// [coverPath] may be empty — the C++ layer will auto-generate a synthetic
  /// 512×512 PNG cover if none is provided.
  Future<bool> embedTicket({
    required String eventName,
    required int blockIndex,
    String coverPath = '',
    required String stegoPath,
  }) async {
    assert(
      stegoPath.endsWith('.png') || stegoPath.endsWith('.bmp'),
      'embedTicket: stegoPath must end in .png or .bmp — '
      'lossy formats are rejected by the C++ layer.',
    );
    final enPtr = eventName.toNativeUtf8();
    final cpPtr = coverPath.toNativeUtf8();
    final spPtr = stegoPath.toNativeUtf8();
    final r = _bindings.embedTicket(_handle, enPtr, blockIndex, cpPtr, spPtr);
    calloc.free(enPtr);
    calloc.free(cpPtr);
    calloc.free(spPtr);
    return r == 0;
  }

  /// Extract and verify a ticket from [stegoPath] against the on-chain block.
  ///
  /// [stegoPath] must point to a PNG or BMP produced by [embedTicket].
  /// Lossy-format paths will fail extraction due to payload corruption.
  Future<bool> extractAndVerify({
    required String stegoPath,
    required String eventName,
    required int blockIndex,
  }) async {
    final spPtr = stegoPath.toNativeUtf8();
    final enPtr = eventName.toNativeUtf8();
    final r = _bindings.extractVerify(_handle, spPtr, enPtr, blockIndex);
    calloc.free(spPtr);
    calloc.free(enPtr);
    return r == 1;
  }

  int stegoCapacity(int width, int height) => _bindings.capacity(width, height);

  // ── Utility ───────────────────────────────────────────────────────────────

  String get version {
    final ptr = _bindings.version();
    return ptr.toDartString();
  }
}
