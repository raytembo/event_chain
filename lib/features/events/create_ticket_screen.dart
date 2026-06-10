// lib/features/events/create_ticket_screen.dart

import 'dart:io';
import 'package:archive/archive_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';

import '../../core/services/supabase_service.dart';
import '../../shared/theme/app_theme.dart';
import 'events_provider.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  final String prefillEventName;
  final String eventId;
  final String posterUrl;

  /// Venue — stored in events.venue, embedded into the stego payload.
  final String? prefillVenue;

  /// ISO-8601 string from events.event_date — embedded into the stego payload
  /// only, never written to the tickets table.
  final String? prefillEventDate;

  const CreateTicketScreen({
    super.key,
    required this.prefillEventName,
    required this.eventId,
    required this.posterUrl,
    this.prefillVenue,
    this.prefillEventDate,
  });

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ownerNameCtrl;

  /// UUID from auth.currentUser — written to tickets.owner_id (FK).
  /// Never editable by the user.
  late final String _authOwnerID;

  // ── Profile lookup state fields ──────────────────────────────────────────
  String? _resolvedOwnerId;
  bool _checkingProfile = false;
  String? _profileStatusMessage;
  bool _hasCheckedProfile = false;

  final TextEditingController _priceCtrl = TextEditingController();

  // ── Payment selection & controllers ──────────────────────────────────────
  String _paymentMethod =
      'Card'; // Options: 'Card', 'TNM Mpamba', 'Airtel Money'
  final TextEditingController _phoneCtrl = TextEditingController();

  // Card payment controllers
  final TextEditingController _cardNumCtrl = TextEditingController();
  final TextEditingController _expiryCtrl = TextEditingController();
  final TextEditingController _cvvCtrl = TextEditingController();
  final TextEditingController _cardHolderCtrl = TextEditingController();

  String _ticketType = 'General';
  bool _submitting = false;

  /// Prices auto-filled from event_ticket_types.
  Map<String, double> _prices = {};

  /// Available slots per ticket type — shown on the selector chips.
  Map<String, int> _remaining = {};

  static const _ticketTypes = ['General', 'VIP', 'Backstage', 'Student'];

  @override
  void initState() {
    super.initState();
    final user = SupabaseService.instance.auth.currentUser;
    _ownerNameCtrl = TextEditingController(
      text: user?.userMetadata?['full_name'] as String? ?? '',
    );
    // Auto-fill cardholder name and default phone fallback if applicable
    _cardHolderCtrl.text = user?.userMetadata?['full_name'] as String? ?? '';
    _authOwnerID = user?.id ?? '';
    _resolvedOwnerId = _authOwnerID; // Default baseline fallback assignment
    _loadPricesAndCapacity();
  }

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _priceCtrl.dispose();
    _phoneCtrl.dispose();
    _cardNumCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    _cardHolderCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadPricesAndCapacity() async {
    try {
      final rows = await SupabaseService.instance.eventTicketTypes
          .select('ticket_type, price, quantity_available, quantity_sold')
          .eq('event_id', widget.eventId);

      final prices = <String, double>{};
      final remaining = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final type = row['ticket_type'] as String;
        prices[type] = (row['price'] as num).toDouble();
        final available = (row['quantity_available'] as num).toInt();
        final sold = (row['quantity_sold'] as num).toInt();
        remaining[type] = (available - sold).clamp(0, available);
      }

      if (!mounted) return;
      setState(() {
        _prices = prices;
        _remaining = remaining;
      });

      // Auto-fill price for the default ticket type.
      if (_prices.containsKey(_ticketType)) {
        _priceCtrl.text = _prices[_ticketType]!.toStringAsFixed(2);
      }
    } catch (e) {
      debugPrint('❌ _loadPricesAndCapacity: $e');
    }
  }

  // ── Remote Profile Search Check ────────────────────────────────────────────

  Future<void> _lookupProfileAccount(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    setState(() {
      _checkingProfile = true;
      _profileStatusMessage = null;
      _hasCheckedProfile = true;
    });

    try {
      // Look up cross-referencing provided name against user profiles table dataset
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('id, display_name, email')
          .eq('display_name', trimmedName)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        if (profile != null) {
          _resolvedOwnerId = profile['id'] as String;
          _profileStatusMessage =
              'Linked with platform user account (${profile['email']})';
        } else {
          // Fall back seamlessly to normal operational parameters
          _resolvedOwnerId = _authOwnerID;
          _profileStatusMessage =
              'No matching user account found. Issuing as guest ticket.';
        }
      });
    } catch (e) {
      debugPrint('❌ _lookupProfileAccount error: $e');
      setState(() {
        _resolvedOwnerId = _authOwnerID;
        _profileStatusMessage =
            'Profile validation offline. Issuing as guest ticket.';
      });
    } finally {
      if (mounted) {
        setState(() => _checkingProfile = false);
      }
    }
  }

  // ── Payment Validation ─────────────────────────────────────────────────────

  String? _validatePayment() {
    if (_paymentMethod == 'Card') {
      final clean = _cardNumCtrl.text.replaceAll(' ', '');
      if (clean.length < 13) return 'Enter a valid card number.';
      if (_expiryCtrl.text.length < 5) return 'Enter a valid expiry date.';
      if (_cvvCtrl.text.length < 3) return 'Enter a valid CVV.';
      if (_cardHolderCtrl.text.trim().isEmpty) {
        return 'Enter the cardholder name.';
      }
    } else {
      final phone = _phoneCtrl.text.trim();
      if (phone.isEmpty) return 'Enter your mobile money phone number.';
      if (phone.length != 10) return 'Enter a valid 10-digit phone number.';

      // Strict prefix validations
      if (_paymentMethod == 'TNM Mpamba' && !phone.startsWith('08')) {
        return 'Invalid TNM Mpamba number. Must start with 08.';
      }
      if (_paymentMethod == 'Airtel Money' && !phone.startsWith('09')) {
        return 'Invalid Airtel Money number. Must start with 09.';
      }
    }
    return null;
  }

  // ── Submission & Processing Dialog Flows ───────────────────────────────────

  void _showMobileMoneySimulationDialog(
      String method, String phoneNumber, VoidCallback onSuccess) {
    final isAirtel = method == 'Airtel Money';
    final themeColor =
        isAirtel ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        // Automatically proceed after simulating network delay
        Future.delayed(const Duration(seconds: 3), () {
          if (ctx.mounted) {
            Navigator.pop(ctx); // Dismiss processing dialog
            onSuccess(); // Proceed to save data assets
          }
        });

        return AlertDialog(
          backgroundColor: AppTheme.cardColor,
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
                    color: themeColor.withOpacity(0.1),
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
                  'Processing $method',
                  style: AppTheme.merri(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A transaction validation prompt request was pushed to $phoneNumber. Waiting for network confirmation...',
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
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final paymentError = _validatePayment();
    if (paymentError != null) {
      _showSnack(paymentError, isError: true);
      return;
    }

    final slotsLeft = _remaining[_ticketType] ?? 0;
    if (slotsLeft <= 0) {
      _showSnack('No $_ticketType tickets are available for this event.',
          isError: true);
      return;
    }

    if (_paymentMethod == 'Card') {
      _executeTicketIssuance();
    } else {
      _showMobileMoneySimulationDialog(
        _paymentMethod,
        _phoneCtrl.text.trim(),
        () => _executeTicketIssuance(),
      );
    }
  }

  Future<void> _executeTicketIssuance() async {
    setState(() => _submitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _IssuingDialog(),
    );

    final String eventDateRaw = widget.prefillEventDate ?? '';

    final (bool success, String? stegoPath) =
        await ref.read(eventsProvider.notifier).addTicket(
              eventName: widget.prefillEventName,
              eventId: widget.eventId,
              posterUrl: widget.posterUrl,
              ownerName: _ownerNameCtrl.text.trim(),
              ownerID: _resolvedOwnerId ?? _authOwnerID,
              eventDate: _formatEventDateForDisplay(eventDateRaw),
              venue: widget.prefillVenue ?? 'TBD',
              ticketType: _ticketType,
              price: double.parse(_priceCtrl.text.trim()),
            );

    if (!mounted) return;
    Navigator.pop(context); // close the issuing dialog
    setState(() => _submitting = false);

    if (success && stegoPath != null) {
      _loadPricesAndCapacity(); // refresh remaining counts
      _showSuccessOptions(stegoPath);
    } else {
      final msg = ref.read(eventsProvider).message ?? 'Something went wrong.';
      _showSnack(msg, isError: true);
    }
  }

  /// Formats a raw ISO-8601 timestamptz into a readable date for UI display
  static String _formatEventDateForDisplay(String? raw) {
    if (raw == null || raw.isEmpty) {
      final now = DateTime.now();
      return '${now.day.toString().padLeft(2, '0')} '
          '${_monthName(now.month)} ${now.year}';
    }
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')} '
          '${_monthName(dt.month)} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  static String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][m];

  // ── Success / error UI ─────────────────────────────────────────────────────

  void _showSuccessOptions(String stegoPath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Ticket Issued!',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Your ticket has been created and saved to the blockchain.\n\n'
          'What would you like to do with the ticket image?',
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_alt, color: AppTheme.primaryColor),
            label: Text('Save to Gallery',
                style: AppTheme.sans(color: AppTheme.primaryColor)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final file = File(stegoPath);
                final lowerPath = stegoPath.toLowerCase();
                String pathToSave = stegoPath;

                if (!lowerPath.endsWith('.png') &&
                    !lowerPath.endsWith('.jpg') &&
                    !lowerPath.endsWith('.jpeg')) {
                  final newPath =
                      '${file.parent.path}/ticket_${DateTime.now().millisecondsSinceEpoch}.png';
                  final newFile = await file.copy(newPath);
                  pathToSave = newFile.path;
                }

                await Gal.putImage(pathToSave, album: 'EventChain');

                if (mounted) {
                  _showSnack('Saved to "EventChain" folder in Gallery!');
                }
              } on GalException catch (e) {
                if (mounted) {
                  _showSnack('Could not save: ${e.type}', isError: true);
                }
              } catch (e) {
                if (mounted) _showSnack('Could not save: $e', isError: true);
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.share, color: AppTheme.primaryColor),
            label: Text('Share Ticket',
                style: AppTheme.sans(color: AppTheme.primaryColor)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final imageFile = File(stegoPath);
                final imageBytes = await imageFile.readAsBytes();

                final imageFileName =
                    'ticket_${widget.prefillEventName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.png';

                final archive = Archive();
                archive.addFile(
                  ArchiveFile(imageFileName, imageBytes.length, imageBytes),
                );

                final zipBytes = ZipEncoder().encode(archive);
                final tempDir = Directory.systemTemp;
                final zipPath =
                    '${tempDir.path}/ticket_${DateTime.now().millisecondsSinceEpoch}.zip';
                await File(zipPath).writeAsBytes(zipBytes);

                await Share.shareXFiles(
                  [XFile(zipPath, mimeType: 'application/zip')],
                  subject: 'My EventChain Ticket – ${widget.prefillEventName}',
                );
              } catch (e) {
                if (mounted) _showSnack('Could not share: $e', isError: true);
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: AppTheme.sans()),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTheme.sans(fontSize: 13)),
      backgroundColor: isError ? AppTheme.tamperedColor : AppTheme.primaryColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Issue New Ticket',
            style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.dividerColor),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // ── Event (read-only) ──────────────────────────────────────────
            const _SectionLabel('Event'),
            const SizedBox(height: 8),
            _ReadOnlyField(
              value: widget.prefillEventName,
              icon: Icons.event_outlined,
            ),
            const SizedBox(height: 24),

            // ── Ticket type ────────────────────────────────────────────────
            const _SectionLabel('Ticket Type'),
            const SizedBox(height: 8),
            _TypeSelector(
              selected: _ticketType,
              types: _ticketTypes,
              prices: _prices,
              remaining: _remaining,
              onChanged: (t) {
                setState(() => _ticketType = t);
                if (_prices.containsKey(t)) {
                  _priceCtrl.text = _prices[t]!.toStringAsFixed(2);
                }
              },
            ),
            const SizedBox(height: 24),

            // ── Price ──────────────────────────────────────────────────────
            const _SectionLabel('Price (MWK)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              style: AppTheme.sans(fontSize: 14),
              decoration: _inputDecoration('0.00', Icons.attach_money_outlined)
                  .copyWith(prefixText: 'MWK '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a price';
                }
                final d = double.tryParse(v.trim());
                if (d == null || d < 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── Attendee name ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel('Attendee Name'),
                if (_checkingProfile)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.primaryColor),
                  )
                else
                  GestureDetector(
                    onTap: () => _lookupProfileAccount(_ownerNameCtrl.text),
                    child: Text(
                      'VERIFY ACCOUNT',
                      style: AppTheme.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerNameCtrl,
              style: AppTheme.sans(fontSize: 14),
              decoration:
                  _inputDecoration('Full name', Icons.person_outline).copyWith(
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search,
                      size: 18, color: AppTheme.subTextColor),
                  onPressed: () => _lookupProfileAccount(_ownerNameCtrl.text),
                ),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (v) {
                if (_hasCheckedProfile) {
                  setState(() {
                    _hasCheckedProfile = false;
                    _profileStatusMessage = null;
                    _resolvedOwnerId = _authOwnerID;
                  });
                }
                if (_cardHolderCtrl.text.isEmpty ||
                    _cardHolderCtrl.text ==
                        (SupabaseService.instance.auth.currentUser
                                ?.userMetadata?['full_name'] as String? ??
                            '')) {
                  setState(() => _cardHolderCtrl.text = v);
                }
              },
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the attendee name'
                  : null,
            ),
            if (_profileStatusMessage != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _profileStatusMessage!,
                  style: AppTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _resolvedOwnerId != _authOwnerID
                        ? AppTheme.primaryColor
                        : AppTheme.subTextColor,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // ── Payment ────────────────────────────────────────────────────
            _buildPaymentSection(),
            const SizedBox(height: 32),

            // ── Submit ─────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      AppTheme.primaryColor.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.confirmation_number_outlined,
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Issue Ticket',
                            style: AppTheme.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds while the ticket is secured.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Payment section selector & variations ──────────────────────────────────

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Payment Method'),
        const SizedBox(height: 8),
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
                        : AppTheme.cardMidColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      method,
                      style: AppTheme.sans(
                        fontSize: 12,
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
          _buildCardFields()
        ] else ...[
          _buildMobileMoneyFields()
        ],
      ],
    );
  }

  Widget _buildCardFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Card Details'),
            const SizedBox(width: 6),
            const Icon(Icons.lock_outline,
                size: 12, color: AppTheme.subTextColor),
          ],
        ),
        const SizedBox(height: 12),
        _CardPreview(
          number: _cardNumCtrl.text,
          holder: _cardHolderCtrl.text,
          expiry: _expiryCtrl.text,
        ),
        const SizedBox(height: 16),
        _CardField(
          label: 'Card Number',
          controller: _cardNumCtrl,
          icon: Icons.credit_card_rounded,
          type: TextInputType.number,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CardNumberFormatter(),
          ],
          maxLength: 19,
          hint: '1234 5678 9012 3456',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _CardField(
                label: 'Expiry',
                controller: _expiryCtrl,
                icon: Icons.calendar_today_outlined,
                type: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _ExpiryFormatter(),
                ],
                maxLength: 5,
                hint: 'MM/YY',
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _CardField(
                label: 'CVV',
                controller: _cvvCtrl,
                icon: Icons.lock_outline_rounded,
                type: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                hint: '•••',
                obscure: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _CardField(
          label: 'Cardholder Name',
          controller: _cardHolderCtrl,
          icon: Icons.person_outline_rounded,
          type: TextInputType.name,
          hint: 'Name as on card',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildMobileMoneyFields() {
    final isAirtel = _paymentMethod == 'Airtel Money';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Mobile Wallet Account'),
            const SizedBox(width: 6),
            const Icon(Icons.security_rounded,
                size: 12, color: AppTheme.subTextColor),
          ],
        ),
        const SizedBox(height: 12),
        _MobileWalletPreview(
          phoneNumber: _phoneCtrl.text,
          isAirtel: isAirtel,
        ),
        const SizedBox(height: 16),
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
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          onChanged: (_) => setState(() {}),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTheme.sans(fontSize: 14),
          decoration: _inputDecoration(
            isAirtel ? 'e.g., 0999123456' : 'e.g., 0888123456',
            Icons.phone_android,
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardMidColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A secure validation authorization push prompt request will trigger automatically on your screen device.',
                  style:
                      AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
        hintStyle: AppTheme.sans(fontSize: 13, color: const Color(0xFF555555)),
      );
}

