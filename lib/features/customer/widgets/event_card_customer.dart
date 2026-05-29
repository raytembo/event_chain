// lib/features/customer/widgets/event_card_customer.dart

import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utilities/currency_formatter.dart';
import 'ticket_section.dart';

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const EventCard({super.key, required this.event});

  // ── Data helpers ──────────────────────────────────────────────────────────

  String get _posterUrl => event['poster_url'] as String? ?? '';
  String get _name => event['event_name'] as String? ?? '';
  String get _date => _formatDate(event['event_date']);
  String get _venue => event['venue'] as String? ?? '';
  String get _desc => event['description'] as String? ?? '';
  String get _ownerName => (event['owner']?['display_name'] as String?) ?? '';
  String get _eventId => event['id'] as String;

  List<Map<String, dynamic>> get _ticketTypes =>
      List<Map<String, dynamic>>.from(event['ticket_types'] ?? []);

  bool get _isSoldOut =>
      _ticketTypes.isNotEmpty &&
      _ticketTypes.every((t) => (t['quantity_available'] as int? ?? 0) <= 0);

  double? get _minPrice {
    final available =
        _ticketTypes.where((t) => (t['quantity_available'] as int? ?? 0) > 0);
    if (available.isEmpty) return null;
    return available
        .map((t) => (t['price'] as num).toDouble())
        .reduce((a, b) => a < b ? a : b);
  }

  static String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')} '
          '${_monthName(dt.month)} ${dt.year}';
    } catch (_) {
      return raw.toString();
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
        'Dec'
      ][m];

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPosterSection(),
          _buildDetailsSection(context),
        ],
      ),
    );
  }

  Widget _buildPosterSection() {
    return Stack(
      children: [
        _posterUrl.isNotEmpty
            ? Image.network(
                _posterUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                color: _isSoldOut ? Colors.black45 : null,
                colorBlendMode: _isSoldOut ? BlendMode.darken : null,
                errorBuilder: (_, __, ___) => const _PosterPlaceholder(),
              )
            : const _PosterPlaceholder(),
        _buildPosterGradient(),
        if (_isSoldOut) _buildSoldOutOverlay() else _buildPriceBadge(),
      ],
    );
  }

  Widget _buildPosterGradient() => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          height: 80,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xCC1A1A1A)],
            ),
          ),
        ),
      );

  Widget _buildSoldOutOverlay() => Positioned.fill(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.tamperedColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'SOLD OUT',
              style: AppTheme.sans(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      );

  Widget _buildPriceBadge() {
    if (_minPrice == null) return const SizedBox.shrink();
    return Positioned(
      bottom: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'From MK ${formatMwk(_minPrice!)}',
          style: AppTheme.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_name, style: AppTheme.merri(fontSize: 20)),
          if (_ownerName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'by $_ownerName',
              style: AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
            ),
          ],
          const SizedBox(height: 12),
          _buildMetaRow(),
          if (_desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _desc,
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 20),
          _isSoldOut
              ? const _SoldOutBanner()
              : TicketSection(
                  eventId: _eventId,
                  eventName: _name,
                  eventDate: _date,
                  venue: _venue,
                  posterUrl: _posterUrl, // ← now passed to the service
                  ticketTypes: _ticketTypes,
                ),
        ],
      ),
    );
  }

  Widget _buildMetaRow() => Row(
        children: [
          const Icon(Icons.calendar_today_rounded,
              size: 13, color: AppTheme.subTextColor),
          const SizedBox(width: 5),
          Text(_date,
              style: AppTheme.sans(fontSize: 13, color: Colors.white70)),
          const SizedBox(width: 16),
          const Icon(Icons.location_on_outlined,
              size: 13, color: AppTheme.subTextColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _venue,
              style: AppTheme.sans(fontSize: 13, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

// ── Private sub-widgets ──────────────────────────────────────────────────────

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        height: 200,
        width: double.infinity,
        color: const Color(0xFF252525),
        child: const Center(
          child: Icon(Icons.event_rounded, color: Color(0xFF3A3A3A), size: 48),
        ),
      );
}

class _SoldOutBanner extends StatelessWidget {
  const _SoldOutBanner();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.tamperedColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppTheme.tamperedColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block_rounded,
                color: AppTheme.tamperedColor, size: 18),
            const SizedBox(width: 10),
            Text(
              'All tickets sold out',
              style: AppTheme.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.tamperedColor,
              ),
            ),
          ],
        ),
      );
}
