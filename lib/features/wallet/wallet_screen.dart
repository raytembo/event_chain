// lib/features/wallet/wallet_screen.dart
//
// Shows purchased tickets with:
//   • Stego ticket image (loaded from stego_url in the tickets table)
//   • Download to gallery (via gal library)
//   • Share via system share sheet
//   • Event details joined from events table

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/utilities/currency_formatter.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final myTicketsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Join tickets → events so we get event_name, venue, event_date
  final res = await supabase
      .from('payments')
      .select('*, tickets(*, event:events(event_name, event_date, venue))')
      .eq('buyer_id', userId)
      .eq('status', 'completed')
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
// Wallet Card — StatefulWidget to manage download state
// ─────────────────────────────────────────────────────────────────────────────

class _WalletCard extends StatefulWidget {
  final Map<String, dynamic> payment;
  const _WalletCard({required this.payment});

  @override
  State<_WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<_WalletCard> {
  bool _isDownloading = false;

  // ── Helpers ────────────────────────────────────────────────────────────────

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
        'Dec',
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

  // ── Download to gallery via gal ────────────────────────────────────────────

  Future<void> _downloadTicket({
    required String stegoUrl,
    required String ticketId,
  }) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      // Check / request gallery permission
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Gallery permission denied.',
              style: AppTheme.sans(),
            ),
            backgroundColor: AppTheme.tamperedColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ));
          return;
        }
      }

      // Fetch image bytes from Supabase Storage public URL
      final response = await http.get(Uri.parse(stegoUrl));
      if (response.statusCode != 200) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }

      // Write to a temp file then hand off to gal
      final tempDir = await getTemporaryDirectory();
      final fileName = 'ticket_$ticketId.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      // Save to gallery (creates "EventChain Tickets" album where supported)
      await Gal.putImage(tempFile.path, album: 'EventChain Tickets');

      // Clean up temp file
      await tempFile.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Saved to gallery',
          style: AppTheme.sans(),
        ),
        backgroundColor: AppTheme.authenticColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Share',
          textColor: Colors.black,
          onPressed: () async {
            final shareFile = File(
              '${(await getTemporaryDirectory()).path}/share_$fileName',
            );
            final shareResponse = await http.get(Uri.parse(stegoUrl));
            await shareFile.writeAsBytes(shareResponse.bodyBytes);
            await Share.shareXFiles(
              [XFile(shareFile.path)],
              subject: 'My EventChain Ticket',
            );
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e', style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── Share ticket image ─────────────────────────────────────────────────────

  Future<void> _shareTicket({
    required String stegoUrl,
    required String ticketId,
    required String eventName,
  }) async {
    try {
      final response = await http.get(Uri.parse(stegoUrl));
      if (response.statusCode != 200) throw Exception('Could not fetch image');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/share_ticket_$ticketId.png');
      await file.writeAsBytes(response.bodyBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'My ticket for $eventName',
        text: 'My EventChain ticket for $eventName',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not share: $e', style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ticket = widget.payment['tickets'] as Map<String, dynamic>? ?? {};
    final eventData = ticket['event'] as Map<String, dynamic>? ?? {};

    final ticketType = ticket['ticket_type'] as String? ?? 'general';
    final typeColor = _typeColor(ticketType);

    final ticketId = ticket['ticket_id'] as String? ?? '';
    final eventName = eventData['event_name'] as String? ?? '';
    final eventDate = _formatDate(eventData['event_date']);
    final venue = eventData['venue'] as String? ?? '';
    final ownerName = ticket['owner_name'] as String? ?? 'You';
    final price = (ticket['price'] as num?)?.toDouble() ?? 0.0;
    final blockIndex = ticket['block_index'] as int? ?? 0;
    final stegoUrl = ticket['stego_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stego ticket image ───────────────────────────────────────────
          _buildTicketImage(stegoUrl, typeColor),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type badge + ticket ID
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: typeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        ticketType.toUpperCase(),
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
                      '#$ticketId',
                      style: AppTheme.sans(
                          fontSize: 12, color: AppTheme.subTextColor),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Perforation line
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
                  style:
                      AppTheme.merri(fontSize: 19, fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 8),

                // Date + Venue
                Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 15, color: AppTheme.subTextColor),
                    const SizedBox(width: 6),
                    Text(eventDate,
                        style:
                            AppTheme.sans(fontSize: 13, color: Colors.white70)),
                    const SizedBox(width: 16),
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: AppTheme.subTextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        venue,
                        style:
                            AppTheme.sans(fontSize: 13, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Owner
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 15, color: AppTheme.subTextColor),
                    const SizedBox(width: 6),
                    Text(
                      ownerName,
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.subTextColor),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Price + Block
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'MK ${formatMwk(price)}',
                      style: AppTheme.sans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: typeColor,
                      ),
                    ),
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

                const SizedBox(height: 16),

                // Divider
                Divider(color: Colors.white.withValues(alpha: 0.08)),

                const SizedBox(height: 12),

                // Download + Share buttons
                if (stegoUrl != null)
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: _isDownloading ? null : Icons.download_rounded,
                          label: _isDownloading ? 'Saving…' : 'Download',
                          color: typeColor,
                          loading: _isDownloading,
                          onTap: _isDownloading
                              ? null
                              : () => _downloadTicket(
                                    stegoUrl: stegoUrl,
                                    ticketId: ticketId,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.share_rounded,
                          label: 'Share',
                          color: typeColor,
                          outlined: true,
                          onTap: () => _shareTicket(
                            stegoUrl: stegoUrl,
                            ticketId: ticketId,
                            eventName: eventName,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Ticket image not available',
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.subTextColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stego image widget ─────────────────────────────────────────────────────

  Widget _buildTicketImage(String? stegoUrl, Color typeColor) {
    if (stegoUrl == null || stegoUrl.isEmpty) {
      return _imagePlaceholder(typeColor);
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Image.network(
        stegoUrl,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 200,
            color: const Color(0xFF1C1C1C),
            child: Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: typeColor,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _imagePlaceholder(typeColor),
      ),
    );
  }

  Widget _imagePlaceholder(Color typeColor) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        height: 120,
        color: const Color(0xFF1C1C1C),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  color: typeColor.withValues(alpha: 0.3), size: 36),
              const SizedBox(height: 8),
              Text(
                'No image available',
                style:
                    AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final bool outlined;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outlined ? color : Colors.black,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 16, color: outlined ? color : Colors.black),
        const SizedBox(width: 7),
        Text(
          label,
          style: AppTheme.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: outlined ? color : Colors.black,
          ),
        ),
      ],
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: content,
      );
    }

    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
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
            style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
