// lib/features/customer/widgets/purchase_flow_sheet.dart
//
// 4-step purchase sheet:
//   Step 0 — Details form (Auto-filled from user profile)
//   Step 1 — Payment form (Cardholder name auto-filled)
//   Step 2 — Processing spinner
//   Step 3 — Success
//
// All ticket/payment DB writes, blockchain mining, and stego embedding are
// delegated to CustomerTicketService. This widget only owns the UI flow and
// card input collection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/utilities/currency_formatter.dart';
import '../../../shared/utilities/input_formatters.dart';
import '../services/customer_ticket_service.dart';
import 'shared_widgets.dart';

class PurchaseFlowSheet extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String eventDate;
  final String venue;
  final String ticketType;
  final String ticketTypeId;
  final double price;
  final int quantityAvailable;
  final String posterUrl; // ← needed by CustomerTicketService for stego embed

  const PurchaseFlowSheet({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.venue,
    required this.ticketType,
    required this.ticketTypeId,
    required this.price,
    required this.quantityAvailable,
    this.posterUrl = '', // optional: service falls back to synthetic cover
  });

  @override
  State<PurchaseFlowSheet> createState() => _PurchaseFlowSheetState();
}

class _PurchaseFlowSheetState extends State<PurchaseFlowSheet> {
  // ── State ──────────────────────────────────────────────────────────────────

  int _step = 0;
  bool _isProcessing = false;

  // Step 0 — details
  final _detailsFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  bool _detailsTried = false;

  // Step 1 — payment
  final _cardNumCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  // Step 3 — result
  String? _stegoPath;
  String? _errorMessage;

