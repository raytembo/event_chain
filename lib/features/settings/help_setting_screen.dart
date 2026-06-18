// lib/features/settings/help_support_screen.dart

import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'HELP & SUPPORT',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Frequently Asked Questions',
            style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _buildFaqTile(
            title: 'How does EventChain secure my tickets?',
            content:
                'EventChain utilizes an advanced hybrid ledger architecture alongside cryptographic steganography. Every ticket asset contains a hidden, untamperable verification layer that directly cross-checks authenticity against the blockchain infrastructure backend.',
          ),
          const SizedBox(height: 12),
          _buildFaqTile(
            title: 'What should I do if a ticket status says "TAMPERED"?',
            content:
                'If the cryptographic signature fails verification or the underlying digital steganographic watermark is broken, the application triggers a red "TAMPERED" notification. Do not attempt to purchase, trade, or accept ownership of these assets.',
          ),
          const SizedBox(height: 12),
          _buildFaqTile(
            title: 'How do I securely transfer asset ownership?',
            content:
                'Head over to your Wallet terminal, choose your active item, and tap "Transfer". Input the target EventChain wallet routing ID to safely re-sign the ticket keys to the new recipient.',
          ),
          const SizedBox(height: 36),
          Text(
            'Still Need Assistance?',
            style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.mail_outline_rounded,
            title: 'Contact Technical Support',
            subtitle: 'support@eventchain.io',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening email client...')),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildContactCard(
            icon: Icons.bug_report_outlined,
            title: 'Report an Integrity Issue',
            subtitle: 'Submit diagnostic security/bug logs',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Opening ticket submission system...')),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildFaqTile({required String title, required String content}) {
    return Theme(
      data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          collapsedIconColor: AppTheme.subTextColor,
          iconColor: AppTheme.primaryColor,
          title: Text(
            title,
            style: AppTheme.merri(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Text(
                content,
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.subTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.cardMidColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.sans(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.sans(
                          fontSize: 12, color: AppTheme.subTextColor),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.subTextColor,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
