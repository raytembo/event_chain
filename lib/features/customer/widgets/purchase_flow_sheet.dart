// lib/features/customer/widgets/purchase_flow_sheet.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/utilities/currency_formatter.dart';
import '../../../shared/utilities/input_formatters.dart';
import '../providers/event_providers_customer.dart';
import '../services/customer_ticket_service.dart';
import 'shared_widgets.dart';

class PurchaseFlowSheet extends ConsumerStatefulWidget {
  final String eventId;
  final String eventName;
  final String eventDate;
  final String venue;
  final String ticketType;
  final String ticketTypeId;
  final double price;
  final int quantityAvailable;
  final String posterUrl;

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
    this.posterUrl = '',
  });

  @override
  ConsumerState<PurchaseFlowSheet> createState() => _PurchaseFlowSheetState();
}

class _PurchaseFlowSheetState extends ConsumerState<PurchaseFlowSheet> {
  int _step = 0;
  bool _isProcessing = false;

  final _detailsFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // ── FIX: Split into two separate controllers ──────────────────────────────
  // _contactPhoneCtrl  → Step 0 "Your Details" contact number (stored on
  //                       the ticket row as buyer_phone).
  // _paymentPhoneCtrl  → Step 1 "Payment" mobile-money wallet number
  //                       (validated for 08/09 prefix, shown on the wallet
  //                       preview card, never written as buyer_phone).
  final _contactPhoneCtrl = TextEditingController();
  final _paymentPhoneCtrl = TextEditingController();

  final _idCtrl = TextEditingController();
  bool _detailsTried = false;

  // Payment configuration tracking
  String _paymentMethod =
      'Card'; // Options: 'Card', 'TNM Mpamba', 'Airtel Money'

  final _cardNumCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  String? _stegoPath;
  String? _errorMessage;

  static const _stepTitles = [
    'Your Details',
    'Payment',
    'Processing…',
    'Purchase Complete!',
  ];