// ── Mobile Wallet Preview Custom Widget ──────────────────────────────────────
class _MobileWalletPreview extends StatelessWidget {
  final String phoneNumber;
  final bool isAirtel;

  const _MobileWalletPreview({
    required this.phoneNumber,
    required this.isAirtel,
  });

  @override
  Widget build(BuildContext context) {
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
              phoneNumber.isEmpty
                  ? (isAirtel ? '099X XXX XXX' : '088X XXX XXX')
                  : phoneNumber,
              style: AppTheme.sans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'MOBILE PAYMENT WALLET',
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
}

// ── Card Preview & Formatters ────────────────────────────────────────────────
class _CardPreview extends StatelessWidget {
  final String number;
  final String holder;
  final String expiry;

  const _CardPreview({
    required this.number,
    required this.holder,
    required this.expiry,
  });

  LinearGradient _cardGradient() {
    final first =
        number.replaceAll(' ', '').isEmpty ? '' : number.replaceAll(' ', '')[0];
    return switch (first) {
      '4' => const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      '5' => const LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFAD1457)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      '3' => const LinearGradient(
          colors: [Color(0xFF004D40), Color(0xFF00695C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      _ => const LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF2C2C2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };
  }

  String _maskedNumber() {
    final digits = number.replaceAll(' ', '');
    if (digits.isEmpty) return '•••• •••• •••• ••••';
    final padded = digits.padRight(16, '•');
    final g1 = padded.substring(0, 4);
    final g2 = padded.substring(4, 8);
    final g3 = padded.substring(8, 12);
    final g4 = padded.substring(12, 16);
    return '$g1 '
        '${digits.length > 4 ? '••••' : g2} '
        '${digits.length > 8 ? '••••' : g3} '
        '$g4';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        gradient: _cardGradient(),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06), width: 40),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.04), width: 30),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFB8960C), width: 0.5),
                      ),
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFB8960C),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _networkLabel(),
                      style: AppTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _maskedNumber(),
                  style: AppTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CARD HOLDER',
                          style: AppTheme.sans(
                            fontSize: 8,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          holder.trim().isEmpty
                              ? 'FULL NAME'
                              : holder.trim().toUpperCase(),
                          style: AppTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'EXPIRES',
                          style: AppTheme.sans(
                            fontSize: 8,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expiry.isEmpty ? 'MM/YY' : expiry,
                          style: AppTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _networkLabel() {
    final first =
        number.replaceAll(' ', '').isEmpty ? '' : number.replaceAll(' ', '')[0];
    return switch (first) {
      '4' => 'VISA',
      '5' => 'MASTERCARD',
      '3' => 'AMEX',
      _ => '',
    };
  }
}

class _CardField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType type;
  final List<TextInputFormatter> formatters;
  final int? maxLength;
  final String hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  const _CardField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.type,
    this.formatters = const [],
    this.maxLength,
    required this.hint,
    this.obscure = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTheme.sans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppTheme.subTextColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: type,
          inputFormatters: formatters,
          maxLength: maxLength,
          obscureText: obscure,
          style: AppTheme.sans(fontSize: 14),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
            hintStyle:
                AppTheme.sans(fontSize: 13, color: const Color(0xFF555555)),
          ),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll('/', '');
    if (digits.length >= 3) {
      final formatted = '${digits.substring(0, 2)}/${digits.substring(2)}';
      return newValue.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return newValue;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTheme.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppTheme.subTextColor,
        ),
      );
}

