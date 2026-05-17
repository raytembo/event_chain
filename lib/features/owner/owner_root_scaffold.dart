// lib/features/owner/owner_root_scaffold.dart
//
// Navigation shell shown to Event Owners after login.
// Tabs: Events (manage) | Scanner (gate verify) | Export (attendee list) | Settings
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../events/events_screen.dart';
import '../scanner/scanner_screen.dart';
import 'attendee_export_screen.dart';
import 'settings_screen_owner.dart';                     // ← New settings screen
import '../auth/auth_provider.dart';
import '../../shared/theme/app_theme.dart';       // ← Updated import to use shared AppTheme

class OwnerRootScaffold extends ConsumerStatefulWidget {
  const OwnerRootScaffold({super.key});

  @override
  ConsumerState createState() => _OwnerRootScaffoldState();
}

class _OwnerRootScaffoldState extends ConsumerState<OwnerRootScaffold> {
  int _tab = 0;

  static const _screens = [
    EventsScreen(),
    ScannerScreen(),
    AttendeeExportScreen(),
    SettingsScreen(),          // ← 4th tab added
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      body: _screens[_tab],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Owner badge strip (kept role-specific purple accent)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            color: const Color(0xFF7C4DFF).withOpacity(0.12),
            child: Row(
              children: [
                const Icon(Icons.manage_accounts, color: Color(0xFF7C4DFF), size: 14),
                const SizedBox(width: 6),
                Text(
                  'OWNER · ${user?.displayName ?? ''}',
                  style: AppTheme.sans(
                    color: const Color(0xFF7C4DFF),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppTheme.cardColor,
                        title: Text(
                          'Sign out?',
                          style: AppTheme.merri(color: Colors.white),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              'CANCEL',
                              style: AppTheme.sans(color: Colors.white54),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              'SIGN OUT',
                              style: AppTheme.sans(color: const Color(0xFFFF1744)),
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
                      color: Colors.white24,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Navigation bar now has 4 tabs (Settings button added)
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.event_outlined),
                selectedIcon: Icon(Icons.event),
                label: 'Events',
              ),
              NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: Icon(Icons.qr_code_scanner),
                label: 'Scanner',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download),
                label: 'Export',
              ),
              NavigationDestination(          // ← New Settings button/tab
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