// lib/core/models/user_model.dart

enum UserRole { owner, customer }

class AppUser {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? phone; // ← was silently discarded before
  final String? avatarUrl; // ← was silently discarded before
  final String? bio; // ← was silently discarded before
  final DateTime createdAt;
  final DateTime updatedAt; // ← new

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.avatarUrl,
    this.bio,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        email: map['email'] as String,
        displayName: map['display_name'] as String,
        role: (map['role'] as String) == 'owner'
            ? UserRole.owner
            : UserRole.customer,
        phone: map['phone'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        bio: map['bio'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'role': role.name,
        'phone': phone,
        'avatar_url': avatarUrl,
        'bio': bio,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
