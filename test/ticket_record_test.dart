// Unit tests for TicketRecord and TicketType (lib/core/models/ticket_record.dart).
//
// Pure Dart — exercises Supabase row -> model mapping without a network call.

import 'package:flutter_test/flutter_test.dart';
import 'package:eventchain/core/models/ticket_record.dart';

void main() {
  group('TicketTypeX', () {
    test('dbValue matches the Postgres enum exactly', () {
      expect(TicketType.general.dbValue, 'General');
      expect(TicketType.vip.dbValue, 'VIP');
      expect(TicketType.backstage.dbValue, 'Backstage');
      expect(TicketType.student.dbValue, 'Student');
    });

    test('fromString maps known database strings back to enum members', () {
      expect(TicketTypeX.fromString('VIP'), TicketType.vip);
      expect(TicketTypeX.fromString('Backstage'), TicketType.backstage);
      expect(TicketTypeX.fromString('Student'), TicketType.student);
      expect(TicketTypeX.fromString('General'), TicketType.general);
    });

    test('fromString defaults unknown or empty strings to general', () {
      expect(
          TicketTypeX.fromString('something-unexpected'), TicketType.general);
      expect(TicketTypeX.fromString(''), TicketType.general);
    });

    test('dbValue and fromString round-trip for every enum value', () {
      for (final type in TicketType.values) {
        expect(TicketTypeX.fromString(type.dbValue), type);
      }
    });
  });

  // A row as returned by a plain `select * from tickets` query — the joined
  // event_* / poster_url / event_owner_id fields are absent.
  final ticketsTableRow = <String, dynamic>{
    'id': 'a1b2c3',
    'ticket_id': 'TKT-001',
    'block_index': 2,
    'stego_url': 'https://storage/.../ticket_3.png',
    'event_id': 'evt-1',
    'owner_id': 'usr-1',
    'owner_name': 'Raymond Tembo',
    'ticket_type': 'VIP',
    'price': 25000,
    'is_sold': false,
    'sold_to': null,
    'sold_at': null,
    'buyer_email': null,
    'buyer_phone': null,
    'deleted_at': null,
    'created_at': '2026-06-01T10:00:00.000Z',
    'updated_at': '2026-06-01T10:00:00.000Z',
  };

  group('TicketRecord.fromMap', () {
    test('parses a row from the bare tickets table', () {
      final record = TicketRecord.fromMap(ticketsTableRow);

      expect(record.id, 'a1b2c3');
      expect(record.ticketId, 'TKT-001');
      expect(record.blockIndex, 2);
      expect(record.stegoUrl, 'https://storage/.../ticket_3.png');
      expect(record.eventId, 'evt-1');
      expect(record.ownerId, 'usr-1');
      expect(record.ownerName, 'Raymond Tembo');
      expect(record.ticketType, TicketType.vip);
      expect(record.price, 25000.0);
      expect(record.isSold, isFalse);
      expect(record.soldTo, isNull);
      expect(record.soldAt, isNull);
      expect(record.deletedAt, isNull);
      expect(record.createdAt, DateTime.parse('2026-06-01T10:00:00.000Z'));

      // Joined fields are absent on the bare table.
      expect(record.eventName, isNull);
      expect(record.venue, isNull);
      expect(record.eventDate, isNull);
      expect(record.posterUrl, isNull);
      expect(record.eventOwnerId, isNull);
    });

    test('parses a fully joined row from v_ticket_detail', () {
      final viewRow = {
        ...ticketsTableRow,
        'is_sold': true,
        'sold_to': 'usr-2',
        'sold_at': '2026-06-05T12:00:00.000Z',
        'buyer_email': 'buyer@example.com',
        'buyer_phone': '+265888000000',
        'event_name': 'Lake of Stars',
        'venue': 'Mangochi Lakeshore',
        'event_date': '2026-09-12T18:00:00.000Z',
        'poster_url': 'https://storage/.../poster.jpg',
        'event_owner_id': 'usr-owner',
      };

      final record = TicketRecord.fromMap(viewRow);

      expect(record.isSold, isTrue);
      expect(record.soldTo, 'usr-2');
      expect(record.soldAt, DateTime.parse('2026-06-05T12:00:00.000Z'));
      expect(record.buyerEmail, 'buyer@example.com');
      expect(record.buyerPhone, '+265888000000');
      expect(record.eventName, 'Lake of Stars');
      expect(record.venue, 'Mangochi Lakeshore');
      expect(record.eventDate, DateTime.parse('2026-09-12T18:00:00.000Z'));
      expect(record.posterUrl, 'https://storage/.../poster.jpg');
      expect(record.eventOwnerId, 'usr-owner');
    });

    test('parses a soft-deleted row', () {
      final deletedRow = {
        ...ticketsTableRow,
        'deleted_at': '2026-06-10T09:30:00.000Z',
      };

      final record = TicketRecord.fromMap(deletedRow);

      expect(record.deletedAt, DateTime.parse('2026-06-10T09:30:00.000Z'));
      expect(record.isActive, isFalse);
    });
  });

  group('TicketRecord computed getters', () {
    test('storageIndex is blockIndex + 1 (genesis block offset)', () {
      final firstReal =
          TicketRecord.fromMap({...ticketsTableRow, 'block_index': 0});
      expect(firstReal.storageIndex, 1);

      final laterTicket =
          TicketRecord.fromMap({...ticketsTableRow, 'block_index': 4});
      expect(laterTicket.storageIndex, 5);
    });

    test('isActive is true only when deletedAt is null', () {
      final active = TicketRecord.fromMap(ticketsTableRow);
      expect(active.isActive, isTrue);

      final inactive = TicketRecord.fromMap(
        {...ticketsTableRow, 'deleted_at': '2026-06-12T00:00:00.000Z'},
      );
      expect(inactive.isActive, isFalse);
    });
  });

  group('TicketRecord.toFFIModel', () {
    test('maps joined event fields and ownership into a TicketModel', () {
      final viewRow = {
        ...ticketsTableRow,
        'block_index': 6,
        'ticket_id': 'TKT-007',
        'ticket_type': 'Backstage',
        'price': 50000,
        'event_name': 'Lake of Stars',
        'venue': 'Mangochi Lakeshore',
        'event_date': '2026-09-12T18:00:00.000Z',
        'poster_url': null,
        'event_owner_id': 'usr-owner',
      };

      final ffi = TicketRecord.fromMap(viewRow).toFFIModel();

      expect(ffi.ticketID, 'TKT-007');
      expect(ffi.eventName, 'Lake of Stars');
      expect(ffi.venue, 'Mangochi Lakeshore');
      expect(ffi.eventDate,
          DateTime.parse('2026-09-12T18:00:00.000Z').toIso8601String());
      expect(ffi.ownerName, 'Raymond Tembo');
      expect(ffi.ownerID, 'usr-1');
      expect(ffi.ticketType, 'Backstage');
      expect(ffi.price, 50000.0);
    });

    test('falls back to empty strings when event fields are not joined', () {
      final ffi = TicketRecord.fromMap(ticketsTableRow).toFFIModel();

      expect(ffi.eventName, '');
      expect(ffi.eventDate, '');
      expect(ffi.venue, '');
    });
  });
}
