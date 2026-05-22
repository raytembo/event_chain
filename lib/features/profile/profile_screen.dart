// lib/features/profile/profile_screen.dart
//
// FIXED: All compilation errors
// • backgroundImage now uses explicit if-else (no ternary inference issue)
// • Removed invalid 'const' from SnackBar constructors that use $e
// • Avatar preview, upload, and form work perfectly

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _email;
  String? _role;
  String? _avatarUrl;
  File? _newAvatarFile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('display_name, email, role, phone, bio, avatar_url')
          .eq('id', userId)
          .single();

      setState(() {
        _displayNameCtrl.text = profile['display_name'] ?? '';
        _phoneCtrl.text = profile['phone'] ?? '';
        _bioCtrl.text = profile['bio'] ?? '';
        _email = profile['email'];
        _role = profile['role'];
        _avatarUrl = profile['avatar_url'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load profile: $e'),
            backgroundColor: AppTheme.tamperedColor,
          ),
        );
      }
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked != null) {
      setState(() => _newAvatarFile = File(picked.path));
    }
  }

  Future<String?> _uploadAvatar() async {
    if (_newAvatarFile == null) return _avatarUrl;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final fileName = '$userId-avatar.jpg';
      final uploadPath = 'avatars/$fileName';

      await supabase.storage.from('avatars').upload(
        uploadPath,
        _newAvatarFile!,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(uploadPath);
      return publicUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Avatar upload failed: $e'),
            backgroundColor: AppTheme.tamperedColor,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    try {
      final newAvatarUrl = await _uploadAvatar();

      await supabase.from('profiles').update({
        'display_name': _displayNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'bio': _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId!);

      if (mounted) {
        setState(() {
          if (newAvatarUrl != null) _avatarUrl = newAvatarUrl;
          _newAvatarFile = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: AppTheme.tamperedColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text('Profile', style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    // ── Explicit ImageProvider to fix type error ─────────────────────
    ImageProvider<Object>? backgroundImage;
    if (_newAvatarFile != null) {
      backgroundImage = FileImage(_newAvatarFile!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_avatarUrl!);
    }

    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'PROFILE',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar Section ─────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 62,
                        backgroundColor: AppTheme.cardMidColor,
                        backgroundImage: backgroundImage,
                        child: backgroundImage == null
                            ? const Icon(Icons.person_rounded, size: 72, color: AppTheme.primaryColor)
                            : null,
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.cardColor, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Tap to change photo',
                  style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                ),
              ),

              const SizedBox(height: 40),

              // ── Form Fields ───────────────────────────────────────
              const _Label('Display Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _displayNameCtrl,
                style: AppTheme.sans(),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Enter your full name',
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Display name is required';
                  if (v.trim().length < 2) return 'Name must be at least 2 characters';
                  return null;
                },
              ),

              const SizedBox(height: 24),

              const _Label('Phone Number'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneCtrl,
                style: AppTheme.sans(),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+265 999 123 456',
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const _Label('Bio (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bioCtrl,
                style: AppTheme.sans(),
                maxLines: 4,
                maxLength: 280,
                decoration: InputDecoration(
                  hintText: 'Tell us a bit about yourself...',
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Read-only fields ───────────────────────────────────
              const _Label('Email Address'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _email ?? '—',
                  style: AppTheme.sans(fontSize: 15, color: Colors.white70),
                ),
              ),

              const SizedBox(height: 24),

              const _Label('Account Role'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (_role ?? 'customer').toUpperCase(),
                  style: AppTheme.sans(fontSize: 15, color: AppTheme.primaryColor),
                ),
              ),

              const SizedBox(height: 48),

              // ── Save Button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                  )
                      : Text(
                    'SAVE CHANGES',
                    style: AppTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper label ─────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.sans(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.subTextColor,
    ),
  );
}