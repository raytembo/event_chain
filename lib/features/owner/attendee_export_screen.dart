// lib/features/owner/attendee_export_screen.dart
//
// Lets an Event Owner view and export the attendee list for any of their events
// as a CSV file. Each row = one approved ticket block.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../events/events_provider.dart';
import '../../shared/theme/app_theme.dart';   // ← Updated import to use shared AppTheme

class AttendeeExportScreen extends ConsumerStatefulWidget {
  const AttendeeExportScreen({super.key});

  @override
  ConsumerState createState() => _AttendeeExportScreenState();
}

class _AttendeeExportScreenState extends ConsumerState<AttendeeExportScreen> {
  String? _selectedEvent;
  List<BlockModel> _blocks = [];
  bool _exporting = false;

  void _loadBlocks(String eventName) {
    final notifier = ref.read(eventsProvider.notifier);
    setState(() {
      _selectedEvent = eventName;
      _blocks = notifier.getChain(eventName)
          .where((b) => b.index > 0)
          .toList();
    });
  }

  Future<void> _exportCsv() async {
    if (_selectedEvent == null || _blocks.isEmpty) return;

    setState(() => _exporting = true);

    final buf = StringBuffer();
    // Header
    buf.writeln('Block,TicketID,EventName,EventDate,Venue,OwnerName,OwnerID,TicketType,Price');
    for (final b in _blocks) {
      final t = b.ticket;
      buf.writeln(
        '${b.index},'
            '"${t.ticketID}",'
            '"${t.eventName}",'
            '"${t.eventDate}",'
            '"${t.venue}",'
            '"${t.ownerName}",'
            '"${t.ownerID}",'
            '"${t.ticketType}",'
            '${t.price.toStringAsFixed(2)}',
      );
    }

    final dir = await getTemporaryDirectory();
    final safeName = _selectedEvent!.replaceAll(' ', '_');
    final file = File('${dir.path}/attendees_$safeName.csv');
    await file.writeAsString(buf.toString());

    setState(() => _exporting = false);
    if (!mounted) return;

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Attendees — $_selectedEvent',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(eventsProvider);
    final eventNames = EventChainFFI.instance.listEvents();

    final accent = AppTheme.primaryColor;
    final card = AppTheme.cardColor;
    final bg = const Color(0xFF0A0A0A); // matches AppTheme _surface

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'ATTENDEE EXPORT',
          style: AppTheme.merri(
            fontSize: 18,
            color: accent,
            letterSpacing: 4,
          ),
        ),
        actions: [
          if (_blocks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _exporting
                  ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFF00C853),
                    strokeWidth: 2,
                  ),
                ),
              )
                  : IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.download, color: Color(0xFF00C853)),
                onPressed: _exportCsv,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Event picker ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              value: _selectedEvent,
              isExpanded: true,
              dropdownColor: card,
              style: AppTheme.sans(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'SELECT EVENT',
                labelStyle: AppTheme.sans(
                  color: accent,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
                filled: true,
                fillColor: AppTheme.cardMidColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent, width: 1.5),
                ),
              ),
              hint: Text(
                'Choose an event',
                style: AppTheme.sans(
                  color: AppTheme.subTextColor,
                  fontSize: 13,
                ),
              ),
              items: eventNames
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (e) {
                if (e != null) _loadBlocks(e);
              },
            ),
          ),

          // ── Stats strip ──────────────────────────────────────────────
          if (_selectedEvent != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatChip(label: 'TICKETS', value: '${_blocks.length}'),
                  const SizedBox(width: 12),
                  _StatChip(
                    label: 'TOTAL REVENUE',
                    value:
                    '\$${_blocks.fold(0.0, (s, b) => s + b.ticket.price).toStringAsFixed(2)}',
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ── List ─────────────────────────────────────────────────────
          Expanded(
            child: _blocks.isEmpty
                ? Center(
              child: Text(
                _selectedEvent == null
                    ? 'Select an event above'
                    : 'No tickets found for this event.',
                style: AppTheme.sans(
                  color: AppTheme.subTextColor,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _blocks.length,
              itemBuilder: (context, i) =>
                  _AttendeeRow(block: _blocks[i], index: i + 1),
            ),
          ),
        ],
      ),
      floatingActionButton: _blocks.isNotEmpty
          ? FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: _exporting ? null : _exportCsv,
        icon: const Icon(Icons.download),
        label: Text(
          'EXPORT CSV',
          style: AppTheme.sans(fontWeight: FontWeight.bold),
        ),
      )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AttendeeRow extends StatelessWidget {
  final BlockModel block;
  final int index;

  const _AttendeeRow({required this.block, required this.index});

  @override
  Widget build(BuildContext context) {
    final t = block.ticket;
    final typeColor = _typeColor(t.ticketType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: typeColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Row number
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withOpacity(0.08),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: AppTheme.sans(
                color: AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.ownerName,
                  style: AppTheme.sans(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${t.ownerID} · ${t.ticketType}',
                  style: AppTheme.sans(
                    color: AppTheme.subTextColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${t.price.toStringAsFixed(2)}',
                style: AppTheme.sans(
                  color: typeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'BLOCK #${block.index}',
                style: AppTheme.sans(
                  color: AppTheme.subTextColor,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    this.color = const Color(0xFF00C853),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.sans(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTheme.sans(
              color: AppTheme.subTextColor,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}