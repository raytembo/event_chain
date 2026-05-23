// lib/features/events/create_ticket_screen.dart

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

  final TextEditingController _priceCtrl = TextEditingController();

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
    _authOwnerID = user?.id ?? '';
    _loadPricesAndCapacity();
  }

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _priceCtrl.dispose();
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

  // ── Submission ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final slotsLeft = _remaining[_ticketType] ?? 0;
    if (slotsLeft <= 0) {
      _showSnack('No $_ticketType tickets are available for this event.',
          isError: true);
      return;
    }

    setState(() => _submitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _IssuingDialog(),
    );

    final eventDate = _formatEventDate(widget.prefillEventDate);

    final (bool success, String? stegoPath) =
        await ref.read(eventsProvider.notifier).addTicket(
              eventName: widget.prefillEventName,
              eventId: widget.eventId,
              posterUrl: widget.posterUrl,
              ownerName: _ownerNameCtrl.text.trim(),
              ownerID: _authOwnerID,
              eventDate: eventDate,
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

  /// Formats a raw ISO-8601 timestamptz into a readable date for the stego
  /// payload (e.g. "25 Dec 2025").
  static String _formatEventDate(String? raw) {
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
                await Gal.putImage(stegoPath);
                _showSnack('Ticket saved to your gallery!');
              } on GalException catch (e) {
                _showSnack('Could not save: ${e.type}', isError: true);
              } catch (e) {
                _showSnack('Could not save: $e', isError: true);
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.share, color: AppTheme.primaryColor),
            label: Text('Share Ticket',
                style: AppTheme.sans(color: AppTheme.primaryColor)),
            onPressed: () async {
              Navigator.pop(ctx);
              await Share.shareXFiles(
                [XFile(stegoPath)],
                subject: 'My EventChain Ticket – ${widget.prefillEventName}',
              );
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
            const _SectionLabel('Attendee Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerNameCtrl,
              style: AppTheme.sans(fontSize: 14),
              decoration: _inputDecoration('Full name', Icons.person_outline),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the attendee name'
                  : null,
            ),
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

  InputDecoration _inputDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
        hintStyle: AppTheme.sans(fontSize: 13, color: const Color(0xFF555555)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// _TypeSelector
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// _IssuingDialog — shown while the blockchain operation runs
// ─────────────────────────────────────────────────────────────────────────────
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
                'Securing the ticket on the blockchain.\nThis usually takes 5–30 seconds.',
                textAlign: TextAlign.center,
                style:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              ),
            ],
          ),
        ),
      );
}
