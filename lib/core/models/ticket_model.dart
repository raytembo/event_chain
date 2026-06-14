// lib/core/models/ticket_model.dart
//
// Dart mirror of the C++ EventTicket struct.
// Travels across the FFI boundary as JSON.
//
// Both fromJson factories use defensive helpers (_str, _dbl, _int) instead of
// direct `as T` casts to prevent TypeErrors from malformed payloads.

// ── Private parsing helpers ──────────────────────────────────────────────────

String _str(dynamic v) {
  if (v is String) return v;
  return '';
}

double _dbl(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

// ── TicketModel ─────────────────────────────────────────────────────────────

class TicketModel {
  final String ticketID;
  final String eventName;
  final String eventDate;
  final String venue;
  final String ownerName;
  final String ownerID;
  final String ticketType;
  final double price;

  const TicketModel({
    required this.ticketID,
    required this.eventName,
    required this.eventDate,
    required this.venue,
    required this.ownerName,
    required this.ownerID,
    required this.ticketType,
    required this.price,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    final type = _str(json['ticketType']);
    return TicketModel(
      ticketID: _str(json['ticketID']),
      eventName: _str(json['eventName']),
      eventDate: _str(json['eventDate']),
      venue: _str(json['venue']),
      ownerName: _str(json['ownerName']),
      ownerID: _str(json['ownerID']),
      ticketType: type.isEmpty ? 'General' : type,
      price: _dbl(json['price']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ticketID': ticketID,
        'eventName': eventName,
        'eventDate': eventDate,
        'venue': venue,
        'ownerName': ownerName,
        'ownerID': ownerID,
        'ticketType': ticketType,
        'price': price,
      };

  TicketModel copyWith({
    String? ticketID,
    String? eventName,
    String? eventDate,
    String? venue,
    String? ownerName,
    String? ownerID,
    String? ticketType,
    double? price,
  }) =>
      TicketModel(
        ticketID: ticketID ?? this.ticketID,
        eventName: eventName ?? this.eventName,
        eventDate: eventDate ?? this.eventDate,
        venue: venue ?? this.venue,
        ownerName: ownerName ?? this.ownerName,
        ownerID: ownerID ?? this.ownerID,
        ticketType: ticketType ?? this.ticketType,
        price: price ?? this.price,
      );

  @override
  String toString() =>
      'TicketModel(id=$ticketID, event=$eventName, owner=$ownerName)';
}

// ── BlockModel ──────────────────────────────────────────────────────────────

/// Mirrors the block wrapper returned by eventchain_get_chain_json.
class BlockModel {
  final int index;
  final TicketModel ticket;

  const BlockModel({required this.index, required this.ticket});

  /// 1-based index used for Supabase Storage paths (ticket_1, ticket_2, …).
  ///
  /// C++ chain indices are 0-based; storage paths are 1-based because block 0
  /// is the genesis block (no ticket) and the first real ticket lands at
  /// block 1 → uploaded as ticket_1.png.  Always use this getter when
  /// constructing or resolving storage paths — never add 1 manually at call
  /// sites.
  int get storageIndex => index + 1;

  factory BlockModel.fromJson(Map<String, dynamic> json) {
    final rawTicket = json['ticket'];
    final ticket = rawTicket is Map<String, dynamic>
        ? TicketModel.fromJson(rawTicket)
        : TicketModel.fromJson(const <String, dynamic>{});

    return BlockModel(
      index: _parseInt(json['index']),
      ticket: ticket,
    );
  }
}
