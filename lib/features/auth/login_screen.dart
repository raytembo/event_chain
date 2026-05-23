// lib/features/auth/login_screen.dart
//
// Fix notes (spinner loop):
//
//   • _login() no longer calls Navigator.  The _AuthRouter in main.dart watches
//     authProvider and automatically swaps to the correct root scaffold the
//     moment AuthNotifier.login() sets user to non-null.
//
//   • Removing the Navigator call also fixes the `if (!mounted) return` bail-
//     out that previously prevented navigation: when _AuthRouter is the parent,
//     LoginScreen is unmounted as soon as loading becomes true, so any
//     Navigator call inside _login() was silently discarded.
//
//   • All UI is unchanged from the original.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import 'auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref.read(authProvider.notifier).login(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );

    // _AuthRouter handles navigation automatically when user becomes non-null.
    // We only need to handle the failure case here.
    if (!ok && mounted) {
      final err = ref.read(authProvider).error ?? 'Login failed';
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Animated Logo ──────────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Opacity(
                  opacity: _pulseAnim.value,
                  child: child,
                ),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  ),
                  child: const Icon(
                    Icons.link,
                    color: AppTheme.primaryColor,
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'EVENTCHAIN',
                style: AppTheme.merri(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 6,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Blockchain-secured ticketing system',
                style: AppTheme.sans(
                  color: AppTheme.subTextColor,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 48),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Email ────────────────────────────────────────────────
                    _fieldLabel('EMAIL'),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: AppTheme.sans(color: Colors.white),
                      decoration: _inputDec('you@example.com'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── Password ─────────────────────────────────────────────
                    _fieldLabel('PASSWORD'),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: AppTheme.sans(color: Colors.white),
                      decoration: _inputDec('••••••••').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.subTextColor,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),

                    const SizedBox(height: 36),

                    // ── Sign-in button ───────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: auth.loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: auth.loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'SIGN IN',
                                style: AppTheme.sans(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Divider ──────────────────────────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: AppTheme.dividerColor),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: AppTheme.sans(
                              color: AppTheme.subTextColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: AppTheme.dividerColor),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Register link ────────────────────────────────────────
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: AppTheme.sans(
                              fontSize: 13,
                              color: AppTheme.subTextColor,
                            ),
                            children: [
                              const TextSpan(text: "Don't have an account?  "),
                              TextSpan(
                                text: 'REGISTER',
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
                  ],
                ),
              ),

              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Steganography · Blockchain · Secure Tickets',
                  style: AppTheme.sans(
                    color: Colors.white12,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppTheme.sans(
            color: AppTheme.primaryColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
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
