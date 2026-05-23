// lib/core/models/ticket_record.dart
//
// Mirrors the Supabase `tickets` table and the `v_ticket_detail` view.
// Separate from TicketModel, which is the C++ FFI / blockchain model.

import 'package:eventchain/core/models/ticket_model.dart';

enum TicketType { general, vip, backstage, student }

extension TicketTypeX on TicketType {
  // Matches the Postgres enum values exactly
  String get dbValue => switch (this) {
        TicketType.general => 'General',
        TicketType.vip => 'VIP',
        TicketType.backstage => 'Backstage',
        TicketType.student => 'Student',
      };

  static TicketType fromString(String s) => switch (s) {
        'VIP' => TicketType.vip,
        'Backstage' => TicketType.backstage,
        'Student' => TicketType.student,
        _ => TicketType.general,
      };
}

class TicketRecord {
  // ── Primary key ───────────────────────────────────────────────────────────
  final String id; // uuid

  // ── Blockchain fields ─────────────────────────────────────────────────────
  final String ticketId; // short human-readable ID from FFI
  final int blockIndex; // 0-based chain index
  final String? stegoUrl; // Supabase Storage URL for the stego PNG

  // ── Ownership ─────────────────────────────────────────────────────────────
  final String eventId; // FK → events.id
  final String ownerId; // FK → auth.users
  final String ownerName;
  final TicketType ticketType;
  final double price;

  // ── Transfer / resale ─────────────────────────────────────────────────────
  final bool isSold;
  final String? soldTo; // FK → auth.users if transferred
  final DateTime? soldAt;
  final String? buyerEmail;
  final String? buyerPhone;

  // ── Soft-delete ───────────────────────────────────────────────────────────
  final DateTime? deletedAt;

  // ── Timestamps ────────────────────────────────────────────────────────────
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Joined from events (populated when querying v_ticket_detail) ──────────
  final String? eventName;
  final String? venue;
  final DateTime? eventDate;
  final String? posterUrl;
  final String? eventOwnerId;

  const TicketRecord({
    required this.id,
    required this.ticketId,
    required this.blockIndex,
    this.stegoUrl,
    required this.eventId,
    required this.ownerId,
    required this.ownerName,
    required this.ticketType,
    required this.price,
    required this.isSold,
    this.soldTo,
    this.soldAt,
    this.buyerEmail,
    this.buyerPhone,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.eventName,
    this.venue,
    this.eventDate,
    this.posterUrl,
    this.eventOwnerId,
  });

  // Use this when querying the tickets table directly.
  factory TicketRecord.fromMap(Map<String, dynamic> m) => TicketRecord(
        id: m['id'] as String,
        ticketId: m['ticket_id'] as String,
        blockIndex: m['block_index'] as int,
        stegoUrl: m['stego_url'] as String?,
        eventId: m['event_id'] as String,
        ownerId: m['owner_id'] as String,
        ownerName: m['owner_name'] as String,
        ticketType: TicketTypeX.fromString(m['ticket_type'] as String),
        price: (m['price'] as num).toDouble(),
        isSold: m['is_sold'] as bool,
        soldTo: m['sold_to'] as String?,
        soldAt: m['sold_at'] == null
            ? null
            : DateTime.parse(m['sold_at'] as String),
        buyerEmail: m['buyer_email'] as String?,
        buyerPhone: m['buyer_phone'] as String?,
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.parse(m['deleted_at'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        // These are only present when querying v_ticket_detail
        eventName: m['event_name'] as String?,
        venue: m['venue'] as String?,
        eventDate: m['event_date'] == null
            ? null
            : DateTime.parse(m['event_date'] as String),
        posterUrl: m['poster_url'] as String?,
        eventOwnerId: m['event_owner_id'] as String?,
      );

  // 1-based storage index — block 0 is genesis, first real ticket = index 1
  int get storageIndex => blockIndex + 1;

  bool get isActive => deletedAt == null;

  // Convert back to the FFI TicketModel for blockchain operations
  // (requires event fields to be populated via v_ticket_detail)
  TicketModel toFFIModel() => TicketModel(
        ticketID: ticketId,
        eventName: eventName ?? '',
        eventDate: eventDate?.toIso8601String() ?? '',
        venue: venue ?? '',
        ownerName: ownerName,
        ownerID: ownerId,
        ticketType: ticketType.dbValue,
        price: price,
      );
}
