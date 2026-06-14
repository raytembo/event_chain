// test/core/models/user_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:eventchain/core/models/user_model.dart';

void main() {
  final ownerMap = <String, dynamic>{
    'id': 'usr-1',
    'email': 'owner@example.com',
    'display_name': 'Raymond Tembo',
    'role': 'owner',
    'phone': '+265888000000',
    'avatar_url': 'https://example.com/avatar.png',
    'bio': 'Event organiser based in Blantyre',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-06-01T00:00:00.000Z',
  };

  group('AppUser.fromMap Core Parsing', () {
    test('parses an owner profile with all fields populated', () {
      final user = AppUser.fromMap(ownerMap);

      expect(user.id, 'usr-1');
      expect(user.email, 'owner@example.com');
      expect(user.displayName, 'Raymond Tembo');
      expect(user.role, UserRole.owner);
      expect(user.phone, '+265888000000');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
      expect(user.bio, 'Event organiser based in Blantyre');
      expect(user.createdAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
      expect(user.updatedAt, DateTime.parse('2026-06-01T00:00:00.000Z'));
    });

    test('role "customer" maps to UserRole.customer', () {
      final user = AppUser.fromMap({...ownerMap, 'role': 'customer'});
      expect(user.role, UserRole.customer);
    });

    test('any role other than "owner" maps to UserRole.customer', () {
      final user = AppUser.fromMap({...ownerMap, 'role': 'admin'});
      expect(user.role, UserRole.customer);
    });
  });

  group('AppUser Parsing Edge Cases & Robustness', () {
    test('optional fields default to null when absent from the map', () {
      final minimalMap = <String, dynamic>{
        'id': 'usr-2',
        'email': 'fan@example.com',
        'display_name': 'Jane Doe',
        'role': 'customer',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      };

      final user = AppUser.fromMap(minimalMap);
      expect(user.phone, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.bio, isNull);
    });

    test(
        'handles completely null values in unexpected optional fields gracefully',
        () {
      final mapWithNulls = Map<String, dynamic>.from(ownerMap)
        ..['phone'] = null
        ..['avatar_url'] = null
        ..['bio'] = null;

      final user = AppUser.fromMap(mapWithNulls);
      expect(user.phone, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.bio, isNull);
    });

    test(
        'falls back safely when key identifiers or strings are completely missing',
        () {
      final brokenMap = <String, dynamic>{};
      final user = AppUser.fromMap(brokenMap);

      expect(user.id, '');
      expect(user.email, '');
      expect(user.displayName, '');
      expect(user.role, UserRole.customer);
      expect(user.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('AppUser.toMap Serialization', () {
    test(
        'serialises all fields, including nullable ones, using db column names',
        () {
      final user = AppUser(
        id: 'usr-1',
        email: 'owner@example.com',
        displayName: 'Raymond Tembo',
        role: UserRole.owner,
        phone: '+265888000000',
        avatarUrl: 'https://example.com/avatar.png',
        bio: 'Event organiser',
        createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2026-06-01T00:00:00.000Z'),
      );

      final map = user.toMap();

      expect(map['id'], 'usr-1');
      expect(map['email'], 'owner@example.com');
      expect(map['display_name'], 'Raymond Tembo');
      expect(map['role'], 'owner');
      expect(map['phone'], '+265888000000');
      expect(map['avatar_url'], 'https://example.com/avatar.png');
      expect(map['bio'], 'Event organiser');
      expect(map['created_at'], '2026-01-01T00:00:00.000Z');
      expect(map['updated_at'], '2026-06-01T00:00:00.000Z');
    });

    test('round-trips through fromMap without losing structural fidelity', () {
      final original = AppUser(
        id: 'usr-3',
        email: 'round@example.com',
        displayName: 'Round Tripper',
        role: UserRole.customer,
        createdAt: DateTime.parse('2026-02-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2026-02-02T00:00:00.000Z'),
      );

      final restored = AppUser.fromMap(original.toMap());
      expect(restored, equals(original));
    });
  });
}
