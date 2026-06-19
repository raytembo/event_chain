// lib/features/owner/manage_verifiers_screen.dart

import 'dart:io';

import 'package:eventchain/features/owner/gate_verifier_patch.dart'
    show gateVerifiersProvider, ownerEventOptionsProvider;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_theme.dart';

class ManageVerifiersScreen extends ConsumerStatefulWidget {
  const ManageVerifiersScreen({super.key});

  @override
  ConsumerState<ManageVerifiersScreen> createState() =>
      _ManageVerifiersScreenState();
}

class _ManageVerifiersScreenState extends ConsumerState<ManageVerifiersScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;

  // Local state for picked avatar file and the upload-then-invite phase.
  File? _avatarFile;
  bool _localSubmitting = false;

  // null = "All Events". Holds an event id once a specific event is chosen.
  String? _selectedEventId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _avatarFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error picking image: $e', color: AppTheme.tamperedColor);
    }
  }

  Future<void> _inviteVerifier() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _localSubmitting = true);

    String? avatarUrl;
    if (_avatarFile != null) {
      try {
        final supabase = Supabase.instance.client;
        final fileExt = _avatarFile!.path.split('.').last;
        final fileName =
            'avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await supabase.storage.from('avatars').upload(fileName, _avatarFile!);
        avatarUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      } catch (e) {
        setState(() => _localSubmitting = false);
        if (!mounted) return;
        _showSnack('Avatar upload failed: $e', color: AppTheme.tamperedColor);
        return;
      }
    }

    final ok = await ref.read(gateVerifiersProvider.notifier).invite(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          avatarUrl: avatarUrl,
          eventId: _selectedEventId,
        );

    if (!mounted) return;
    setState(() => _localSubmitting = false);

    if (ok) {
      _showSnack('Verifier account authorized for ${_emailCtrl.text.trim()}.');
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passwordCtrl.clear();
      _confirmCtrl.clear();
      _phoneCtrl.clear();
      _bioCtrl.clear();
      setState(() => _avatarFile = null);
      FocusScope.of(context).unfocus();
    } else {
      final error = ref.read(gateVerifiersProvider).error ??
          'Could not send the invite. Please try again.';
      _showSnack(error, color: AppTheme.tamperedColor);
    }
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gateVerifiersProvider);
    final eventOptionsAsync = ref.watch(ownerEventOptionsProvider);
    final isSubmitting = state.submitting || _localSubmitting;

    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'MANAGE VERIFIERS',
          style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(gateVerifiersProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Authorize Gate Personnel',
              style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a full verifier account on their behalf — name, login credentials, and (optionally) a photo and contact details — then assign them to an event. They will receive access to the Gate Terminal.',
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 24),

            // Invite Form Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    _fieldLabel('VERIFIER EMAIL'),
                    _field(
                      _emailCtrl,
                      'staff@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _fieldLabel('INITIAL ACCESS PASSWORD'),
                    _passwordField(
                      _passwordCtrl,
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
                      validator: (v) => v != _passwordCtrl.text
                          ? 'Passwords do not match'
                          : null,
                    ),

                    const SizedBox(height: 28),
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),

                    _sectionLabel('PROFILE INFORMATION (OPTIONAL)'),
                    const SizedBox(height: 16),

                    _fieldLabel('AVATAR PROFILE IMAGE'),
                    const SizedBox(height: 8),
                    _buildAvatarPicker(),
                    const SizedBox(height: 24),

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
                        counterStyle: AppTheme.sans(
                            color: AppTheme.subTextColor, fontSize: 10),
                      ),
                    ),

                    const SizedBox(height: 28),
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),

                    Text(
                      'ASSIGNMENT SCOPE',
                      style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),

                    // Event Selection Dropdown (live data)
                    eventOptionsAsync.when(
                      loading: () => Container(
                        height: 48,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.cardMidColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, _) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.cardMidColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        child: Text(
                          'Could not load events.',
                          style: AppTheme.sans(
                              fontSize: 13, color: AppTheme.subTextColor),
                        ),
                      ),
                      data: (events) {
                        final validIds =
                            events.map((e) => e['id'] as String).toSet();
                        if (_selectedEventId != null &&
                            !validIds.contains(_selectedEventId)) {
                          _selectedEventId = null;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.cardMidColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _selectedEventId,
                              isExpanded: true,
                              dropdownColor: AppTheme.cardColor,
                              style: AppTheme.sans(
                                  fontSize: 14, color: Colors.white),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Events'),
                                ),
                                ...events.map(
                                  (e) => DropdownMenuItem<String?>(
                                    value: e['id'] as String,
                                    child: Text(
                                      e['event_name'] as String,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => _selectedEventId = val),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : _inviteVerifier,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('AUTHORIZE VERIFIER'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            Text(
              'Active Personnel',
              style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            if (state.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.verifiers.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardMidColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'No verifiers yet. Invite gate staff above to get started.',
                  style:
                      AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                ),
              )
            else
              for (final v in state.verifiers)
                _buildVerifierCard(
                  id: v['id'] as String,
                  email: v['verifier_email'] as String,
                  event: (v['events'] as Map<String, dynamic>?)?['event_name']
                          as String? ??
                      'All Events',
                  status: v['status'] as String,
                ),
          ],
        ),
      ),
    );
  }

  // ── Native File Selection Sub-Widget ────────────────────────────────────────

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.cardMidColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _avatarFile != null
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                      width: 2,
                    ),
                    image: _avatarFile != null
                        ? DecorationImage(
                            image: FileImage(_avatarFile!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _avatarFile == null
                      ? const Icon(
                          Icons.person_add_alt_1_outlined,
                          color: AppTheme.subTextColor,
                          size: 32,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.black,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_avatarFile != null) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _avatarFile = null),
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: AppTheme.tamperedColor),
              label: Text(
                'Remove Photo',
                style: AppTheme.sans(
                    color: AppTheme.tamperedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
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

  Widget _buildVerifierCard({
    required String id,
    required String email,
    required String event,
    required String status,
  }) {
    final isActive = status == 'active';
    final isRevoked = status == 'revoked';
    final statusLabel = status[0].toUpperCase() + status.substring(1);

    final statusColor = isActive
        ? AppTheme.primaryColor
        : isRevoked
            ? AppTheme.tamperedColor
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withAlpha((0.1 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive
                  ? Icons.qr_code_scanner_rounded
                  : isRevoked
                      ? Icons.block_rounded
                      : Icons.pending_actions_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: AppTheme.sans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Assigned to: $event  ·  $statusLabel',
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.subTextColor)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: AppTheme.subTextColor),
            color: AppTheme.cardColor,
            onSelected: (action) async {
              final notifier = ref.read(gateVerifiersProvider.notifier);
              switch (action) {
                case 'revoke':
                  await notifier.revoke(id);
                  if (!mounted) return;
                  _showSnack('Revoked access for $email');
                  break;
                case 'reactivate':
                  await notifier.reactivate(id);
                  if (!mounted) return;
                  _showSnack('Reauthorized $email');
                  break;
                case 'remove':
                  await notifier.remove(id);
                  if (!mounted) return;
                  _showSnack('Removed $email');
                  break;
              }
            },
            itemBuilder: (context) => [
              if (isActive)
                const PopupMenuItem(
                  value: 'revoke',
                  child: Text('Revoke access'),
                ),
              if (!isActive)
                const PopupMenuItem(
                  value: 'reactivate',
                  child: Text('Reauthorize'),
                ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