  static const _stepTitles = [
    'Your Details',
    'Payment',
    'Processing…',
    'Purchase Complete!',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _autoFillProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    _cardNumCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  // ── Auto-Fill ──────────────────────────────────────────────────────────────

  Future<void> _autoFillProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      if (user.email != null && user.email!.isNotEmpty) {
        _emailCtrl.text = user.email!;
      }

      final profile = await supabase
          .from('profiles')
          .select('display_name, phone')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          if (profile['display_name'] != null) {
            _nameCtrl.text = profile['display_name'] as String;
            _holderCtrl.text = profile['display_name'] as String;
          }
          if (profile['phone'] != null) {
            _phoneCtrl.text = profile['phone'] as String;
          }
        });
      }
    } catch (e) {
      debugPrint(
          'Silent warning: Failed to auto-fill purchase profile data: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _goToStep(int s) => setState(() => _step = s);

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTheme.sans()),
      backgroundColor:
          isError ? AppTheme.tamperedColor : AppTheme.authenticColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Step 0: validate + live availability check ─────────────────────────────

  Future<void> _submitDetails() async {
    setState(() => _detailsTried = true);
    if (!_detailsFormKey.currentState!.validate()) return;

    final res = await Supabase.instance.client
        .from('event_ticket_types')
        .select('quantity_available')
        .eq('id', widget.ticketTypeId)
        .maybeSingle();

    if (res == null || (res['quantity_available'] as int? ?? 0) <= 0) {
      _showSnack('Sorry, this ticket type just sold out.');
      return;
    }

    _goToStep(1);
  }

  // ── Step 1: validate card fields ───────────────────────────────────────────

  bool _validateCard() {
    final clean = _cardNumCtrl.text.replaceAll(' ', '');
    if (clean.length < 13 ||
        _expiryCtrl.text.length < 5 ||
        _cvvCtrl.text.length < 3 ||
        _holderCtrl.text.trim().isEmpty) {
      _showSnack('Please fill in all card details.');
      return false;
    }
    return true;
  }

  // ── Step 1 → 2 → 3: process payment ───────────────────────────────────────
  //
  // All heavy lifting (blockchain sync, block mining, stego embed, Storage
  // uploads, DB inserts) is handled by CustomerTicketService. This method
  // only drives the UI step transitions and surfaces errors.

  Future<void> _processPayment() async {
    if (_isProcessing) return;
    if (!_validateCard()) return;

    setState(() => _isProcessing = true);
    _goToStep(2);

    try {
      final result = await CustomerTicketService.instance.purchaseTicket(
        eventId: widget.eventId,
        eventName: widget.eventName,
        posterUrl: widget.posterUrl,
        eventDate: widget.eventDate,
        venue: widget.venue,
        ticketType: widget.ticketType,
        price: widget.price,
      );

      if (!result.success) {
        throw Exception(result.error ?? 'Purchase failed. Please try again.');
      }

      _stegoPath = result.stegoLocalPath;
      _goToStep(3);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = msg;
        _step = 1;
      });
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  Future<void> _shareTicket() async {
    if (_stegoPath == null) return;
    await Share.shareXFiles(
      [XFile(_stegoPath!)],
      subject: 'My ticket for ${widget.eventName}',
      text: 'Ticket for ${widget.eventName} on ${widget.eventDate}\n'
          'Type: ${widget.ticketType} · Holder: ${_nameCtrl.text}',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          SheetHeader(
            stepLabel: _step < 2 ? 'Step ${_step + 1} of 2' : '',
            title: _stepTitles[_step],
            onCancel: _step == 3 ? null : () => Navigator.pop(context),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildDetailsStep();
      case 1:
        return _buildPaymentStep();
      case 2:
        return _buildProcessingStep();
      case 3:
        return _buildSuccessStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0 — Details ───────────────────────────────────────────────────────

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _detailsFormKey,
        autovalidateMode: _detailsTried
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TicketSummaryBadge(
              type: widget.ticketType,
              price: widget.price,
              eventName: widget.eventName,
            ),
            const SizedBox(height: 24),
            AppFormField(
              controller: _nameCtrl,
              label: 'Full Name',
              hint: 'Your full name',
              icon: Icons.person_outline_rounded,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Name is required';
                if (v.trim().length < 2) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppFormField(
              controller: _emailCtrl,
              label: 'Email Address',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
              type: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppFormField(
              controller: _phoneCtrl,
              label: 'Phone Number',
              hint: '+265 99 123 4567',
              icon: Icons.phone_outlined,
              type: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Phone number is required';
                }
                if (v.trim().length < 7) return 'Enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppFormField(
              controller: _idCtrl,
              label: 'National ID / Passport',
              hint: 'e.g. 10/NRB/987654/01',
              icon: Icons.badge_outlined,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'ID / Passport number is required';
                }
                if (v.trim().length < 5) return 'ID number is too short';
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text(
              'These details will be embedded in your ticket for identity verification at the venue.',
              style: AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Continue to Payment',
              onTap: _submitDetails,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1 — Payment ───────────────────────────────────────────────────────

  Widget _buildPaymentStep() {
    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderSummary(
            name: _nameCtrl.text,
            type: widget.ticketType,
            price: widget.price,
            eventName: widget.eventName,
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) ...[
            ErrorBanner(message: _errorMessage!),
            const SizedBox(height: 16),
          ],
          CardPreview(
            number: _cardNumCtrl.text,
            holder: _holderCtrl.text,
            expiry: _expiryCtrl.text,
          ),
          const SizedBox(height: 20),
          CardInput(
            label: 'Card Number',
            controller: _cardNumCtrl,
            icon: Icons.credit_card_rounded,
            type: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              CardNumberFormatter(),
            ],
            maxLength: 19,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CardInput(
                  label: 'Expiry Date',
                  controller: _expiryCtrl,
                  icon: Icons.calendar_today_outlined,
                  type: TextInputType.number,
                  formatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    ExpiryFormatter(),
                  ],
                  maxLength: 5,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: CardInput(
                  label: 'CVV',
                  controller: _cvvCtrl,
                  icon: Icons.lock_outline_rounded,
                  type: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  obscure: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CardInput(
            label: 'Cardholder Name',
            controller: _holderCtrl,
            icon: Icons.person_outline_rounded,
            type: TextInputType.name,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: _isProcessing
                ? 'Processing…'
                : 'Pay MK ${formatMwk(widget.price)}',
            onTap: _isProcessing ? () {} : _processPayment,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _isProcessing ? null : () => _goToStep(0),
              child: Text(
                '← Back to Details',
                style:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2 — Processing ────────────────────────────────────────────────────

  Widget _buildProcessingStep() => Center(
        key: const ValueKey(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primaryColor, strokeWidth: 2.5),
            const SizedBox(height: 28),
            Text('Processing payment…', style: AppTheme.merri(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              'Please do not close this screen.',
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
            ),
          ],
        ),
      );

  // ── Step 3 — Success ───────────────────────────────────────────────────────

  Widget _buildSuccessStep() {
    return SingleChildScrollView(
      key: const ValueKey(3),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const SuccessIcon(),
          const SizedBox(height: 20),
          Text(
            'Payment Successful!',
            style: AppTheme.merri(fontSize: 24, color: AppTheme.authenticColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ticket has been issued.',
            style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
          ),
          const SizedBox(height: 28),
          TicketDetailCard(
            eventName: widget.eventName,
            ticketType: widget.ticketType,
            eventDate: widget.eventDate,
            venue: widget.venue,
            buyerName: _nameCtrl.text,
            price: widget.price,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Close', style: AppTheme.sans(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareTicket,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    'Share',
                    style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
