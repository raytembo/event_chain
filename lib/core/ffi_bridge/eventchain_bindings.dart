// lib/core/ffi_bridge/eventchain_bindings.dart

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ── Type aliases ─────────────────────────────────────────────────────────────
typedef CreateNative = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef CreateDart = Pointer<Void> Function(Pointer<Utf8>, int);

typedef DestroyNative = Void Function(Pointer<Void>);
typedef DestroyDart = void Function(Pointer<Void>);

typedef FreeStringNative = Void Function(Pointer<Utf8>);
typedef FreeStringDart = void Function(Pointer<Utf8>);

typedef IntStrNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef IntStrDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef AddTicketNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef AddTicketDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef TransferNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef TransferDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>);

typedef GetChainJsonNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef GetChainJsonDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef GetTicketJsonNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Int32);
typedef GetTicketJsonDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, int);

typedef ListEventsNative = Pointer<Utf8> Function(Pointer<Void>);
typedef ListEventsDart = Pointer<Utf8> Function(Pointer<Void>);

// ── Steganography typedefs ────────────────────────────────────────────────────
typedef GenCoverNative = Int32 Function(Pointer<Utf8>, Int32, Int32);
typedef GenCoverDart = int Function(Pointer<Utf8>, int, int);

typedef EmbedNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef EmbedDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>);

typedef ExtractVerifyNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef ExtractVerifyDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int);

typedef CapacityNative = Int32 Function(Int32, Int32);
typedef CapacityDart = int Function(int, int);

typedef VersionNative = Pointer<Utf8> Function();
typedef VersionDart = Pointer<Utf8> Function();

// ── EventChainBindings ────────────────────────────────────────────────────────
class EventChainBindings {
  final DynamicLibrary _lib;

  EventChainBindings(this._lib);

  late final CreateDart create =
      _lib.lookupFunction<CreateNative, CreateDart>('eventchain_create');
  late final DestroyDart destroy =
      _lib.lookupFunction<DestroyNative, DestroyDart>('eventchain_destroy');

  late final FreeStringDart freeString =
      _lib.lookupFunction<FreeStringNative, FreeStringDart>(
          'eventchain_free_string');

  late final AddTicketDart addTicket = _lib
      .lookupFunction<AddTicketNative, AddTicketDart>('eventchain_add_ticket');
  late final IntStrDart validate =
      _lib.lookupFunction<IntStrNative, IntStrDart>('eventchain_validate');
  late final IntStrDart getSize =
      _lib.lookupFunction<IntStrNative, IntStrDart>('eventchain_get_size');
  late final GetChainJsonDart getChainJson =
      _lib.lookupFunction<GetChainJsonNative, GetChainJsonDart>(
          'eventchain_get_chain_json');
  late final TransferDart transferOwnership =
      _lib.lookupFunction<TransferNative, TransferDart>(
          'eventchain_transfer_ownership');
  late final GetTicketJsonDart getTicketJson =
      _lib.lookupFunction<GetTicketJsonNative, GetTicketJsonDart>(
          'eventchain_get_ticket_json');
  late final IntStrDart save =
      _lib.lookupFunction<IntStrNative, IntStrDart>('eventchain_save');
  late final IntStrDart load =
      _lib.lookupFunction<IntStrNative, IntStrDart>('eventchain_load');
  late final ListEventsDart listEvents =
      _lib.lookupFunction<ListEventsNative, ListEventsDart>(
          'eventchain_list_events');

  // ── Steganography ──────────────────────────────────────────────────────────
  late final GenCoverDart generateCover =
      _lib.lookupFunction<GenCoverNative, GenCoverDart>(
          'eventchain_generate_cover');
  late final EmbedDart embedTicket =
      _lib.lookupFunction<EmbedNative, EmbedDart>('eventchain_embed_ticket');
  late final ExtractVerifyDart extractVerify =
      _lib.lookupFunction<ExtractVerifyNative, ExtractVerifyDart>(
          'eventchain_extract_verify');
  late final CapacityDart capacity =
      _lib.lookupFunction<CapacityNative, CapacityDart>(
          'eventchain_stego_capacity');

  late final VersionDart version =
      _lib.lookupFunction<VersionNative, VersionDart>('eventchain_version');
}