class _ReadOnlyField extends StatelessWidget {
  final String value;
  final IconData icon;
  const _ReadOnlyField({required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardMidColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.subTextColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: AppTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const Icon(Icons.lock_outline,
                color: AppTheme.subTextColor, size: 16),
          ],
        ),
      );
}

class _TypeSelector extends StatelessWidget {
  final String selected;
  final List<String> types;
  final Map<String, double> prices;
  final Map<String, int> remaining;
  final ValueChanged<String> onChanged;

  const _TypeSelector({
    required this.selected,
    required this.types,
    required this.prices,
    required this.remaining,
    required this.onChanged,
  });

  Color _colorFor(String type) => switch (type.toLowerCase()) {
        'vip' => const Color(0xFFFFD700),
        'backstage' => const Color(0xFFFF6D00),
        'student' => const Color(0xFF69F0AE),
        _ => AppTheme.primaryColor,
      };

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: types.map((t) {
          final isSelected = t == selected;
          final color = _colorFor(t);
          final price = prices[t];
          final slots = remaining[t];
          final soldOut = slots != null && slots <= 0;

          return GestureDetector(
            onTap: soldOut ? null : () => onChanged(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: soldOut
                    ? AppTheme.cardMidColor.withValues(alpha: 0.5)
                    : isSelected
                        ? color.withValues(alpha: 0.18)
                        : AppTheme.cardMidColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: soldOut
                      ? AppTheme.dividerColor.withValues(alpha: 0.4)
                      : isSelected
                          ? color
                          : AppTheme.dividerColor,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.toUpperCase(),
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: soldOut
                          ? AppTheme.subTextColor.withValues(alpha: 0.4)
                          : isSelected
                              ? color
                              : AppTheme.subTextColor,
                    ),
                  ),
                  if (price != null)
                    Text(
                      'MWK ${price.toStringAsFixed(0)}',
                      style: AppTheme.sans(
                        fontSize: 10,
                        color: soldOut
                            ? AppTheme.subTextColor.withValues(alpha: 0.4)
                            : isSelected
                                ? color
                                : AppTheme.subTextColor,
                      ),
                    ),
                  if (slots != null)
                    Text(
                      soldOut ? 'SOLD OUT' : '$slots left',
                      style: AppTheme.sans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: soldOut
                            ? AppTheme.tamperedColor.withValues(alpha: 0.7)
                            : isSelected
                                ? color.withValues(alpha: 0.8)
                                : AppTheme.subTextColor.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      );
}

class _IssuingDialog extends StatelessWidget {
  const _IssuingDialog();

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primaryColor),
              const SizedBox(height: 24),
              Text(
                'Issuing your ticket…',
                style:
                    AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Securing the ticket \nThis usually takes 5–30 seconds.',
                textAlign: TextAlign.center,
                style:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              ),
            ],
          ),
        ),
      );
}
