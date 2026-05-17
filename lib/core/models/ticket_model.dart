// lib/core/models/ticket_model.dart
//
// Dart mirror of the C++ EventTicket struct.
// Travels across the FFI boundary as JSON.

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

  factory TicketModel.fromJson(Map<String, dynamic> json) => TicketModel(
        ticketID:   json['ticketID']   as String? ?? '',
        eventName:  json['eventName']  as String? ?? '',
        eventDate:  json['eventDate']  as String? ?? '',
        venue:      json['venue']      as String? ?? '',
        ownerName:  json['ownerName']  as String? ?? '',
        ownerID:    json['ownerID']    as String? ?? '',
        ticketType: json['ticketType'] as String? ?? 'General',
        price:      (json['price']     as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'ticketID':   ticketID,
        'eventName':  eventName,
        'eventDate':  eventDate,
        'venue':      venue,
        'ownerName':  ownerName,
        'ownerID':    ownerID,
        'ticketType': ticketType,
        'price':      price,
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
        ticketID:   ticketID   ?? this.ticketID,
        eventName:  eventName  ?? this.eventName,
        eventDate:  eventDate  ?? this.eventDate,
        venue:      venue      ?? this.venue,
        ownerName:  ownerName  ?? this.ownerName,
        ownerID:    ownerID    ?? this.ownerID,
        ticketType: ticketType ?? this.ticketType,
        price:      price      ?? this.price,
      );

  @override
  String toString() =>
      'TicketModel(id=$ticketID, event=$eventName, owner=$ownerName)';
}

/// Mirrors the block wrapper returned by eventchain_get_chain_json
class BlockModel {
  final int index;
  final TicketModel ticket;

  const BlockModel({required this.index, required this.ticket});

  factory BlockModel.fromJson(Map<String, dynamic> json) => BlockModel(
        index:  json['index'] as int,
        ticket: TicketModel.fromJson(json['ticket'] as Map<String, dynamic>),
      );
}
