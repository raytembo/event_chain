// lib/features/settings/about_screen.dart

import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dark().scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ABOUT EVENTCHAIN',
          style: AppTheme.merri(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),

          // App Visual Anchor Shield (Matches cryptographic focus)
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.link,
                color: AppTheme.primaryColor,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              'EventChain',
              style: AppTheme.merri(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Version 1.0.0',
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
            ),
          ),
          const SizedBox(height: 40),

          Text(
            'Our Mission',
            style: AppTheme.merri(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'EventChain eliminates secondary ticket fraud and illegal scalping networks. By reinforcing ticket allocations with localized steganography patterns and public ledger smart state routing, we guarantee transparent verification pipelines directly from hosts to real attendees.',
            style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
          ),
          const SizedBox(height: 40),

          const Divider(),
          _buildLegalRow(
            context,
            title: 'Privacy Policy',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Loading Privacy Policy...')),
              );
            },
          ),
          const Divider(),
          _buildLegalRow(
            context,
            title: 'Terms of Service',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Loading Terms of Service...')),
              );
            },
          ),
          const Divider(),
          _buildLegalRow(
            context,
            title: 'Open Source Licenses',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'EventChain',
                applicationVersion: '1.0.0',
              );
            },
          ),
          const Divider(),

          const SizedBox(height: 60),
          Center(
            child: Text(
              '© 2026 EventChain Inc. All rights reserved.',
              style: AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalRow(BuildContext context,
      {required String title, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      title: Text(
        title,
        style: AppTheme.sans(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        color: AppTheme.subTextColor,
        size: 14,
      ),
      onTap: onTap,
    );
  }
}