  @override
  void initState() {
    super.initState();
    _autoFillProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _contactPhoneCtrl.dispose(); // FIX: dispose both controllers
    _paymentPhoneCtrl.dispose();
    _idCtrl.dispose();
    _cardNumCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  String _generateFakeNationalId() {
    final random = Random();
    final districts = ['LL', 'BT', 'ZA', 'MZ', 'NRB', 'SA', 'KU', 'KA'];
    final district = districts[random.nextInt(districts.length)];
    final regNo = List.generate(6, (_) => random.nextInt(10).toString()).join();
    final checkDigit =
        List.generate(2, (_) => random.nextInt(10).toString()).join();
    return '10/$district/$regNo/$checkDigit';
  }

  Future<void> _saveLocalPaymentAndIdData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_national_id', _idCtrl.text.trim());
      // FIX: cache card data only — payment phone is not persisted because
      // mobile-money numbers come from the user's profile on every load.
      await prefs.setString('cached_card_number', _cardNumCtrl.text.trim());
      await prefs.setString('cached_card_expiry', _expiryCtrl.text.trim());
      await prefs.setString('cached_card_holder', _holderCtrl.text.trim());
    } catch (e, stackTrace) {
      debugPrint('Error saving local payment preferences: $e\n$stackTrace');
    }
  }

  Future<void> _autoFillProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      // ── Step 1: populate from Supabase profile ──────────────────────────
      String? profilePhone;
      if (user != null) {
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
              String rawPhone = profile['phone'] as String;
              rawPhone = rawPhone.replaceAll(' ', '').trim();

              if (rawPhone.startsWith('+265')) {
                rawPhone = rawPhone.substring(4);
              } else if (rawPhone.startsWith('265')) {
                rawPhone = rawPhone.substring(3);
              }
              if (!rawPhone.startsWith('0') &&
                  (rawPhone.startsWith('8') || rawPhone.startsWith('9'))) {
                rawPhone = '0$rawPhone';
              }

              // FIX: profile phone populates BOTH fields — contact number
              // for Step 0 and the mobile-money wallet number for Step 1.
              _contactPhoneCtrl.text = rawPhone;
              _paymentPhoneCtrl.text = rawPhone;
              profilePhone = rawPhone;

              // FIX: derive default payment method from the profile phone
              // prefix. This is only a default — user can still switch tabs.
              if (rawPhone.startsWith('08')) {
                _paymentMethod = 'TNM Mpamba';
              } else if (rawPhone.startsWith('09')) {
                _paymentMethod = 'Airtel Money';
              }
            }
          });
        }
      }

      // ── Step 2: overlay cached preferences ─────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('cached_national_id');
      final savedCardNum = prefs.getString('cached_card_number');
      final savedExpiry = prefs.getString('cached_card_expiry');
      final savedHolder = prefs.getString('cached_card_holder');

      if (mounted) {
        setState(() {
          _idCtrl.text = (savedId != null && savedId.isNotEmpty)
              ? savedId
              : _generateFakeNationalId();

          if (savedExpiry != null && savedExpiry.isNotEmpty) {
            _expiryCtrl.text = savedExpiry;
          }
          if (savedHolder != null && savedHolder.isNotEmpty) {
            _holderCtrl.text = savedHolder;
          }

          if (savedCardNum != null && savedCardNum.isNotEmpty) {
            _cardNumCtrl.text = savedCardNum;
            // FIX: cached card should NOT override a mobile-money default
            // derived from the user's profile phone (08/09 prefix). Only
            // switch to Card when the profile gave no mobile-money signal.
            final hasMobileMoneyProfile = profilePhone != null &&
                (profilePhone!.startsWith('08') ||
                    profilePhone!.startsWith('09'));
            if (!hasMobileMoneyProfile) {
              _paymentMethod = 'Card';
            }
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint(
          'Error during profile autofill configuration: $e\n$stackTrace');
    }
  }

  void _goToStep(int s) => setState(() => _step = s);

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTheme.sans()),
      backgroundColor:
          isError ? AppTheme.tamperedColor : AppTheme.authenticColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _submitDetails() async {
    setState(() {
      _detailsTried = true;
      _errorMessage = null;
    });

    if (!_detailsFormKey.currentState!.validate()) return;

    try {
      final res = await Supabase.instance.client
          .from('event_ticket_types')
          .select('quantity_available, quantity_sold')
          .eq('id', widget.ticketTypeId)
          .maybeSingle();

      if (res == null) {
        _showSnack('Unable to verify ticket availability from the server.');
        return;
      }

      final available = (res['quantity_available'] as num?)?.toInt() ?? 0;
      final sold = (res['quantity_sold'] as num?)?.toInt() ?? 0;

      if ((available - sold) <= 0) {
        _showSnack('Sorry, this ticket type just sold out.');
        return;
      }

      // FIX: when the user moves to the payment step, pre-fill the payment
      // phone field from the contact phone if the payment phone is still
      // empty and the contact number matches a mobile-money prefix.
      if (_paymentPhoneCtrl.text.trim().isEmpty) {
        final contact = _contactPhoneCtrl.text.trim();
        if (contact.startsWith('08') || contact.startsWith('09')) {
          setState(() {
            _paymentPhoneCtrl.text = contact;
            _paymentMethod =
                contact.startsWith('08') ? 'TNM Mpamba' : 'Airtel Money';
          });
        }
      }

      _goToStep(1);
    } catch (e, stackTrace) {
      debugPrint(
          'CRITICAL: Exception caught in _submitDetails: $e\n$stackTrace');
      _showSnack(
          'Network error verifying availability. Check console for details.');
    }
  }

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

  // FIX: validate against _paymentPhoneCtrl, not _contactPhoneCtrl
  bool _validateMobileMoney() {
    final phone = _paymentPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showSnack('Please enter your mobile money phone number.');
      return false;
    }
    if (phone.length != 10) {
      _showSnack('Mobile money numbers must be exactly 10 digits.');
      return false;
    }
    if (_paymentMethod == 'TNM Mpamba' && !phone.startsWith('08')) {
      _showSnack('Invalid TNM Mpamba number. Must start with 08.');
      return false;
    }
    if (_paymentMethod == 'Airtel Money' && !phone.startsWith('09')) {
      _showSnack('Invalid Airtel Money number. Must start with 09.');
      return false;
    }
    return true;
  }

  Future<bool> _showMobileMoneyAlertDialog() async {
    final isAirtel = _paymentMethod == 'Airtel Money';
    final themeColor =
        isAirtel ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32);
    // FIX: display the payment phone, not the contact phone
    final phone = _paymentPhoneCtrl.text.trim();
    bool confirmed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        Future.delayed(const Duration(seconds: 3), () {
          if (ctx.mounted) {
            confirmed = true;
            Navigator.pop(ctx);
          }
        });

        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phonelink_ring_rounded,
                    color: themeColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Processing $_paymentMethod',
                  style: AppTheme.merri(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A simulated transaction confirmation prompt request was pushed to $phone. Waiting for carrier response...',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                    color: AppTheme.subTextColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return confirmed;
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return;

    if (_paymentMethod == 'Card') {
      if (!_validateCard()) return;
    } else {
      if (!_validateMobileMoney()) return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Mobile money: show simulated push-authorization dialog.
    // It always auto-approves after 3 seconds (simulated payment).
    if (_paymentMethod != 'Card') {
      final approved = await _showMobileMoneyAlertDialog();
      if (!approved) {
        setState(() => _isProcessing = false);
        return;
      }
    }

    _goToStep(2);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception(
            'Session expired. Please log in again to purchase a ticket.');
      }

      await _saveLocalPaymentAndIdData();

      bool serviceHandled = false;

      // Attempt full service-layer purchase (handles steganography, QR, etc.)
      try {
        final result = await CustomerTicketService.instance.purchaseTicket(
          eventId: widget.eventId,
          eventName: widget.eventName,
          posterUrl: widget.posterUrl,
          eventDate: widget.eventDate,
          venue: widget.venue,
          ticketType: widget.ticketType,
          ticketTypeId: widget.ticketTypeId,
          price: widget.price,
          buyerId: user.id,
          buyerName: _nameCtrl.text.trim(),
          buyerEmail: _emailCtrl.text.trim(),
          // FIX: contact phone goes to the service (written as buyer_phone)
          buyerPhone: _contactPhoneCtrl.text.trim(),
          nationalId: _idCtrl.text.trim(),
          paymentMethod: _paymentMethod,
        );

        if (result.success) {
          _stegoPath = result.stegoLocalPath;
          serviceHandled = true;
        } else {
          debugPrint(
              'Service returned failure: ${result.error} — falling back to direct insert.');
        }
      } catch (serviceError, st) {
        debugPrint(
            'Service layer threw (falling back to direct insert): $serviceError\n$st');
      }

      // Fallback: create ticket + update quantities when the service failed.
      if (!serviceHandled) {
        await _createTicketDirectly(user.id);
        await _decrementTicketQuantity();
      }

      ref.invalidate(publicEventsProvider);
      _goToStep(3);
    } catch (e, stackTrace) {
      debugPrint(
          'CRITICAL POSTGRES/SERVICE ERROR in _processPayment: $e\n$stackTrace');

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

  /// Direct Supabase insert — fallback when [CustomerTicketService] fails.
  Future<void> _createTicketDirectly(String buyerId) async {
    final ticketId = 'TKT-${DateTime.now().millisecondsSinceEpoch}';
    await Supabase.instance.client.from('tickets').insert({
      'ticket_id': ticketId,
      'block_index': 0,
      'event_id': widget.eventId,
      'owner_id': buyerId,
      'owner_name': _nameCtrl.text.trim(),
      'ticket_type': widget.ticketType,
      'price': widget.price,
      'is_sold': true,
      'sold_to': buyerId,
      'sold_at': DateTime.now().toIso8601String(),
      'buyer_email': _emailCtrl.text.trim(),
      // FIX: use the contact phone, not the payment/wallet phone
      'buyer_phone': _contactPhoneCtrl.text.trim(),
    });
  }

  /// Decrements available capacity and increments quantity_sold.
  Future<void> _decrementTicketQuantity() async {
    try {
      await Supabase.instance.client.rpc(
        'decrement_ticket_quantity',
        params: {'ticket_type_id': widget.ticketTypeId},
      );
    } catch (rpcError) {
      debugPrint(
          'RPC decrement_ticket_quantity failed, using manual update: $rpcError');
      try {
        final row = await Supabase.instance.client
            .from('event_ticket_types')
            .select('quantity_available, quantity_sold')
            .eq('id', widget.ticketTypeId)
            .single();
        final avail = (row['quantity_available'] as num? ?? 1).toInt();
        final sold = (row['quantity_sold'] as num? ?? 0).toInt();
        await Supabase.instance.client.from('event_ticket_types').update({
          'quantity_available': (avail - 1).clamp(0, avail),
          'quantity_sold': sold + 1,
        }).eq('id', widget.ticketTypeId);
      } catch (updateError) {
        debugPrint(
            'WARNING: quantity update failed (ticket still created): $updateError');
      }
    }
  }

  Future<void> _shareTicket() async {
    if (_stegoPath == null) return;
    await Share.shareXFiles(
      [XFile(_stegoPath!)],
      subject: 'My ticket for ${widget.eventName}',
      text: 'Ticket for ${widget.eventName} on ${widget.eventDate}\n'
          'Type: ${widget.ticketType} · Holder: ${_nameCtrl.text}',
    );
  }

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
            // FIX: Step 0 uses _contactPhoneCtrl — this is the number stored
            // on the ticket row. It is independent of the payment wallet number.
            AppFormField(
              controller: _contactPhoneCtrl,
              label: 'Phone Number',
              hint: 'e.g., 0888123456 or 0999123456',
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
          Text(
            'PAYMENT METHOD',
            style: AppTheme.sans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppTheme.subTextColor,
            ),
          ),
          const SizedBox(height: 8),
          // Payment method tab selector — unchanged from original
          Row(
            children: ['Card', 'TNM Mpamba', 'Airtel Money'].map((method) {
              final isSelected = _paymentMethod == method;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _paymentMethod = method),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withValues(alpha: 0.15)
                          : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : const Color(0xFF2C2C2C),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        method,
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.subTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          if (_paymentMethod == 'Card') ...[
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
          ] else ...[
            // FIX: preview reads _paymentPhoneCtrl
            _buildMobileWalletPreview(),
            const SizedBox(height: 20),
            Text(
              'PHONE NUMBER',
              style: AppTheme.sans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppTheme.subTextColor,
              ),
            ),
            const SizedBox(height: 6),
            // FIX: phone input uses _paymentPhoneCtrl
            TextField(
              controller: _paymentPhoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              onChanged: (_) => setState(() {}),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTheme.sans(fontSize: 14),
              decoration: InputDecoration(
                hintText: _paymentMethod == 'Airtel Money'
                    ? 'e.g., 0999123456'
                    : 'e.g., 0888123456',
                prefixIcon: const Icon(Icons.phone_android,
                    color: AppTheme.subTextColor, size: 20),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A secure validation authorization push prompt request will trigger automatically on your device screen context.',
                      style: AppTheme.sans(
                          fontSize: 11, color: AppTheme.subTextColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  // FIX: reads _paymentPhoneCtrl (payment wallet number, not contact number)
  Widget _buildMobileWalletPreview() {
    final isAirtel = _paymentMethod == 'Airtel Money';
    final phone = _paymentPhoneCtrl.text.trim();

    return Container(
      width: double.infinity,
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAirtel
              ? [const Color(0xFFD32F2F), const Color(0xFF991B1B)]
              : [const Color(0xFF2E7D32), const Color(0xFF14532D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAirtel ? 'AIRTEL MONEY' : 'TNM MPAMBA',
                  style: AppTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
                const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 20),
              ],
            ),
            const Spacer(),
            Text(
              phone.isEmpty
                  ? (isAirtel ? '099X XXX XXX' : '088X XXX XXX')
                  : phone,
              style: AppTheme.sans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'MOBILE WALLET VIA MWK',
              style: AppTheme.sans(
                fontSize: 8,
                color: Colors.white.withValues(alpha: 0.6),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
