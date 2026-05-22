// lib/features/customer/widgets/ticket_section.dart

import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utilities/currency_formatter.dart';
import 'purchase_flow_sheet.dart';
import 'shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TICKET SECTION
// ─────────────────────────────────────────────────────────────────────────────

class TicketSection extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String eventDate;
  final String venue;
  final List<Map<String, dynamic>> ticketTypes;

  const TicketSection({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.venue,
    required this.ticketTypes,
  });

  @override
  State<TicketSection> createState() => _TicketSectionState();
}

class _TicketSectionState extends State<TicketSection> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    // Default to first available ticket type; fall back to first if all sold.
    final available = widget.ticketTypes
        .where((t) => (t['quantity_available'] as int? ?? 0) > 0);
    _selectedId = (available.isNotEmpty
        ? available.first
        : widget.ticketTypes.first)['id'] as String;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> get _selectedMap => widget.ticketTypes.firstWhere(
        (t) => t['id'] == _selectedId,
        orElse: () => widget.ticketTypes.first,
      );

  String get _selectedType => _selectedMap['ticket_type'] as String;
  double get _selectedPrice => (_selectedMap['price'] as num).toDouble();
  int get _selectedQty => _selectedMap['quantity_available'] as int? ?? 0;
  bool get _selectedAvailable => _selectedQty > 0;

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'vip':
        return const Color(0xFFFFD700);
      case 'backstage':
        return const Color(0xFFFF6D00);
      case 'student':
        return const Color(0xFF69F0AE);
      default:
        return AppTheme.primaryColor;
    }
  }

  void _openPurchase() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PurchaseFlowSheet(
        eventId: widget.eventId,
        eventName: widget.eventName,
        eventDate: widget.eventDate,
        venue: widget.venue,
        ticketType: _selectedType,
        ticketTypeId: _selectedId,
        price: _selectedPrice,
        quantityAvailable: _selectedQty,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.ticketTypes.isEmpty) {
      return Text(
        'No ticket types available for this event.',
        style: AppTheme.sans(color: AppTheme.subTextColor),
      );
    }

    final accentColor = _typeColor(_selectedType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT TICKET TYPE',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 12),

        // ── Dropdown ──────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.4)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedId,
              dropdownColor: const Color(0xFF1E1E1E),
              isExpanded: true,
              icon:
                  Icon(Icons.expand_more_rounded, color: accentColor, size: 20),
              style: AppTheme.sans(fontSize: 14, color: Colors.white),
              items: widget.ticketTypes.map((t) {
                final type = t['ticket_type'] as String;
                final price = (t['price'] as num).toDouble();
                final qty = t['quantity_available'] as int? ?? 0;
                final color = _typeColor(type);
                final available = qty > 0;
                final id = t['id'] as String;

                return DropdownMenuItem<String>(
                  value: id,
                  child: Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (available ? color : Colors.grey)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: (available ? color : Colors.grey)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: AppTheme.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: available ? color : Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Price
                      Expanded(
                        child: Text(
                          'MK ${formatMwk(price)}',
                          style: AppTheme.merri(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: available ? Colors.white : Colors.grey,
                          ),
                        ),
                      ),
                      // Stock label
                      Text(
                        available ? '$qty left' : 'Sold out',
                        style: AppTheme.sans(
                          fontSize: 11,
                          color: available
                              ? AppTheme.subTextColor
                              : AppTheme.tamperedColor,
                          fontWeight:
                              available ? FontWeight.normal : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedId = value);
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── Summary row ───────────────────────────────────────────────────
        Row(
          children: [
            AvailabilityChip(
              qty: _selectedQty,
              color: accentColor,
              available: _selectedAvailable,
            ),
            const Spacer(),
            Text(
              'MK ${formatMwk(_selectedPrice)}',
              style: AppTheme.merri(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Buy button ────────────────────────────────────────────────────
        if (_selectedAvailable)
          PrimaryButton(
            label: 'Buy ${_selectedType.toUpperCase()} Ticket',
            onTap: _openPurchase,
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.tamperedColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.tamperedColor.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'This ticket type is sold out',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.tamperedColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AVAILABILITY CHIP
// ─────────────────────────────────────────────────────────────────────────────

class AvailabilityChip extends StatelessWidget {
  final int qty;
  final Color color;
  final bool available;

  const AvailabilityChip({
    super.key,
    required this.qty,
    required this.color,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = available ? color : AppTheme.tamperedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available
                ? Icons.confirmation_number_outlined
                : Icons.block_rounded,
            size: 12,
            color: chipColor,
          ),
          const SizedBox(width: 5),
          Text(
            available ? '$qty tickets remaining' : 'Sold out',
            style: AppTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}
