// lib/features/scanner/verification_result_screen.dart
//
// Optimized rewrite: null-safe ticket resolution, better error states,
//                    consistent styling, const constructors where possible.

import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/models/ticket_model.dart';
import '../../core/models/ticket_record.dart';
import '../../shared/theme/app_theme.dart';

class VerificationResultScreen extends StatelessWidget {
  final bool authentic;
  final String imagePath;
  final String? eventName;
  final int? blockIndex;
  final Map<String, dynamic>? supabaseTicketData;

  const VerificationResultScreen({
    super.key,
    required this.authentic,
    required this.imagePath,
    this.eventName,
    this.blockIndex,
    this.supabaseTicketData,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve ticket from FFI first, fall back to model from Supabase JSON
    final TicketModel? ticket = _resolveTicket();

    final Color color =
        authentic ? AppTheme.authenticColor : AppTheme.tamperedColor;
    final String label = authentic ? 'AUTHENTIC' : 'TAMPERED';
    final IconData icon = authentic ? Icons.verified : Icons.gpp_bad;

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: Text('Scan Result', style: AppTheme.merri(fontSize: 20)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResultBanner(color: color, label: label, icon: icon),
              const SizedBox(height: 24),
              _ScannedImage(path: imagePath),
              const SizedBox(height: 32),
              if (ticket != null) ...[
                const _SectionHeader('Ticket Details'),
                _TicketDetailCard(ticket: ticket),
              ] else if (supabaseTicketData != null) ...[
                const _SectionHeader('Database Record'),
                _RawDataCard(data: supabaseTicketData!),
              ] else ...[
                const _SectionHeader('Details'),
                _EmptyState(authentic: authentic),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'SCAN ANOTHER TICKET',
                    style: AppTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TicketModel? _resolveTicket() {
    // ── Priority 1: live FFI lookup against the local blockchain ────────────
    if (eventName != null && blockIndex != null) {
      try {
        return EventChainFFI.instance.getTicket(eventName!, blockIndex!);
      } catch (e) {
        debugPrint('[Result] FFI getTicket failed: $e');
      }
    }

    // ── Priority 2: Supabase row (from v_ticket_detail via scanner) ──────────
    //
    // FIX (Bug 3): The raw Supabase row uses snake_case keys
    // (ticket_id, owner_name, block_index, event_name, …) because it comes
    // straight from PostgREST. The old code called TicketModel.fromJson()
    // which looks for camelCase keys (ticketID, ownerName, …) — every field
    // silently resolved to '' / 0.0, producing a completely blank ticket card.
    //
    // The correct approach is TicketRecord.fromMap() (which was written for
    // exactly this snake_case shape) followed by toFFIModel() to produce a
    // TicketModel the rest of the UI can display uniformly.
    //
    // If fromMap() throws (e.g. a required field is absent or the schema
    // changed), we fall back to TicketModel.fromJson() as a best-effort so
    // at least partial data can appear, then _RawDataCard as a last resort.
    if (supabaseTicketData != null) {
      try {
        return TicketRecord.fromMap(supabaseTicketData!).toFFIModel();
      } catch (e) {
        debugPrint('[Result] TicketRecord.fromMap failed: $e');
      }
      try {
        return TicketModel.fromJson(supabaseTicketData!);
      } catch (e) {
        debugPrint('[Result] TicketModel.fromJson fallback also failed: $e');
      }
    }

    return null;
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  const _ResultBanner(
      {required this.color, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        children: [
          Icon(icon, size: 80, color: color),
          const SizedBox(height: 16),
          Text(
            label,
            style: AppTheme.merri(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannedImage extends StatelessWidget {
  final String path;
  const _ScannedImage({required this.path});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(path),
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 220,
          color: AppTheme.cardMidColor,
          child: Center(
            child: Text(
              'Image not available',
              style: AppTheme.sans(color: AppTheme.subTextColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      );
}

class _TicketDetailCard extends StatelessWidget {
  final TicketModel ticket;
  const _TicketDetailCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Ticket ID', ticket.ticketID),
      ('Event', ticket.eventName),
      ('Date', ticket.eventDate),
      ('Venue', ticket.venue),
      ('Owner', ticket.ownerName),
      ('Owner ID', ticket.ownerID),
      ('Type', ticket.ticketType),
      ('Price', '\$${ticket.price.toStringAsFixed(2)}'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children:
            rows.map((r) => _DetailRow(label: r.$1, value: r.$2)).toList(),
      ),
    );
  }
}

class _RawDataCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RawDataCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _DetailRow(
              label: e.key,
              value: e.value?.toString() ?? 'null',
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool authentic;
  const _EmptyState({required this.authentic});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        authentic
            ? 'Ticket verified, but details could not be loaded.'
            : 'No matching ticket found in any loaded event chain.',
        textAlign: TextAlign.center,
        style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.subTextColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
