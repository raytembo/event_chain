// lib/features/events/event_detail_screen.dart
//
// Shows an owner's event: chain integrity status, all issued tickets, and the
// button to issue more. Handles ticket sharing as PNG or BMP zip.

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:gal/gal.dart';
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

/// Formats an ISO-8601 string into a human-readable local date format.
String _formatDate(String? raw) {
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

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventName;
  final String eventId;
  final String posterUrl;
  final String? venue;

  /// Raw ISO-8601 timestamptz string from events.event_date.
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

  Future<void> _shareTicket(BlockModel block) async {
    final tempDir = await getTemporaryDirectory();
    _showBrief('Getting your ticket ready…');

    final storageIndex = block.index + 1;
    final localPath =
        await SupabaseStorageService.instance.downloadStegoTicketToTemp(
      eventId: widget.eventId,
      blockIndex: storageIndex,
      tempDir: tempDir.path,
    );

    final imagePath =
        localPath ?? '${tempDir.path}/stego_${block.ticket.ticketID}.png';

    if (localPath == null) {
      await EventChainFFI.instance.embedTicket(
        eventName: widget.eventName,
        blockIndex: block.index,
        stegoPath: imagePath,
      );
    }

    if (!mounted) return;
    if (!await File(imagePath).exists()) {
      _showBrief('Could not prepare the ticket. Please try again.');
      return;
    }

    await _shareAsZip(imagePath, block);
  }

  Future<void> _shareTicketAsFormat(BlockModel block, int format) async {
    final tempDir = await getTemporaryDirectory();
    _showBrief('Getting your ticket ready…');

    final ext = format == ImageFormat.bmp ? 'bmp' : 'png';
    final outputPath = '${tempDir.path}/stego_${block.ticket.ticketID}.$ext';

    if (format == ImageFormat.png) {
      final localPath =
          await SupabaseStorageService.instance.downloadStegoTicketToTemp(
        eventId: widget.eventId,
        blockIndex: block.index + 1,
        tempDir: tempDir.path,
      );
      if (localPath != null && await File(localPath).exists()) {
        if (!mounted) return;
        await _shareAsZip(localPath, block, ext: 'png');
        return;
      }
    }

    final ok = await EventChainFFI.instance.embedTicket(
      eventName: widget.eventName,
      blockIndex: block.index,
      stegoPath: outputPath,
    );

    if (!mounted) return;
    if (ok && await File(outputPath).exists()) {
      await _shareAsZip(outputPath, block, ext: ext);
    } else {
      _showBrief('Could not prepare the ticket. Please try again.');
    }
  }

  Future<void> _shareAsZip(String imagePath, BlockModel block,
      {String ext = 'png'}) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final safeName =
          block.ticket.eventName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileNameInZip = 'ticket_$safeName.$ext';

      final archive = Archive();
      archive
          .addFile(ArchiveFile(fileNameInZip, imageBytes.length, imageBytes));

      final zipBytes = ZipEncoder().encode(archive);
      final tempDir = await getTemporaryDirectory();
      final zipPath = '${tempDir.path}/ticket_${block.ticket.ticketID}.zip';
      await File(zipPath).writeAsBytes(zipBytes);

      await Share.shareXFiles(
        [XFile(zipPath, mimeType: 'application/zip')],
        subject: 'Ticket: ${block.ticket.eventName}',
      );
    } catch (e) {
      if (mounted) _showBrief('Could not share. Please try again.');
    }
  }

  Future<void> _saveToGallery(BlockModel block) async {
    final tempDir = await getTemporaryDirectory();
    _showBrief('Saving ticket to your gallery…');

    final storageIndex = block.index + 1;
    final localPath =
        await SupabaseStorageService.instance.downloadStegoTicketToTemp(
      eventId: widget.eventId,
      blockIndex: storageIndex,
      tempDir: tempDir.path,
    );

    String? imagePath = localPath;

    if (imagePath == null) {
      final fallbackPath = '${tempDir.path}/stego_${block.ticket.ticketID}.png';
      await EventChainFFI.instance.embedTicket(
        eventName: widget.eventName,
        blockIndex: block.index,
        stegoPath: fallbackPath,
      );
      imagePath = fallbackPath;
    }

    if (!mounted) return;
    if (!await File(imagePath).exists()) {
      _showBrief('Could not prepare the ticket. Please try again.');
      return;
    }

    try {
      String pathToSave = imagePath;
      final lower = imagePath.toLowerCase();
      if (!lower.endsWith('.png') &&
          !lower.endsWith('.jpg') &&
          !lower.endsWith('.jpeg')) {
        final newPath =
            '${tempDir.path}/ticket_${DateTime.now().millisecondsSinceEpoch}.png';
        pathToSave = (await File(imagePath).copy(newPath)).path;
      }

      await Gal.putImage(pathToSave, album: 'EventChain');
      if (mounted) _showBrief('Saved to "EventChain" in your gallery!');
    } on GalException catch (e) {
      if (mounted) _showBrief('Could not save: ${e.type}');
    } catch (e) {
      if (mounted) _showBrief('Could not save. Please try again.');
    }
  }

  void _showBrief(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTheme.sans(fontSize: 13)),
      backgroundColor: AppTheme.cardColor,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Skip genesis block (index 0) — it holds no ticket data.
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
          'New Ticket',
          style: AppTheme.sans(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Collapsible Header Information ─────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster image
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
                                AppTheme.cardColor.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Integrity banner
                if (_chainOk != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    color: _chainOk!
                        ? AppTheme.authenticColor
                        : AppTheme.tamperedColor,
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
                        Flexible(
                          child: Text(
                            _chainOk!
                                ? 'All tickets are genuine'
                                : 'Warning: some tickets may be altered',
                            style: AppTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Stats row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      _StatChip(value: '${_blocks.length}', label: 'BLOCKS'),
                      const SizedBox(width: 12),
                      _StatChip(value: '${tickets.length}', label: 'TICKETS'),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Event info & Mini Map
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      if (widget.latitude != null &&
                          widget.longitude != null) ...[
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
                                  userAgentPackageName:
                                      'com.example.eventchain',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: LatLng(
                                          widget.latitude!, widget.longitude!),
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
              ],
            ),
          ),

          // ── Ticket List Content ────────────────────────────────────────────
          if (tickets.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        size: 48, color: AppTheme.subTextColor),
                    const SizedBox(height: 16),
                    Text('No tickets yet',
                        style: AppTheme.merri(
                            fontSize: 16, color: AppTheme.subTextColor)),
                    const SizedBox(height: 4),
                    Text('Tap "New Ticket" to get started.',
                        style: AppTheme.sans(
                            fontSize: 13, color: AppTheme.subTextColor)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              // Generous bottom padding gives cards clear clearance over the FAB while scrolling
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _TicketCard(
                    block: tickets[index],
                    onShare: () => _shareTicket(tickets[index]),
                    onShareAsFormat: (fmt) =>
                        _shareTicketAsFormat(tickets[index], fmt),
                    onSaveToGallery: () => _saveToGallery(tickets[index]),
                  ),
                  childCount: tickets.length,
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
  final VoidCallback onSaveToGallery;

  const _TicketCard({
    required this.block,
    required this.onShare,
    required this.onShareAsFormat,
    required this.onSaveToGallery,
  });

  Color _typeColor(String type) => switch (type.toLowerCase()) {
        'vip' => const Color(0xFFFFD700),
        'backstage' => const Color(0xFFFF6D00),
        'student' => const Color(0xFF69F0AE),
        _ => AppTheme.primaryColor,
      };

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket Options',
                  style: AppTheme.merri(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Choose how to save or share this ticket.',
                style:
                    AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
              ),
              const SizedBox(height: 16),
              _FormatOption(
                icon: Icons.save_alt_outlined,
                label: 'Save to Gallery',
                subtitle: 'Saves image to the "EventChain" album on your phone',
                onTap: () {
                  Navigator.pop(ctx);
                  onSaveToGallery();
                },
              ),
              const Divider(height: 24),
              _FormatOption(
                icon: Icons.image_outlined,
                label: 'Share as PNG',
                subtitle: 'Smaller file · sent as a zip',
                onTap: () {
                  Navigator.pop(ctx);
                  onShareAsFormat(ImageFormat.png);
                },
              ),
              _FormatOption(
                icon: Icons.image,
                label: 'Share as BMP',
                subtitle: 'Larger file · sent as a zip',
                onTap: () {
                  Navigator.pop(ctx);
                  onShareAsFormat(ImageFormat.bmp);
                },
              ),
              const SizedBox(height: 8),
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppTheme.subTextColor),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(t.eventDate),
                      style: AppTheme.sans(
                          fontSize: 12, color: AppTheme.subTextColor),
                    ),
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
                const SizedBox(height: 4),
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
                Text(
                  'MWK ${t.price.toStringAsFixed(2)}',
                  style: AppTheme.merri(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => _showOptionsMenu(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: typeColor,
                        side:
                            BorderSide(color: typeColor.withValues(alpha: 0.7)),
                        backgroundColor: typeColor.withValues(alpha: 0.07),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Icon(Icons.more_vert, size: 16, color: typeColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
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
