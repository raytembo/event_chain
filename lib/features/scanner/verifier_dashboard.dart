// lib/features/scanner/verifier_dashboard_screen.dart

import 'package:eventchain/features/scanner/verifier_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../auth/auth_provider.dart';
import 'scanner_screen.dart';

class VerifierDashboardScreen extends ConsumerWidget {
  const VerifierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userEmail = authState.user?.email ?? 'Unknown Staff';
    final eventsAsync = ref.watch(verifierAssignedEventsProvider);

    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'GATE TERMINAL',
          style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppTheme.subTextColor,
              size: 22,
            ),
            tooltip: 'Log Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppTheme.cardColor,
                  title: Text(
                    'Log Out',
                    style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1),
                  ),
                  content: Text(
                    'Are you sure you want to log out',
                    style: AppTheme.sans(
                        fontSize: 13, color: AppTheme.subTextColor),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'CANCEL',
                        style: AppTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.subTextColor),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'LOG OUT',
                        style: AppTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(authProvider.notifier).logout();
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // ignore: unused_result
          await ref.refresh(verifierAssignedEventsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Identity Node
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded,
                      color: AppTheme.primaryColor, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AUTHORIZED PERSONNEL',
                          style: AppTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                              letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userEmail,
                          style: AppTheme.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            Text(
              'Your Assigned Events',
              style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            eventsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardMidColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Could not load your assigned events. Pull down to retry.',
                  style:
                      AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                ),
              ),
              data: (events) {
                if (events.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.cardMidColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'No events assigned yet. Ask your event owner to authorize you.',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.subTextColor),
                    ),
                  );
                }
                return Column(
                  children: events
                      .map((e) => _buildAuthorizedEventCard(
                            e['event_name'] as String? ?? 'Untitled Event',
                            _formatEventDate(e['event_date'] as String?),
                          ))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 48),

            // Scanner Launch Action
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      AppTheme.primaryColor.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: eventsAsync.maybeWhen(
                  data: (events) => events.isEmpty
                      ? null
                      : () => _launchScanner(context, events),
                  orElse: () => null,
                ),
                icon: const Icon(Icons.document_scanner_rounded, size: 28),
                label: Text(
                  'LAUNCH VERIFICATION SCANNER',
                  style: AppTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: Text(
                eventsAsync.maybeWhen(
                  data: (events) => events.isEmpty
                      ? 'Assign yourself to an event to enable scanning.'
                      : 'Ready when you are.',
                  orElse: () =>
                      'Awaiting peer-to-peer payload transfers or local file selection.',
                ),
                style:
                    AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launchScanner(BuildContext context, List<Map<String, dynamic>> events) {
    final eventNames = events
        .map((e) => e['event_name'] as String?)
        .whereType<String>()
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(),
      ),
    );
  }

  static String _formatEventDate(String? iso) {
    if (iso == null) return 'Date TBA';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $h:$m';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildAuthorizedEventCard(String title, String date) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.sans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(date,
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.subTextColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
