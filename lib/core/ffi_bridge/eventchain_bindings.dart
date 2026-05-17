// lib/core/ffi_bridge/eventchain_bindings.dart
//
// Raw FFI type bindings for libEventChain.so.
// C++ layer writes PNG (via stb_image_write) and BMP only.
// Lossy formats (JPEG, WebP) are hard-rejected by the C++ layer.

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ── Type aliases ────────────────────────────────────────────────────────────
typedef _CreateNative  = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _CreateDart    = Pointer<Void> Function(Pointer<Utf8>, int);



typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart   = void Function(Pointer<Void>);

typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart   = void Function(Pointer<Utf8>);

typedef _IntStrNative  = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _IntStrDart    = int   Function(Pointer<Void>, Pointer<Utf8>);

typedef _AddTicketNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _AddTicketDart   = int   Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef _TransferNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef _TransferDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>);

typedef _GetChainJsonNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _GetChainJsonDart   = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef _GetTicketJsonNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _GetTicketJsonDart   = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _ListEventsNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _ListEventsDart   = Pointer<Utf8> Function(Pointer<Void>);

// ── Steganography typedefs ───────────────────────────────────────────────────
// generateCover has NO handle parameter — it is a standalone utility.
// C signature: int eventchain_generate_cover(const char* outputPath, int w, int h)
// PNG output path → stb_image_write; BMP → CImg native.
// Passing a .jpg / .webp path is rejected by C++ with return value -1.
typedef _GenCoverNative = Int32 Function(Pointer<Utf8>, Int32, Int32);
typedef _GenCoverDart   = int   Function(Pointer<Utf8>, int, int);

typedef _EmbedNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef _EmbedDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>);

typedef _ExtractVerifyNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _ExtractVerifyDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int);

typedef _CapacityNative = Int32 Function(Int32, Int32);
typedef _CapacityDart   = int   Function(int, int);

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart   = Pointer<Utf8> Function();



// ── EventChainBindings ──────────────────────────────────────────────────────
class EventChainBindings {
  final DynamicLibrary _lib;

  EventChainBindings(this._lib);

  late final _CreateDart  create  = _lib
      .lookupFunction<_CreateNative, _CreateDart>('eventchain_create');
  late final _DestroyDart destroy = _lib
      .lookupFunction<_DestroyNative, _DestroyDart>('eventchain_destroy');

  late final _FreeStringDart freeString = _lib
      .lookupFunction<_FreeStringNative, _FreeStringDart>('eventchain_free_string');

  late final _AddTicketDart addTicket = _lib
      .lookupFunction<_AddTicketNative, _AddTicketDart>('eventchain_add_ticket');
  late final _IntStrDart validate = _lib
      .lookupFunction<_IntStrNative, _IntStrDart>('eventchain_validate');
  late final _IntStrDart getSize = _lib
      .lookupFunction<_IntStrNative, _IntStrDart>('eventchain_get_size');
  late final _GetChainJsonDart getChainJson = _lib
      .lookupFunction<_GetChainJsonNative, _GetChainJsonDart>('eventchain_get_chain_json');
  late final _TransferDart transferOwnership = _lib
      .lookupFunction<_TransferNative, _TransferDart>('eventchain_transfer_ownership');
  late final _GetTicketJsonDart getTicketJson = _lib
      .lookupFunction<_GetTicketJsonNative, _GetTicketJsonDart>('eventchain_get_ticket_json');
  late final _IntStrDart save = _lib
      .lookupFunction<_IntStrNative, _IntStrDart>('eventchain_save');
  late final _IntStrDart load = _lib
      .lookupFunction<_IntStrNative, _IntStrDart>('eventchain_load');
  late final _ListEventsDart listEvents = _lib
      .lookupFunction<_ListEventsNative, _ListEventsDart>('eventchain_list_events');

  // ── Steganography ───────────────────────────────────────────────────────
  // generateCover: no handle — standalone utility function.
  // C signature: int eventchain_generate_cover(const char*, int, int)
  // Outputs PNG by default (via stb_image_write). BMP also accepted.
  // Lossy formats (JPEG, WebP) are rejected by the C++ layer.
  late final _GenCoverDart generateCover = _lib
      .lookupFunction<_GenCoverNative, _GenCoverDart>('eventchain_generate_cover');
  late final _EmbedDart embedTicket = _lib
      .lookupFunction<_EmbedNative, _EmbedDart>('eventchain_embed_ticket');
  late final _ExtractVerifyDart extractVerify = _lib
      .lookupFunction<_ExtractVerifyNative, _ExtractVerifyDart>('eventchain_extract_verify');
  late final _CapacityDart capacity = _lib
      .lookupFunction<_CapacityNative, _CapacityDart>('eventchain_stego_capacity');

  late final _VersionDart version = _lib
      .lookupFunction<_VersionNative, _VersionDart>('eventchain_version');
}