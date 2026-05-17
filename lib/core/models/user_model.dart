// lib/core/models/user_model.dart
//
// Plain Dart model mirroring the Supabase `profiles` table.
// No Isar annotations — password hashing is handled by Supabase Auth.

enum UserRole { owner, customer }

class AppUser {
  final String id;          // uuid from auth.users
  final String email;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt, String? phone, String? bio, String? avatarUrl,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
    id:          map['id']           as String,
    email:       map['email']        as String,
    displayName: map['display_name'] as String,
    role:        (map['role'] as String) == 'owner'
        ? UserRole.owner
        : UserRole.customer,
    createdAt:   DateTime.parse(map['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id':           id,
    'email':        email,
    'display_name': displayName,
    'role':         role == UserRole.owner ? 'owner' : 'customer',
    'created_at':   createdAt.toIso8601String(),
  };
}