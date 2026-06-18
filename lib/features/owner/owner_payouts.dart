// lib/features/owner/payouts_revenue_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../events/events_provider.dart';

class PayoutsRevenueScreen extends ConsumerWidget {
  const PayoutsRevenueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(ownerEventsProvider);

    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'PAYOUTS & REVENUE',
          style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: eventsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
        ),
        error: (err, stack) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppTheme.tamperedColor, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to load financial telemetry.',
                  style:
                      AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style:
                      AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (events) {
          // ── Real-Time Metrics Aggregation ──────────────────────────────────
          double totalRevenue = 0.0;
          int totalTicketsSold = 0;
          int totalTicketsAvailable = 0;

          for (final event in events) {
            final ticketTypes =
                event['event_ticket_types'] as List<dynamic>? ?? [];
            for (final type in ticketTypes) {
              final price = (type['price'] as num?)?.toDouble() ?? 0.0;
              final sold = (type['quantity_sold'] as num?)?.toInt() ?? 0;
              final available =
                  (type['quantity_available'] as num?)?.toInt() ?? 0;

              totalRevenue += price * sold;
              totalTicketsSold += sold;
              totalTicketsAvailable += available;
            }
          }

          return RefreshIndicator(
            color: AppTheme.primaryColor,
            backgroundColor: AppTheme.cardColor,
            onRefresh: () => ref.refresh(ownerEventsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Dynamic Revenue Overview Dashboard Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL REVENUE (ESCROWED)',
                        style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.subTextColor,
                            letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MWK ${totalRevenue.toStringAsFixed(2)}',
                        style: AppTheme.merri(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatSubfield('Tickets Sold',
                              '$totalTicketsSold / $totalTicketsAvailable'),
                          _buildStatSubfield('Settlement State',
                              events.isEmpty ? 'No Events' : 'Pending Close'),
                        ],
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Linked Payout Routing',
                  style:
                      AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                // Connected Settlement Endpoint Info Node
                Container(
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
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.account_balance_rounded,
                            color: AppTheme.primaryColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Connected Bank Account',
                                style: AppTheme.sans(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                                'Settlements auto-route within 24 hours of event close.',
                                style: AppTheme.sans(
                                    fontSize: 12,
                                    color: AppTheme.subTextColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                Text(
                  'Revenue Breakdown by Event',
                  style:
                      AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(
                      child: Text(
                        'No organized events found to evaluate pipeline.',
                        style: AppTheme.sans(
                            fontSize: 13, color: AppTheme.subTextColor),
                      ),
                    ),
                  )
                else
                  ...events.map((event) {
                    final eventName =
                        event['event_name'] as String? ?? 'Unnamed Event';
                    final eventDateStr = event['event_date'] as String? ?? '';

                    // Parse native dates smoothly
                    String formattedDate = 'Date Unspecified';
                    if (eventDateStr.isNotEmpty) {
                      final parsedDate = DateTime.tryParse(eventDateStr);
                      if (parsedDate != null) {
                        formattedDate =
                            '${parsedDate.day}/${parsedDate.month}/${parsedDate.year}';
                      }
                    }

                    // Compute individual event total revenue metrics
                    double eventRevenue = 0.0;
                    final ticketTypes =
                        event['event_ticket_types'] as List<dynamic>? ?? [];
                    for (final type in ticketTypes) {
                      final price = (type['price'] as num?)?.toDouble() ?? 0.0;
                      final sold =
                          (type['quantity_sold'] as num?)?.toInt() ?? 0;
                      eventRevenue += price * sold;
                    }

                    return _buildPayoutHistoryRow(
                      title: eventName,
                      date: formattedDate,
                      amount: 'MWK ${eventRevenue.toStringAsFixed(2)}',
                      status: eventRevenue > 0 ? 'Active Accrual' : 'No Sales',
                    );
                  }),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: events.isEmpty
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Manual sweep request dispatched to clearing engine.')),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: events.isEmpty
                        ? AppTheme.cardMidColor
                        : AppTheme.primaryColor,
                    foregroundColor:
                        events.isEmpty ? AppTheme.subTextColor : Colors.black,
                  ),
                  child: const Text('REQUEST EARLY WITHDRAWAL'),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatSubfield(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor)),
        const SizedBox(height: 4),
        Text(value,
            style: AppTheme.merri(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPayoutHistoryRow({
    required String title,
    required String date,
    required String amount,
    required String status,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.sans(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(date,
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.subTextColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount,
                  style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                status,
                style: AppTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: status == 'No Sales'
                      ? AppTheme.subTextColor
                      : AppTheme.primaryColor,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
