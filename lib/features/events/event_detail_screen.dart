// lib/features/events/event_detail_screen.dart
//
// Shows an owner's event: chain integrity status, all issued tickets, and the
// button to issue more. Handles ticket sharing as PNG or BMP.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../../core/services/supabase_storage_service.dart';
import '../../shared/theme/app_theme.dart';
import 'events_provider.dart';
import 'create_ticket_screen.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventName;
  final String eventId;
  final String posterUrl;
  final String? venue;

  /// Raw ISO-8601 timestamptz string from events.event_date.
  /// Displayed as a formatted date; also passed to CreateTicketScreen for the
  /// steganographic payload.
  final String? eventDate;
  final double? latitude;
  final double? longitude;

  const EventDetailScreen({
    super.key,
    required this.eventName,
    required this.eventId,
    required this.posterUrl,
    this.venue,
    this.eventDate,
    this.latitude,
    this.longitude,
  });

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _checking = false;
  bool? _chainOk;
  List<BlockModel> _blocks = [];

  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  void _loadBlocks() {
    setState(() {
      _blocks = ref.read(eventsProvider.notifier).getChain(widget.eventName);
    });
  }

  Future<void> _checkChain() async {
    setState(() {
      _checking = true;
      _chainOk = null;
    });
    final ok =
        await ref.read(eventsProvider.notifier).validateEvent(widget.eventName);
    setState(() {
      _checking = false;
      _chainOk = ok;
    });
  }

  // ── Sharing ────────────────────────────────────────────────────────────────

  /// Share a ticket as PNG — tries the already-uploaded cloud copy first.
  Future<void> _shareTicket(BlockModel block) async {
    final tempDir = await getTemporaryDirectory();
    _showBrief('Preparing your ticket image…');

    // storageIndex is 1-based (ticket_1, ticket_2, …).
    final storageIndex = block.index + 1;
    final localPath =
        await SupabaseStorageService.instance.downloadStegoTicketToTemp(
      eventId: widget.eventId,
      blockIndex: storageIndex,
      tempDir: tempDir.path,
    );

    final sharePath =
        localPath ?? '${tempDir.path}/stego_${block.ticket.ticketID}.png';
    if (localPath == null) {
      // Re-embed locally as a fallback.
      await EventChainFFI.instance.embedTicket(
        eventName: widget.eventName,
        blockIndex: block.index, // 0-based for FFI
        stegoPath: sharePath,
      );
    }

    if (!mounted) return;
    if (await File(sharePath).exists()) {
      await Share.shareXFiles(
        [XFile(sharePath)],
        subject: 'Your ticket: ${block.ticket.eventName}',
      );
    } else {
      _showBrief('Could not prepare the ticket image.');
    }
  }

  /// Share as a specific format (PNG or BMP).
  Future<void> _shareTicketAsFormat(BlockModel block, int format) async {
    final tempDir = await getTemporaryDirectory();
    _showBrief('Preparing your ticket…');

    final ext = format == ImageFormat.bmp ? 'bmp' : 'png';
    final outputPath = '${tempDir.path}/stego_${block.ticket.ticketID}.$ext';

    // For PNG, prefer the cloud copy.
    if (format == ImageFormat.png) {
      final localPath =
          await SupabaseStorageService.instance.downloadStegoTicketToTemp(
        eventId: widget.eventId,
        blockIndex: block.index + 1, // 1-based storage path
        tempDir: tempDir.path,
      );
      if (localPath != null && await File(localPath).exists()) {
        if (!mounted) return;
        await Share.shareXFiles(
          [XFile(localPath)],
          subject: 'Your ${block.ticket.eventName} ticket (PNG)',
        );
        return;
      }
    }

    // BMP or PNG fallback: re-embed via C++.
    final ok = await EventChainFFI.instance.embedTicket(
      eventName: widget.eventName,
      blockIndex: block.index, // 0-based for FFI
      stegoPath: outputPath,
    );

    if (!mounted) return;
    if (ok && await File(outputPath).exists()) {
      await Share.shareXFiles(
        [XFile(outputPath)],
        subject: 'Your ${block.ticket.eventName} ticket (${ext.toUpperCase()})',
      );
    } else {
      _showBrief('Could not prepare the ticket image.');
    }
  }

  void _showBrief(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTheme.sans(fontSize: 13)),
      backgroundColor: AppTheme.cardColor,
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
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
      ];
      return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Skip genesis block (index 0) — it has no ticket data.
    final tickets = _blocks.where((b) => b.index > 0).toList();

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: Text(
          widget.eventName,
          style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.dividerColor),
        ),
        actions: [
          if (_checking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primaryColor),
              ),
            )
          else
            IconButton(
              tooltip: 'Check ticket integrity',
              icon: Icon(
                _chainOk == null
                    ? Icons.shield_outlined
                    : _chainOk!
                        ? Icons.shield
                        : Icons.shield_moon,
                color: _chainOk == null
                    ? Colors.white
                    : _chainOk!
                        ? AppTheme.authenticColor
                        : AppTheme.tamperedColor,
              ),
              onPressed: _checkChain,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTicketScreen(
              prefillEventName: widget.eventName,
              eventId: widget.eventId,
              posterUrl: widget.posterUrl,
              prefillVenue: widget.venue,
              prefillEventDate: widget.eventDate,
            ),
          ),
        ).then((_) => _loadBlocks()),
        icon: const Icon(Icons.add),
        label: Text(
          'Issue Ticket',
          style: AppTheme.sans(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
        ),
      ),
      body: Column(
        children: [
          // ── Poster ──────────────────────────────────────────────────────
          if (widget.posterUrl.isNotEmpty)
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.posterUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.cardColor.withValues(alpha: 0.8)
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Chain integrity banner ───────────────────────────────────────
          if (_chainOk != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: double.infinity,
              color:
                  _chainOk! ? AppTheme.authenticColor : AppTheme.tamperedColor,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _chainOk!
                        ? Icons.verified_outlined
                        : Icons.warning_amber_rounded,
                    color: Colors.black,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _chainOk!
                        ? 'All tickets are genuine — nothing has been tampered with'
                        : 'Warning: ticket data may have been altered',
                    style: AppTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),

          // ── Stats row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _StatChip(value: '${_blocks.length}', label: 'BLOCKS'),
                const SizedBox(width: 12),
                _StatChip(value: '${tickets.length}', label: 'TICKETS ISSUED'),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Event info ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 14, color: AppTheme.subTextColor),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(widget.eventDate),
                      style: AppTheme.sans(fontSize: 13),
                    ),
                    const Spacer(),
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppTheme.subTextColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.venue ?? 'No venue set',
                        style: AppTheme.sans(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // ── Mini map (only when coordinates are available) ─────────
                if (widget.latitude != null && widget.longitude != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 140,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter:
                              LatLng(widget.latitude!, widget.longitude!),
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.eventchain',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point:
                                    LatLng(widget.latitude!, widget.longitude!),
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Color(0xFFFF1744),
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Ticket list ──────────────────────────────────────────────────
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.confirmation_number_outlined,
                            size: 48, color: AppTheme.subTextColor),
                        const SizedBox(height: 16),
                        Text('No tickets yet.',
                            style: AppTheme.merri(
                                fontSize: 16, color: AppTheme.subTextColor)),
                        const SizedBox(height: 4),
                        Text('Tap "Issue Ticket" to create the first one.',
                            style: AppTheme.sans(
                                fontSize: 13, color: AppTheme.subTextColor)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: tickets.length,
                    itemBuilder: (_, i) => _TicketCard(
                      block: tickets[i],
                      onShare: () => _shareTicket(tickets[i]),
                      onShareAsFormat: (fmt) =>
                          _shareTicketAsFormat(tickets[i], fmt),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatChip
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardMidColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: AppTheme.merri(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTheme.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: AppTheme.subTextColor)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _TicketCard
// ─────────────────────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final BlockModel block;
  final VoidCallback onShare;
  final ValueChanged<int> onShareAsFormat;

  const _TicketCard({
    required this.block,
    required this.onShare,
    required this.onShareAsFormat,
  });

  Color _typeColor(String type) => switch (type.toLowerCase()) {
        'vip' => const Color(0xFFFFD700),
        'backstage' => const Color(0xFFFF6D00),
        'student' => const Color(0xFF69F0AE),
        _ => AppTheme.primaryColor,
      };

  void _showFormatMenu(
      BuildContext context, ValueChanged<int> onShareAsFormat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share Ticket As',
                  style: AppTheme.merri(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Only lossless formats work — compressed formats destroy the hidden data.',
                style:
                    AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
              ),
              const SizedBox(height: 16),
              _FormatOption(
                icon: Icons.image_outlined,
                label: 'PNG (Recommended)',
                subtitle:
                    'Lossless · preserves hidden data · smallest file size',
                onTap: () {
                  Navigator.pop(ctx);
                  onShareAsFormat(ImageFormat.png);
                },
              ),
              _FormatOption(
                icon: Icons.image,
                label: 'BMP',
                subtitle: 'Lossless · uncompressed · larger file size',
                onTap: () {
                  Navigator.pop(ctx);
                  onShareAsFormat(ImageFormat.bmp);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = block.ticket;
    final typeColor = _typeColor(t.ticketType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colour accent bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: typeColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      t.ticketType.toUpperCase(),
                      style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: typeColor),
                    ),
                    const Spacer(),
                    Text('BLOCK #${block.index}',
                        style: AppTheme.sans(
                            fontSize: 11, color: AppTheme.subTextColor)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(t.eventName,
                    style: AppTheme.merri(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppTheme.subTextColor),
                    const SizedBox(width: 4),
                    Text(t.eventDate,
                        style: AppTheme.sans(
                            fontSize: 12, color: AppTheme.subTextColor)),
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: AppTheme.subTextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(t.venue,
                          style: AppTheme.sans(
                              fontSize: 12, color: AppTheme.subTextColor),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 13, color: AppTheme.subTextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        t.ownerName,
                        style: AppTheme.sans(
                            fontSize: 11, color: AppTheme.subTextColor),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MWK ${t.price.toStringAsFixed(2)}',
                      style: AppTheme.merri(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _showFormatMenu(context, onShareAsFormat),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: typeColor,
                            side: BorderSide(
                                color: typeColor.withValues(alpha: 0.7)),
                            backgroundColor: typeColor.withValues(alpha: 0.07),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child:
                              Icon(Icons.more_vert, size: 16, color: typeColor),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: onShare,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: typeColor,
                            side: BorderSide(
                                color: typeColor.withValues(alpha: 0.7)),
                            backgroundColor: typeColor.withValues(alpha: 0.07),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: Text(
                            'SHARE',
                            style: AppTheme.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: typeColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FormatOption
// ─────────────────────────────────────────────────────────────────────────────
class _FormatOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _FormatOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(label,
            style: AppTheme.sans(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor)),
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
      );
}
