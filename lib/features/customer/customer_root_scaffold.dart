// lib/features/customer/customer_root_scaffold.dart
//
// UPDATED: Added Settings tab to bottom navigation
// • Third tab = SettingsScreen (full-screen, matches Wallet/Discover UI)
// • Profile editing is now reachable via Settings → Profile
// • No UI changes to existing Discover / Wallet / badge strip

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../auth/auth_provider.dart';
import '../wallet/wallet_screen.dart';
import 'customer_discover_screen.dart';
import '../settings/settings_screen.dart';     // ← new
import '../profile/profile_screen.dart';       // ← new

class CustomerRootScaffold extends ConsumerStatefulWidget {
  const CustomerRootScaffold({super.key});

  @override
  ConsumerState<CustomerRootScaffold> createState() => _CustomerRootScaffoldState();
}

class _CustomerRootScaffoldState extends ConsumerState<CustomerRootScaffold> {
  int _tab = 0;

  static const _screens = [
    CustomerDiscoverScreen(),
    WalletScreen(),
    SettingsScreen(),      // ← new third screen
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      body: _screens[_tab],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attendee badge strip (unchanged)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            color: AppTheme.primaryColor.withOpacity(0.08),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  color: AppTheme.primaryColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'ATTENDEE · ${user?.displayName ?? ''}',
                  style: AppTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppTheme.cardColor,
                        title: Text(
                          'Sign out?',
                          style: AppTheme.merri(fontSize: 18),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              'CANCEL',
                              style: AppTheme.sans(color: AppTheme.subTextColor),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              'SIGN OUT',
                              style: AppTheme.sans(
                                color: AppTheme.tamperedColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(authProvider.notifier).logout();
                    }
                  },
                  child: Text(
                    'SIGN OUT',
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: AppTheme.subTextColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom navigation (now 3 tabs)
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Discover',
              ),
              NavigationDestination(
                icon: Icon(Icons.wallet_outlined),
                selectedIcon: Icon(Icons.wallet),
                label: 'My Tickets',
              ),
              NavigationDestination(          // ← NEW SETTINGS TAB
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}