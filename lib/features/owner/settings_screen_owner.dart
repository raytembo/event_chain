// lib/features/owner/settings_screen.dart
//
// Owner-specific Settings Screen (updated to match the exact UI style you provided)
// • Clean dark UI with the same _SettingsCard design, fonts, colors, and spacing
// • ONLY options relevant to Event Owners (no general attendee/user options)
// • Profile still navigates to the shared ProfileScreen (with owner-tailored subtitle)
// • Other cards are owner-focused (payouts, notifications, etc.) with placeholder actions

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../profile/profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SETTINGS',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Owner-focused cards ───────────────────────────────────────

          _SettingsCard(
            icon: Icons.person_outline_rounded,
            title: 'Profile',
            subtitle: 'Edit your organizer name, contact details & business info',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            icon: Icons.attach_money_rounded,
            title: 'Payouts & Revenue',
            subtitle: 'View ticket earnings, manage bank details & withdrawal requests',
            onTap: () {
              // TODO: future owner payout screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payout settings coming soon')),
              );
            },
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Manage alerts for new ticket sales, scans & event updates',
            onTap: () {
              // TODO: future owner notification preferences
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notification preferences coming soon')),
              );
            },
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            subtitle: 'FAQs, contact us, or report an issue',
            onTap: () {
              // TODO: future page
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Help & Support coming soon')),
              );
            },
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            icon: Icons.info_outline_rounded,
            title: 'About EventChain',
            subtitle: 'Version • Privacy • Terms',
            onTap: () {
              // TODO: future page
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About page coming soon')),
              );
            },
          ),

          const SizedBox(height: 40),

          // Extra spacing at bottom so FAB / keyboard doesn't overlap
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Reusable settings card (exactly as you provided – matches wallet ticket card style) ─────────────────
class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.merri(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.sans(
                        fontSize: 13,
                        color: AppTheme.subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.subTextColor,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}