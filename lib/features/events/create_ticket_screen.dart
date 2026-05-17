// lib/features/events/create_ticket_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';

import '../../shared/theme/app_theme.dart';
import 'events_provider.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  final String prefillEventName;
  final String eventId;
  final String posterUrl;
  final String? prefillVenue;
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
  late final TextEditingController _ownerIDCtrl;
  final TextEditingController _priceCtrl = TextEditingController();

  String _ticketType = 'General';
  bool _submitting = false;

  // Auto-fill prices from Supabase event_ticket_types
  Map<String, double> _prices = {};

  static const _ticketTypes = ['General', 'VIP', 'Backstage', 'Student'];

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _ownerNameCtrl = TextEditingController(text: user?.userMetadata?['full_name'] as String? ?? '');
    _ownerIDCtrl = TextEditingController(text: user?.id ?? '');

    _loadTicketPrices();
  }

  Future<void> _loadTicketPrices() async {
    final prices = await ref.read(eventsProvider.notifier).getTicketPrices(widget.eventId);
    setState(() => _prices = prices);

    if (_prices.containsKey(_ticketType)) {
      _priceCtrl.text = _prices[_ticketType]!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _ownerIDCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _MiningDialog(),
    );

    final (bool success, String? stegoPath) = await ref.read(eventsProvider.notifier).addTicket(
      eventName: widget.prefillEventName,
      eventId: widget.eventId,
      posterUrl: widget.posterUrl,
      ownerName: _ownerNameCtrl.text.trim(),
      ownerID: _ownerIDCtrl.text.trim(),
      eventDate: widget.prefillEventDate ?? '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
      venue: widget.prefillVenue ?? 'TBD',
      ticketType: _ticketType,
      price: double.parse(_priceCtrl.text.trim()),
    );

    if (!mounted) return;
    Navigator.pop(context); // close mining dialog

    setState(() => _submitting = false);

    if (success && stegoPath != null) {
      _showSuccessOptions(stegoPath);
    } else {
      final err = ref.read(eventsProvider).error ?? 'Unknown error';
      _showSnack('Failed: $err', isError: true);
    }
  }

  void _showSuccessOptions(String stegoPath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Ticket Created!',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Your on-chain ticket has been mined and uploaded.\n\n'
              'What would you like to do with the ticket image?',
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_alt, color: AppTheme.primaryColor),
            label: Text('Save to Gallery', style: AppTheme.sans(color: AppTheme.primaryColor)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Gal.putImage(stegoPath);
                _showSnack('✅ Ticket saved to your gallery!', isError: false);
              } on GalException catch (e) {
                _showSnack('Failed to save: ${e.type}', isError: true);
              } catch (e) {
                _showSnack('Failed to save: $e', isError: true);
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.share, color: AppTheme.primaryColor),
            label: Text('Share Ticket', style: AppTheme.sans(color: AppTheme.primaryColor)),
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
        title: Text('New Ticket', style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700)),
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
            _SectionLabel('Event'),
            const SizedBox(height: 8),
            _ReadOnlyField(
              value: widget.prefillEventName,
              icon: Icons.event_outlined,
            ),
            const SizedBox(height: 24),

            _SectionLabel('Ticket Type'),
            const SizedBox(height: 8),
            _TypeSelector(
              selected: _ticketType,
              types: _ticketTypes,
              prices: _prices,
              onChanged: (t) {
                setState(() => _ticketType = t);
                if (_prices.containsKey(t)) {
                  _priceCtrl.text = _prices[t]!.toStringAsFixed(2);
                }
              },
            ),
            const SizedBox(height: 24),

            _SectionLabel('Price (MWK)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              style: AppTheme.sans(fontSize: 14),
              decoration: _decoration('0.00', Icons.attach_money_outlined).copyWith(
                prefixText: 'MWK ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Price is required';
                final d = double.tryParse(v.trim());
                if (d == null || d < 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // NEW: Image format selector removed — C++ outputs PNG directly.

            _SectionLabel('Owner Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerNameCtrl,
              style: AppTheme.sans(fontSize: 14),
              decoration: _decoration('Full name', Icons.person_outline),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Owner name is required' : null,
            ),
            const SizedBox(height: 16),

            _SectionLabel('Owner ID'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerIDCtrl,
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              decoration: _decoration('user ID', Icons.badge_outlined),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Owner ID is required' : null,
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppTheme.primaryColor.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'MINE & CREATE TICKET',
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
              'Creating a ticket runs Proof-of-Work mining on device. This may take a few seconds.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
    hintStyle: AppTheme.sans(fontSize: 13, color: const Color(0xFF555555)),
  );
}

// ── Reusable widgets ─────────────────────────────────────────────────────────
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
        Icon(Icons.lock_outline, color: AppTheme.subTextColor, size: 16),
      ],
    ),
  );
}

class _TypeSelector extends StatelessWidget {
  final String selected;
  final List<String> types;
  final Map<String, double> prices;
  final ValueChanged<String> onChanged;

  const _TypeSelector({
    required this.selected,
    required this.types,
    required this.prices,
    required this.onChanged,
  });

  Color _colorFor(String type) {
    switch (type.toLowerCase()) {
      case 'vip': return const Color(0xFFFFD700);
      case 'backstage': return const Color(0xFFFF6D00);
      case 'student': return const Color(0xFF69F0AE);
      default: return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: types.map((t) {
      final isSelected = t == selected;
      final color = _colorFor(t);
      final price = prices[t];

      return GestureDetector(
        onTap: () => onChanged(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.18) : AppTheme.cardMidColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : AppTheme.dividerColor,
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
                  color: isSelected ? color : AppTheme.subTextColor,
                ),
              ),
              if (price != null)
                Text(
                  'MWK ${price.toStringAsFixed(0)}',
                  style: AppTheme.sans(
                    fontSize: 10,
                    color: isSelected ? color : AppTheme.subTextColor,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

class _MiningDialog extends StatelessWidget {
  const _MiningDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
              'Mining ticket...',
              style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Processing.\nThis may take 5–30 seconds on low-end devices.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
            ),
          ],
        ),
      ),
    );
  }
}