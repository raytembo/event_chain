// lib/features/scanner/verification_result_screen.dart
//
// Supports three scan outcomes: VALID, INVALID, and ALREADY SCANNED.
// The alreadyScanned flag (set by the duplicate-scan guard in scanner_screen)
// drives a distinct orange warning state without affecting the authentic flag.

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

  /// True when the ticket passed cryptographic verification but was already
  /// stamped in a previous scan session. The scanner_screen sets this and
  /// merges the original scanned_at timestamp into supabaseTicketData.
  final bool alreadyScanned;

  const VerificationResultScreen({
    super.key,
    required this.authentic,
    required this.imagePath,
    this.eventName,
    this.blockIndex,
    this.supabaseTicketData,
    this.alreadyScanned = false,
  });

  // ── Timestamp helper ────────────────────────────────────────────────────

  /// Converts an ISO-8601 UTC string into a human-readable local time string.
  static String _formatTimestamp(String iso8601) {
    try {
      final dt = DateTime.parse(iso8601).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return '$d/$mo/${dt.year} at $h:$m';
    } catch (_) {
      return iso8601;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TicketModel? ticket = _resolveTicket();

    // ── Resolve banner state ───────────────────────────────────────────────
    final Color color;
    final String label;
    final IconData icon;
    final String? bannerSubtitle;

    if (alreadyScanned) {
      color = Colors.orange;
      label = 'ALREADY SCANNED';
      icon = Icons.warning_amber_rounded;
      final ts = supabaseTicketData?['scanned_at'] as String?;
      bannerSubtitle =
          ts != null ? 'First used on ${_formatTimestamp(ts)}' : null;
    } else if (authentic) {
      color = AppTheme.authenticColor;
      label = 'VALID TICKET';
      icon = Icons.verified;
      final ts = supabaseTicketData?['scanned_at'] as String?;
      bannerSubtitle =
          ts != null ? 'Admitted on ${_formatTimestamp(ts)}' : null;
    } else {
      color = AppTheme.tamperedColor;
      label = 'INVALID TICKET';
      icon = Icons.gpp_bad;
      bannerSubtitle = null;
    }

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
              _ResultBanner(
                color: color,
                label: label,
                icon: icon,
                subtitle: bannerSubtitle,
              ),
              const SizedBox(height: 24),
              _ScannedImage(path: imagePath),
              const SizedBox(height: 32),
              if (ticket != null) ...[
                const _SectionHeader('Ticket Details'),
                _TicketDetailCard(ticket: ticket),
              ] else if (supabaseTicketData != null) ...[
                const _SectionHeader('System Record'),
                _RawDataCard(data: supabaseTicketData!),
              ] else ...[
                const _SectionHeader('Information'),
                _EmptyState(
                  authentic: authentic,
                  alreadyScanned: alreadyScanned,
                ),
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
    if (eventName != null && blockIndex != null) {
      try {
        return EventChainFFI.instance.getTicket(eventName!, blockIndex!);
      } catch (e) {
        debugPrint('[Result] FFI getTicket failed: $e');
      }
    }

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

  /// Optional line shown below the label — used for timestamps.
  final String? subtitle;

  const _ResultBanner({
    required this.color,
    required this.label,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
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
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                fontSize: 13,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
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
      ('Ticket Holder', ticket.ownerName),
      ('Holder ID', ticket.ownerID),
      ('Tier Type', ticket.ticketType),
      ('Price', 'MWK ${ticket.price.toStringAsFixed(2)}'),
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
  final bool alreadyScanned;
  const _EmptyState({required this.authentic, required this.alreadyScanned});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (alreadyScanned) {
      message =
          'This ticket has already been used for entry and cannot be admitted again.';
    } else if (authentic) {
      message =
          'The ticket is valid, but its individual data records could not be read.';
    } else {
      message =
          'This ticket could not be found or verified in our system listings.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
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
