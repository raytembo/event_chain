// lib/features/wallet/wallet_screen.dart
//
// REFACTORED: Now verifies purchased tickets using BOTH payments + tickets tables
// • Only shows tickets that have a COMPLETED payment by the current user (buyer_id)
// • Uses Supabase join: payments → tickets(*)
// • All ticket fields (event_name, venue, event_date, ticket_type, price, block_index, etc.) come from the joined tickets table
// • UI, card design, perforation effect, colors, and layout are 100% unchanged
// • Cleaner, safer, and verifies real purchases

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_theme.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
final myTicketsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final res = await supabase
      .from('payments')
      .select('*, tickets(*)')
      .eq('buyer_id', userId)
      .eq('status', 'completed') // only verified successful purchases
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(res);
});

// ── Screen ────────────────────────────────────────────────────────────────────
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(myTicketsProvider);

    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'MY TICKETS',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myTicketsProvider),
          ),
        ],
      ),
      body: ticketsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading tickets:\n$err',
              textAlign: TextAlign.center,
              style: AppTheme.sans(color: AppTheme.tamperedColor),
            ),
          ),
        ),
        data: (payments) => payments.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: payments.length,
                itemBuilder: (ctx, i) => _WalletCard(payment: payments[i]),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _WalletCard extends StatelessWidget {
  final Map<String, dynamic>
      payment; // each item is a payment row with embedded ticket

  const _WalletCard({required this.payment});

  static String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')} '
          '${_month(dt.month)} ${dt.year}';
    } catch (_) {
      return raw.toString();
    }
  }

  static String _month(int m) => const [
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

  @override
  Widget build(BuildContext context) {
    // Extract the joined ticket data
    final ticket = payment['tickets'] as Map<String, dynamic>? ?? {};

    final typeColor = _typeColor(ticket['ticket_type'] as String? ?? 'General');

    final ticketType = (ticket['ticket_type'] as String? ?? '').toUpperCase();
    final ticketID = ticket['ticket_id'] as String? ?? '';
    final eventName = ticket['event_name'] as String? ?? '';
    final eventDate = _formatDate(ticket['event_date']);
    final venue = ticket['venue'] as String? ?? '';
    final ownerName = ticket['owner_name'] as String? ?? 'You';
    final price = (ticket['price'] as num?)?.toDouble() ?? 0.0;
    final blockIndex = ticket['block_index'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            typeColor.withValues(alpha: 0.22),
            AppTheme.cardColor,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: typeColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ticket type badge + ID
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    ticketType,
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: typeColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#$ticketID',
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.subTextColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Perforation line (classic ticket look)
            Row(
              children: List.generate(
                32,
                (_) => Expanded(
                  child: Container(
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.15),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Event name
            Text(
              eventName,
              style: AppTheme.merri(fontSize: 19, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 8),

            // Date + Venue
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 15,
                  color: AppTheme.subTextColor,
                ),
                const SizedBox(width: 6),
                Text(
                  eventDate,
                  style: AppTheme.sans(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: AppTheme.subTextColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    venue,
                    style: AppTheme.sans(fontSize: 13, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Owner (for verification)
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 15,
                  color: AppTheme.subTextColor,
                ),
                const SizedBox(width: 6),
                Text(
                  ownerName,
                  style:
                      AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Price + Block number
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: AppTheme.sans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: typeColor,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'BLOCK #$blockIndex',
                      style: AppTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.subTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 88,
            color: AppTheme.primaryColor.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 24),
          Text(
            'NO TICKETS YET',
            style: AppTheme.merri(
              fontSize: 18,
              letterSpacing: 3,
              color: AppTheme.subTextColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tickets you purchase from Discover\nwill appear here automatically.',
            style: AppTheme.sans(
              fontSize: 14,
              color: AppTheme.subTextColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
