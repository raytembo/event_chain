// lib/features/auth/register_screen.dart
//
// Registration flow — schema v2 notes:
//
//   • The profiles row is auto-created by the handle_new_user() Postgres
//     trigger the moment auth.signUp() succeeds.  The trigger reads
//     raw_user_meta_data for 'full_name' and 'role', so those MUST be
//     passed in the signUp metadata (handled by AuthNotifier.register()).
//
//   • phone, bio, and avatar_url are NOT written by the trigger.
//     AuthNotifier.register() issues a follow-up profiles UPDATE for them
//     after signUp returns.
//
//   • profiles.role is a Postgres enum (public.user_role).
//     The only valid values are 'owner' and 'customer', which map exactly
//     to the Dart UserRole enum values via UserRole.name.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_model.dart';
import '../../shared/theme/app_theme.dart';
import 'auth_provider.dart';
import 'login_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _avatarUrlCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  UserRole _role = UserRole.customer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _avatarUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    // AuthNotifier.register() must:
    //   1. Call supabase.auth.signUp() with:
    //        data: {'full_name': displayName, 'role': role.name}
    //      → The handle_new_user trigger picks these up and creates profiles row.
    //   2. If phone/bio/avatarUrl are provided, issue a follow-up:
    //        supabase.from('profiles').update({...}).eq('id', user.id)
    //      because the trigger only writes id, email, display_name, role.
    final ok = await ref.read(authProvider.notifier).register(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          displayName: _nameCtrl.text.trim(),
          role: _role,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          avatarUrl: _avatarUrlCtrl.text.trim().isEmpty
              ? null
              : _avatarUrlCtrl.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account created! Please sign in.',
            style: AppTheme.sans(fontSize: 13),
          ),
          backgroundColor: AppTheme.authenticColor,
          duration: const Duration(seconds: 3),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      final err = ref.read(authProvider).error ?? 'Registration failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err, style: AppTheme.sans(fontSize: 13)),
          backgroundColor: AppTheme.tamperedColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryColor, size: 18),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
        ),
        title: Text(
          'CREATE ACCOUNT',
          style: AppTheme.merri(
              color: Colors.white, letterSpacing: 2, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Role ───────────────────────────────────────────────────────
              _sectionLabel('I AM A...'),
              const SizedBox(height: 12),
              _RoleSelector(
                selected: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
              const SizedBox(height: 28),

              // ── Account information ────────────────────────────────────────
              _sectionLabel('ACCOUNT INFORMATION'),
              const SizedBox(height: 16),

              _fieldLabel('DISPLAY NAME'),
              _field(
                _nameCtrl,
                'Full name',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              _fieldLabel('EMAIL'),
              _field(
                _emailCtrl,
                'you@example.com',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _fieldLabel('PASSWORD'),
              _passwordField(
                _passCtrl,
                'At least 8 characters',
                _obscurePass,
                () => setState(() => _obscurePass = !_obscurePass),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _fieldLabel('CONFIRM PASSWORD'),
              _passwordField(
                _confirmCtrl,
                'Repeat password',
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (v) =>
                    v != _passCtrl.text ? 'Passwords do not match' : null,
              ),

              const SizedBox(height: 32),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 24),

              // ── Optional profile information ───────────────────────────────
              // These fields are written to profiles via a follow-up UPDATE
              // after signUp, since the handle_new_user trigger only fills
              // id, email, display_name, and role.
              _sectionLabel('PROFILE INFORMATION (OPTIONAL)'),
              const SizedBox(height: 16),

              _fieldLabel('PHONE NUMBER'),
              _field(
                _phoneCtrl,
                '+265 999 123 456',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              _fieldLabel('BIO / ABOUT'),
              TextFormField(
                controller: _bioCtrl,
                maxLines: 3,
                maxLength: 500,
                style: AppTheme.sans(color: Colors.white),
                decoration:
                    _inputDec('Tell us a bit about yourself...').copyWith(
                  counterStyle:
                      AppTheme.sans(color: AppTheme.subTextColor, fontSize: 10),
                ),
              ),
              const SizedBox(height: 20),

              _fieldLabel('AVATAR URL'),
              _field(
                _avatarUrlCtrl,
                'https://example.com/avatar.jpg',
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'Enter a valid URL or leave blank';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 40),

              // ── Submit ─────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: auth.loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.authenticColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: auth.loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2.5),
                        )
                      : Text(
                          'CREATE ACCOUNT',
                          style: AppTheme.sans(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.subTextColor),
                      children: [
                        const TextSpan(text: 'Already have an account?  '),
                        TextSpan(
                          text: 'SIGN IN',
                          style: AppTheme.sans(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper builders ──────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppTheme.sans(
            color: AppTheme.primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppTheme.sans(
            color: AppTheme.subTextColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: AppTheme.sans(color: Colors.white),
        decoration: _inputDec(hint),
        validator: validator,
      );

  Widget _passwordField(
    TextEditingController ctrl,
    String hint,
    bool obscure,
    VoidCallback toggle, {
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        obscureText: obscure,
        style: AppTheme.sans(color: Colors.white),
        decoration: _inputDec(hint).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: AppTheme.subTextColor,
              size: 20,
            ),
            onPressed: toggle,
          ),
        ),
        validator: validator,
      );

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.sans(color: const Color(0xFF555555), fontSize: 13),
        filled: true,
        fillColor: AppTheme.cardMidColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.tamperedColor),
        ),
        errorStyle: AppTheme.sans(
          color: AppTheme.tamperedColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

// ── Role Selector ─────────────────────────────────────────────────────────────
class _RoleSelector extends StatelessWidget {
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _tile(
          role: UserRole.owner,
          icon: Icons.manage_accounts_outlined,
          label: 'EVENT OWNER',
          sub: 'Create & manage events',
        ),
        const SizedBox(width: 12),
        _tile(
          role: UserRole.customer,
          icon: Icons.person_outline,
          label: 'CUSTOMER',
          sub: 'Browse & buy tickets',
        ),
      ],
    );
  }

  Widget _tile({
    required UserRole role,
    required IconData icon,
    required String label,
    required String sub,
  }) {
    final isSelected = selected == role;
    const accent = AppTheme.primaryColor;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.12)
                : AppTheme.cardMidColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : AppTheme.dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? accent : AppTheme.subTextColor, size: 32),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.sans(
                  color: isSelected ? accent : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: AppTheme.sans(color: AppTheme.subTextColor, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
