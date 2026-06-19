// lib/features/owner/owner_notifications_screen.dart

import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class OwnerNotificationsScreen extends StatefulWidget {
  const OwnerNotificationsScreen({super.key});

  @override
  State<OwnerNotificationsScreen> createState() =>
      _OwnerNotificationsScreenState();
}

class _OwnerNotificationsScreenState extends State<OwnerNotificationsScreen> {
  bool _ticketSales = true;
  bool _ticketScans = true;
  bool _payoutAlerts = true;
  bool _systemSecurity = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'NOTIFICATION PREFERENCES',
          style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Live Event Tracking',
            style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Stay updated on real-time transactional and door telemetry activity.',
            style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
          ),
          const SizedBox(height: 16),
          _buildSwitchCard(
            title: 'New Ticket Sales',
            subtitle:
                'Receive instant push alerts when attendees secure a ticket tier.',
            value: _ticketSales,
            onChanged: (val) => setState(() => _ticketSales = val),
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: 'Gate Ticket Scans',
            subtitle:
                'Get alerts during check-ins to monitor queue processing flow metrics.',
            value: _ticketScans,
            onChanged: (val) => setState(() => _ticketScans = val),
          ),
          const SizedBox(height: 28),
          Text(
            'Finance & Protocols',
            style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _buildSwitchCard(
            title: 'Payout Settlements',
            subtitle:
                'Get notified immediately upon blockchain ledger clearing and balance transfer completions.',
            value: _payoutAlerts,
            onChanged: (val) => setState(() => _payoutAlerts = val),
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: 'Cryptographic Integrity Triggers',
            subtitle:
                'Crucial alerts regarding dynamic steganography or signature anomalies discovered during check-in.',
            value: _systemSecurity,
            onChanged: (val) => setState(() => _systemSecurity = val),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      AppTheme.sans(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style:
                      AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppTheme.primaryColor,
            activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
