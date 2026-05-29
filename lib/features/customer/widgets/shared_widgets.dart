// lib/features/customer/widgets/shared_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utilities/currency_formatter.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const PrimaryButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          child: Text(
            label,
            style: AppTheme.sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
      );
}

class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const SummaryRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor)),
            Flexible(
              child: Text(
                value,
                style: AppTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class TicketSummaryBadge extends StatelessWidget {
  final String type;
  final double price;
  final String eventName;

  const TicketSummaryBadge({
    super.key,
    required this.type,
    required this.price,
    required this.eventName,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$type Ticket',
                      style: AppTheme.sans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    'MK ${formatMwk(price)} · $eventName',
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.subTextColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class OrderSummary extends StatelessWidget {
  final String name;
  final String type;
  final double price;
  final String eventName;

  const OrderSummary({
    super.key,
    required this.name,
    required this.type,
    required this.price,
    required this.eventName,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            SummaryRow('Event', eventName),
            SummaryRow('Ticket Type', type),
            SummaryRow('Buyer', name.isEmpty ? '—' : name),
            const Divider(color: AppTheme.dividerColor, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount',
                  style:
                      AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
                ),
                Text(
                  'MK ${formatMwk(price)}',
                  style: AppTheme.merri(
                      fontSize: 20, color: AppTheme.primaryColor),
                ),
              ],
            ),
          ],
        ),
      );
}

class TicketDetailCard extends StatelessWidget {
  final String eventName;
  final String ticketType;
  final String eventDate;
  final String venue;
  final String buyerName;
  final double price;

  const TicketDetailCard({
    super.key,
    required this.eventName,
    required this.ticketType,
    required this.eventDate,
    required this.venue,
    required this.buyerName,
    required this.price,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppTheme.authenticColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eventName, style: AppTheme.merri(fontSize: 17)),
            const SizedBox(height: 12),
            SummaryRow('Ticket Type', ticketType),
            SummaryRow('Event Date', eventDate),
            SummaryRow('Venue', venue),
            SummaryRow('Buyer', buyerName),
            SummaryRow('Price', 'MK ${formatMwk(price)}'),
          ],
        ),
      );
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.tamperedColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppTheme.tamperedColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          message,
          style: AppTheme.sans(fontSize: 12, color: AppTheme.tamperedColor),
        ),
      );
}

class SuccessIcon extends StatelessWidget {
  const SuccessIcon({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.authenticColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            size: 48, color: AppTheme.authenticColor),
      );
}

class SheetHeader extends StatelessWidget {
  final String stepLabel;
  final String title;
  final VoidCallback? onCancel;

  const SheetHeader({
    super.key,
    required this.stepLabel,
    required this.title,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 14),
            child: Row(
              children: [
                if (stepLabel.isNotEmpty) _StepBadge(label: stepLabel),
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.merri(fontSize: 18),
                    textAlign:
                        stepLabel.isEmpty ? TextAlign.center : TextAlign.left,
                  ),
                ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    child: Text(
                      'Cancel',
                      style: AppTheme.sans(color: AppTheme.subTextColor),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: AppTheme.dividerColor),
        ],
      );
}

class _StepBadge extends StatelessWidget {
  final String label;
  const _StepBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor,
          ),
        ),
      );
}

class AppFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType type;
  final String? Function(String?)? validator;

  const AppFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.type = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.subTextColor,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: type,
            validator: validator,
            style: AppTheme.sans(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
              errorStyle:
                  AppTheme.sans(fontSize: 11, color: AppTheme.tamperedColor),
            ),
          ),
        ],
      );
}

class CardInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType type;
  final List<TextInputFormatter>? formatters;
  final int? maxLength;
  final bool obscure;
  final void Function(String)? onChanged;

  const CardInput({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.type,
    this.formatters,
    this.maxLength,
    this.obscure = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
            onChanged: onChanged,
            style: AppTheme.sans(fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.subTextColor, size: 20),
              counterText: '',
            ),
          ),
        ],
      );
}

class CardPreview extends StatelessWidget {
  final String number;
  final String holder;
  final String expiry;

  const CardPreview({
    super.key,
    required this.number,
    required this.holder,
    required this.expiry,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: 170,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2A50), Color(0xFF0D1830)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.credit_card_rounded,
                color: Colors.white54, size: 32),
            Text(
              number.isEmpty ? '•••• •••• •••• ••••' : number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 3,
                fontFamily: 'Courier',
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  holder.isEmpty ? 'CARDHOLDER NAME' : holder.toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  expiry.isEmpty ? 'MM/YY' : expiry,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined,
                size: 72, color: AppTheme.primaryColor.withValues(alpha: 0.25)),
            const SizedBox(height: 24),
            Text(
              'No Events Yet',
              style: AppTheme.merri(fontSize: 20, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Events will appear here once\norganisers publish them.',
              style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class ErrorState extends StatelessWidget {
  final String message;
  const ErrorState({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppTheme.tamperedColor),
              const SizedBox(height: 16),
              Text('Something went wrong', style: AppTheme.merri(fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.sans(color: AppTheme.subTextColor),
              ),
            ],
          ),
        ),
      );
}
