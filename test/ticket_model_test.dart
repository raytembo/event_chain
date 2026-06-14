import 'package:flutter_test/flutter_test.dart';
import 'package:eventchain/core/models/ticket_model.dart';

void main() {
  group('TicketModel Serialization', () {
    test('fromJson parses a well-formed JSON map correctly', () {
      final json = {
        'ticketID': 'TKT-1024',
        'eventName': 'Tech Summit',
        'eventDate': '2026-08-15T09:00:00Z',
        'venue': 'Bingu International Convention Centre',
        'ownerName': 'Raymond Tembo',
        'ownerID': 'usr-1',
        'ticketType': 'VIP',
        'price': 45000, // Note: int in JSON, should parse to double
      };

      final ticket = TicketModel.fromJson(json);

      expect(ticket.ticketID, 'TKT-1024');
      expect(ticket.eventName, 'Tech Summit');
      expect(ticket.venue, 'Bingu International Convention Centre');
      expect(ticket.ownerName, 'Raymond Tembo');
      expect(ticket.ticketType, 'VIP');
      expect(ticket.price, 45000.0);
    });

    test('fromJson falls back gracefully when fields are missing or null', () {
      final incompleteJson = {
        'ticketID': 'TKT-002',
        // Missing eventName, venue, ownerName, etc.
        'ticketType': null,
        'price': null,
      };

      final ticket = TicketModel.fromJson(incompleteJson);

      expect(ticket.ticketID, 'TKT-002');
      expect(ticket.eventName, '');
      expect(ticket.venue, '');
      expect(ticket.ticketType, 'General'); // Fallback for null/missing type
      expect(ticket.price, 0.0);
    });

    test(
        'fromJson defends against completely wrong data types without crashing',
        () {
      final corruptedJson = {
        'ticketID': 12345, // Should be String
        'eventName': ['Array', 'Instead', 'Of', 'String'], // Should be String
        'ticketType': 99, // Should be String
        'price': 'Not a number', // Should be numeric
      };

      final ticket = TicketModel.fromJson(corruptedJson);

      expect(ticket.ticketID, '');
      expect(ticket.eventName, '');
      expect(ticket.ticketType,
          'General'); // Rejects the int, falls back to General
      expect(ticket.price,
          0.0); // Rejects the unparseable string, falls back to 0.0
    });

    test('price parses strings containing valid numbers correctly', () {
      final json = {
        'ticketID': 'TKT-003',
        'price': '15000.50', // String representation of a float
      };

      final ticket = TicketModel.fromJson(json);
      expect(ticket.price, 15000.50);
    });

    test('toJson serializes fields back into a Map', () {
      const ticket = TicketModel(
        ticketID: 'TKT-XYZ',
        eventName: 'Gala',
        eventDate: '2026-12-31',
        venue: 'Grand Hall',
        ownerName: 'Alice',
        ownerID: 'usr-2',
        ticketType: 'General',
        price: 100.0,
      );

      final map = ticket.toJson();

      expect(map['ticketID'], 'TKT-XYZ');
      expect(map['eventName'], 'Gala');
      expect(map['price'], 100.0);
    });
  });

  group('BlockModel Serialization', () {
    test('fromJson parses correctly with a valid ticket map', () {
      final json = {
        'index': 5,
        'ticket': {
          'ticketID': 'TKT-999',
          'eventName': 'Lake Festival',
        }
      };

      final block = BlockModel.fromJson(json);

      expect(block.index, 5);
      expect(block.storageIndex, 6); // Getter check
      expect(block.ticket.ticketID, 'TKT-999');
      expect(block.ticket.eventName, 'Lake Festival');
    });

    test('fromJson handles a completely missing or malformed ticket object',
        () {
      final json = {
        'index': 2,
        'ticket': 'This should be a map, not a string',
      };

      final block = BlockModel.fromJson(json);

      expect(block.index, 2);
      // It should instantiate an empty TicketModel rather than crashing
      expect(block.ticket.ticketID, '');
      expect(block.ticket.ticketType, 'General');
      expect(block.ticket.price, 0.0);
    });

    test('fromJson safely handles wrong types for the block index', () {
      final json = {
        'index': '3', // String instead of int
        'ticket': <String, dynamic>{},
      };

      final block = BlockModel.fromJson(json);
      expect(block.index, 3); // Handled by _parseInt
    });
  });

  group('BlockModel Computed Getters', () {
    test(
        'storageIndex correctly offsets the 0-based C++ index to a 1-based storage index',
        () {
      const genesisNext = BlockModel(
        index: 0,
        ticket: TicketModel(
          ticketID: '',
          eventName: '',
          eventDate: '',
          venue: '',
          ownerName: '',
          ownerID: '',
          ticketType: '',
          price: 0,
        ),
      );

      expect(genesisNext.storageIndex, 1);
    });
  });
}
