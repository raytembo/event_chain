// lib/features/wallet/wallet_screen.dart
//
// Shows purchased tickets with:
//   • Stego ticket image (loaded from stego_url in the tickets table)
//   • Download to gallery (via gal library)
//   • Share via system share sheet (Image & ZIP formats)
//   • Event details joined from events table
//   • P2P Direct Sending to local Verification Terminals via Nearby Connections

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/utilities/currency_formatter.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final myTicketsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

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
  bool _isZipping = false;

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
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gallery permission denied.', style: AppTheme.sans()),
            backgroundColor: AppTheme.tamperedColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ));
          return;
        }
      }

      final response = await http.get(Uri.parse(stegoUrl));
      if (response.statusCode != 200) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'ticket_$ticketId.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      await Gal.putImage(tempFile.path, album: 'EventChain Tickets');
      await tempFile.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to gallery', style: AppTheme.sans()),
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

  // ── Share ticket ZIP archive ───────────────────────────────────────────────

  Future<void> _shareTicketZip({
    required String stegoUrl,
    required String ticketId,
    required String eventName,
    required String eventDate,
    required String venue,
    required String ownerName,
    required String ticketType,
    required double price,
    required int blockIndex,
  }) async {
    if (_isZipping) return;
    setState(() => _isZipping = true);

    try {
      final response = await http.get(Uri.parse(stegoUrl));
      if (response.statusCode != 200) {
        throw Exception('Could not fetch image asset');
      }

      final imageBytes = response.bodyBytes;
      final archive = Archive();

      archive.addFile(
        ArchiveFile('ticket_$ticketId.png', imageBytes.length, imageBytes),
      );

      final manifestText = '''
==================================================
              EVENTCHAIN TICKET MANIFEST          
==================================================
Ticket ID:  #$ticketId
Event:      $eventName
Date:       $eventDate
Venue:      $venue
Owner:      $ownerName
Tier:       ${ticketType.toUpperCase()}
Price:      MK ${formatMwk(price)}
Block:      BLOCK #$blockIndex

Generated securely via EventChain System.
==================================================
''';
      final manifestBytes = utf8.encode(manifestText);
      archive.addFile(
        ArchiveFile('ticket_details.txt', manifestBytes.length, manifestBytes),
      );

      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes == null)
        throw Exception('Failed to generate archive structure');

      final tempDir = await getTemporaryDirectory();
      final zipFile = File('${tempDir.path}/ticket_$ticketId.zip');
      await zipFile.writeAsBytes(zipBytes);

      await Share.shareXFiles(
        [XFile(zipFile.path, mimeType: 'application/zip')],
        subject: 'EventChain Archive - $eventName',
        text:
            'Compressed asset packet containing secure ticket verification items.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ZIP bundle build failed: $e', style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } finally {
      if (mounted) setState(() => _isZipping = false);
    }
  }

  // Opens the P2P Sending Platform Interface
  void _openNearbyTransmissionSheet({
    required String stegoUrl,
    required String ticketId,
    required String eventName,
    required String eventDate,
    required String venue,
    required String ownerName,
    required String ticketType,
    required double price,
    required int blockIndex,
    required Color accentColor,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _NearbySendBottomSheet(
        stegoUrl: stegoUrl,
        ticketId: ticketId,
        eventName: eventName,
        eventDate: eventDate,
        venue: venue,
        ownerName: ownerName,
        ticketType: ticketType,
        price: price,
        blockIndex: blockIndex,
        accentColor: accentColor,
      ),
    );
  }

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
          _buildTicketImage(stegoUrl, typeColor),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(
                  eventName,
                  style:
                      AppTheme.merri(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
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
                Divider(color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 12),
                if (stegoUrl != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // High-priority ecosystem feature: Wireless delivery pipeline
                      SizedBox(
                        width: double.infinity,
                        child: _ActionButton(
                          icon: Icons.wifi_tethering_rounded,
                          label: 'SEND VIA NEARBY SHARE',
                          color: typeColor,
                          onTap: () => _openNearbyTransmissionSheet(
                            stegoUrl: stegoUrl,
                            ticketId: ticketId,
                            eventName: eventName,
                            eventDate: eventDate,
                            venue: venue,
                            ownerName: ownerName,
                            ticketType: ticketType,
                            price: price,
                            blockIndex: blockIndex,
                            accentColor: typeColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: _isDownloading
                                  ? null
                                  : Icons.download_rounded,
                              label: _isDownloading ? 'Saving…' : 'Download',
                              color: typeColor,
                              outlined: true,
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
                              label: 'Share Image',
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
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _ActionButton(
                          icon: _isZipping ? null : Icons.folder_zip_outlined,
                          label:
                              _isZipping ? 'Archiving…' : 'Share ZIP Archive',
                          color: typeColor,
                          outlined: true,
                          loading: _isZipping,
                          onTap: _isZipping
                              ? null
                              : () => _shareTicketZip(
                                    stegoUrl: stegoUrl,
                                    ticketId: ticketId,
                                    eventName: eventName,
                                    eventDate: eventDate,
                                    venue: venue,
                                    ownerName: ownerName,
                                    ticketType: ticketType,
                                    price: price,
                                    blockIndex: blockIndex,
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
// P2P Transmitter Console Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _NearbySendBottomSheet extends StatefulWidget {
  final String stegoUrl;
  final String ticketId;
  final String eventName;
  final String eventDate;
  final String venue;
  final String ownerName;
  final String ticketType;
  final double price;
  final int blockIndex;
  final Color accentColor;

  const _NearbySendBottomSheet({
    required this.stegoUrl,
    required this.ticketId,
    required this.eventName,
    required this.eventDate,
    required this.venue,
    required this.ownerName,
    required this.ticketType,
    required this.price,
    required this.blockIndex,
    required this.accentColor,
  });

  @override
  State<_NearbySendBottomSheet> createState() => _NearbySendBottomSheetState();
}

class _NearbySendBottomSheetState extends State<_NearbySendBottomSheet> {
  final List<Map<String, String>> _discoveredScanners = [];
  String _statusMessage = 'Initializing local hardware link…';
  bool _preparingBundle = true;
  bool _isConnected = false;
  bool _isSending = false;
  String? _connectedEndpointId;
  double _transmissionProgress = 0.0;
  File? _compiledPayloadFile;

  @override
  void initState() {
    super.initState();
    _assemblePackageAndDiscover();
  }

  @override
  void dispose() {
    Nearby().stopDiscovery();
    if (_connectedEndpointId != null) {
      Nearby().disconnectFromEndpoint(_connectedEndpointId!);
    }
    if (_compiledPayloadFile != null && _compiledPayloadFile!.existsSync()) {
      try {
        _compiledPayloadFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  // Requests hardware capabilities, downloads image, packs archive container
  Future<void> _assemblePackageAndDiscover() async {
    try {
      final permissionsAllowed = await [
        Permission.location,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.nearbyWifiDevices,
      ].request();

      if (!permissionsAllowed.values.every((status) => status.isGranted)) {
        setState(() {
          _preparingBundle = false;
          _statusMessage =
              'Sharing failed: Missing required hardware map permissions.';
        });
        return;
      }

      setState(
          () => _statusMessage = 'Compiling encrypted validation manifest…');

      final response = await http.get(Uri.parse(widget.stegoUrl));
      if (response.statusCode != 200)
        throw Exception('Remote asset fetch failed');

      final imageBytes = response.bodyBytes;
      final archive = Archive();

      archive.addFile(
        ArchiveFile(
            'ticket_${widget.ticketId}.png', imageBytes.length, imageBytes),
      );

      final manifestText = '''
==================================================
              EVENTCHAIN TICKET MANIFEST          
==================================================
Ticket ID:  #${widget.ticketId}
Event:      ${widget.eventName}
Date:       ${widget.eventDate}
Venue:      ${widget.venue}
Owner:      ${widget.ownerName}
Tier:       ${widget.ticketType.toUpperCase()}
Price:      MK ${formatMwk(widget.price)}
Block:      BLOCK #${widget.blockIndex}

Generated securely via EventChain System.
==================================================
''';
      final manifestBytes = utf8.encode(manifestText);
      archive.addFile(
        ArchiveFile('ticket_details.txt', manifestBytes.length, manifestBytes),
      );

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception('Archive assembly layout fault');

      final tempDir = await getTemporaryDirectory();
      _compiledPayloadFile =
          File('${tempDir.path}/p2p_trans_${widget.ticketId}.zip');
      await _compiledPayloadFile!.writeAsBytes(zipBytes);

      setState(() {
        _preparingBundle = false;
        _statusMessage = 'Searching for active validation scanners…';
      });

      await Nearby().startDiscovery(
        "Ticket_Sender_${Platform.localHostname}",
        Strategy.P2P_STAR,
        onEndpointFound: (id, name, serviceId) {
          if (!mounted) return;
          setState(() {
            if (!_discoveredScanners.any((sc) => sc['id'] == id)) {
              _discoveredScanners.add({'id': id, 'name': name});
            }
          });
        },
        onEndpointLost: (id) {
          if (!mounted) return;
          setState(() {
            _discoveredScanners.removeWhere((sc) => sc['id'] == id);
          });
        },
      );
    } catch (e) {
      setState(() {
        _preparingBundle = false;
        _statusMessage = 'Failed initialization layout sequence: $e';
      });
    }
  }

  // Handles active connection requests to tapped scanning terminals
  Future<void> _dispatchConnectionRequest(String id, String name) async {
    setState(() {
      _statusMessage = 'Requesting local uplink channel to $name…';
    });

    try {
      await Nearby().requestConnection(
        "Ticket_Sender_${Platform.localHostname}",
        id,
        onConnectionInitiated: (endpointId, info) async {
          await Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved:
                (_, __) {}, // Handled strictly as outgoing channel
            onPayloadTransferUpdate: (epId, update) {
              if (!mounted) return;
              switch (update.status) {
                case PayloadStatus.IN_PROGRESS:
                  setState(() {
                    _isSending = true;
                    _transmissionProgress =
                        update.bytesTransferred / update.totalBytes;
                    _statusMessage =
                        'Streaming bundle payload: ${(_transmissionProgress * 100).toStringAsFixed(0)}%';
                  });
                  break;
                case PayloadStatus.SUCCESS:
                  setState(() {
                    _isSending = false;
                    _statusMessage = 'Payload delivered successfully!';
                  });
                  Future.delayed(const Duration(milliseconds: 1800), () {
                    if (mounted) Navigator.pop(context);
                  });
                  break;
                case PayloadStatus.FAILURE:
                  setState(() {
                    _isSending = false;
                    _statusMessage =
                        'Transmission stream dropped by host terminal.';
                  });
                  break;
                case PayloadStatus.NONE:
                  break;
                case PayloadStatus.CANCELED:
                  // TODO: Handle this case.
                  throw UnimplementedError();
              }
            },
          );
        },
        onConnectionResult: (endpointId, status) async {
          if (status == Status.CONNECTED) {
            setState(() {
              _isConnected = true;
              _connectedEndpointId = endpointId;
              _statusMessage = 'Uplink locked. Executing pipeline stream…';
            });

            if (_compiledPayloadFile != null &&
                _compiledPayloadFile!.existsSync()) {
              await Nearby()
                  .sendFilePayload(endpointId, _compiledPayloadFile!.path);
            } else {
              setState(
                  () => _statusMessage = 'Payload container generation error.');
            }
          } else {
            setState(() =>
                _statusMessage = 'Uplink connection rejected by terminal.');
          }
        },
        onDisconnected: (endpointId) {
          if (!mounted) return;
          setState(() {
            _isConnected = false;
            _isSending = false;
            _connectedEndpointId = null;
            _statusMessage = 'Disconnected. Searching for endpoints…';
          });
        },
      );
    } catch (e) {
      setState(() =>
          _statusMessage = 'Failed routing connection payload parameters: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEARBY WIRELESS EMIT',
                style: AppTheme.merri(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: AppTheme.subTextColor, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            style: AppTheme.sans(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          if (_preparingBundle || _isConnected || _isSending) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: LinearProgressIndicator(
                  value: _isSending ? _transmissionProgress : null,
                  color: widget.accentColor,
                  backgroundColor: Colors.white10,
                ),
              ),
            )
          ] else ...[
            Text(
              'AVAILABLE SCANNERS',
              style: AppTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: _discoveredScanners.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Waiting for gate terminal to launch discovery server…',
                          textAlign: TextAlign.center,
                          style: AppTheme.sans(
                              fontSize: 12, color: AppTheme.subTextColor),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _discoveredScanners.length,
                      separatorBuilder: (_, __) => Divider(
                          color: Colors.white.withValues(alpha: 0.05),
                          height: 1),
                      itemBuilder: (context, idx) {
                        final scanner = _discoveredScanners[idx];
                        return ListTile(
                          leading: Icon(Icons.pin_drop_rounded,
                              color: widget.accentColor),
                          title: Text(
                            scanner['name'] ?? 'Unknown Hardware Gateway',
                            style: AppTheme.sans(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded,
                              size: 14, color: Colors.white30),
                          onTap: () => _dispatchConnectionRequest(
                              scanner['id']!, scanner['name']!),
                        );
                      },
                    ),
            )
          ]
        ],
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
        if (icon != null || loading) const SizedBox(width: 7),
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
