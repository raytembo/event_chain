// lib/features/scanner/scanner_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart'; // Handles ZIP decoding
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../shared/theme/app_theme.dart';
import '../auth/auth_provider.dart'; // Added to access logged-in scanner profile info
import '../events/events_provider.dart';
import 'verification_result_screen.dart';

// ── Structured errors ─────────────────────────────────────────────────────

sealed class ScanError implements Exception {
  final String message;
  const ScanError(this.message);
  @override
  String toString() => message;
}

final class ImageReadError extends ScanError {
  const ImageReadError(super.message);
}

final class ZipExtractError extends ScanError {
  const ZipExtractError(super.message);
}

final class NoChainsError extends ScanError {
  const NoChainsError() : super('No event details available.');
}

final class VerificationInterrupted extends ScanError {
  const VerificationInterrupted() : super('Scan interrupted.');
}

// ── Auto-delete file helper ───────────────────────────────────────────────

class _AutoDeleteFile {
  final String path;
  bool _deleted = false;

  _AutoDeleteFile(this.path);

  void dispose() {
    if (_deleted) return;
    _deleted = true;
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  bool _scanning = false;
  String _statusMessage = '';
  Future<void>? _pendingScan;

  // Nearby Connections P2P State
  bool _isAdvertising = false;
  String? _connectedEndpointId;

  // Cache to map a framework payload transfer ID directly to its temporary file URI
  final Map<int, String> _incomingFileUris = {};

  @override
  void initState() {
    super.initState();
    // Kick off a background sync the moment this screen opens, so the
    // verifier always has the latest event chains downloaded to the
    // device without needing to scan a ticket first. This runs after the
    // first frame so it never blocks the screen transition, and it's
    // safe to call even if chains are already present locally — it just
    // re-downloads anything that's changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(eventsProvider.notifier).syncAllEvents();
    });
  }

  @override
  void dispose() {
    if (_isAdvertising) {
      Nearby().stopAdvertising();
    }
    if (_connectedEndpointId != null) {
      Nearby().disconnectFromEndpoint(_connectedEndpointId!);
    }
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _setStatus(String msg) => _safeSetState(() => _statusMessage = msg);

  // ── Nearby Connections (P2P Stream Lifecycle) ───────────────────────────

  Future<bool> _requestP2PPermissions() async {
    final statuses = await [
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  // Helper method to dynamically isolate the active Scanner user name
  String _getScannerIdentityName() {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final metaName = currentUser?.userMetadata?['full_name'] as String?;
      if (metaName != null && metaName.trim().isNotEmpty) {
        return metaName.trim();
      }
    } catch (_) {}

    try {
      final authUser = ref.read(authProvider).user;
      if (authUser != null) {
        final mapData = jsonDecode(jsonEncode(authUser));
        if (mapData['fullName'] != null) return mapData['fullName'].toString();
        // FIX: curly_braces_in_flow_control_structures (was missing braces)
        if (mapData['displayName'] != null) {
          return mapData['displayName'].toString();
        }
        if (mapData['full_name'] != null) {
          return mapData['full_name'].toString();
        }
      }
    } catch (_) {}

    return "Gate Terminal";
  }

  Future<void> _toggleNearbyReceiver() async {
    if (_isAdvertising) {
      await Nearby().stopAdvertising();
      if (_connectedEndpointId != null) {
        await Nearby().disconnectFromEndpoint(_connectedEndpointId!);
      }
      _safeSetState(() {
        _isAdvertising = false;
        _connectedEndpointId = null;
      });
      return;
    }

    final allowed = await _requestP2PPermissions();
    if (!allowed) {
      _showError("Nearby sharing needs Location and Bluetooth permissions.");
      return;
    }

    _safeSetState(() {
      _scanning = true;
      _statusMessage = 'Setting up connection...';
    });

    // Create a dynamic display string for the target discovery pipeline
    final broadcastIdentity = "Scanner: ${_getScannerIdentityName()}";

    try {
      await Nearby().startAdvertising(
        broadcastIdentity,
        Strategy.P2P_STAR,
        onConnectionInitiated: (endpointId, connectionInfo) async {
          _setStatus('Connecting...');
          await Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved: _onP2PPayloadReceived,
            onPayloadTransferUpdate: _onP2PPayloadTransferUpdate,
          );
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            _safeSetState(() {
              _connectedEndpointId = endpointId;
              _scanning = true;
              _statusMessage = 'Connected! Waiting for ticket...';
            });
          } else {
            debugPrint('P2P Pipeline connection error status: $status');
            _safeSetState(() {
              _scanning = false;
              _connectedEndpointId = null;
            });
            _showError('Connection failed.');
          }
        },
        onDisconnected: (endpointId) {
          debugPrint(
              'P2P Pipeline remote disconnected from target: $endpointId');
          _safeSetState(() {
            _connectedEndpointId = null;
            if (_scanning && _statusMessage.contains('Waiting for ticket')) {
              _scanning = false;
            }
          });
          _showError('Sender disconnected.');
        },
      );

      _safeSetState(() {
        _isAdvertising = true;
        _statusMessage =
            'Ready to receive. Open the share menu on the sender device...';
      });
    } catch (e) {
      debugPrint('P2P Server Failure to initialize: ${e.toString()}');
      _safeSetState(() {
        _scanning = false;
        _isAdvertising = false;
      });
      _showError('Could not start wireless sharing.');
    }
  }

  void _onP2PPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.FILE) {
      if (payload.uri != null) {
        _incomingFileUris[payload.id] = payload.uri!;
        _setStatus('Receiving ticket...');
      }
    }
  }

  void _onP2PPayloadTransferUpdate(
      String endpointId, PayloadTransferUpdate update) async {
    switch (update.status) {
      case PayloadStatus.IN_PROGRESS:
        if (update.totalBytes > 0) {
          final progress = (update.bytesTransferred / update.totalBytes * 100)
              .toStringAsFixed(0);
          _setStatus('Downloading: $progress%');
        }
        break;

      case PayloadStatus.SUCCESS:
        final String? tempUriPath = _incomingFileUris[update.id];

        if (tempUriPath != null) {
          _setStatus('Opening ticket file...');
          try {
            final tempDir = await getTemporaryDirectory();
            final String originalFileName = tempUriPath.split('/').last;
            final targetDestPath =
                '${tempDir.path}/p2p_${DateTime.now().millisecondsSinceEpoch}_$originalFileName';

            await Nearby()
                .copyFileAndDeleteOriginal(tempUriPath, targetDestPath);

            _incomingFileUris.remove(update.id);

            // Direct inspect file signatures (Magic Bytes)
            final file = File(targetDestPath);
            bool isZipFile = false;

            if (await file.exists()) {
              final raf = await file.open(mode: FileMode.read);
              final bytes = await raf.read(4);
              await raf.close();

              if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
                isZipFile = true;
              }
            }

            if (isZipFile || targetDestPath.toLowerCase().endsWith('.zip')) {
              await _processZipAndVerify(targetDestPath);
            } else {
              await _verifyImage(targetDestPath);
            }
          } catch (e) {
            debugPrint('Error handling success payload streaming archive: $e');
            _safeSetState(() => _scanning = false);
            _showError('Failed to read the received ticket.');
          }
        } else {
          debugPrint(
              'P2P Error: Success status achieved but index URI tracking lost.');
          _safeSetState(() => _scanning = false);
          _showError('Transfer error. Please try again.');
        }
        break;

      case PayloadStatus.FAILURE:
        debugPrint('P2P Failure status caught for active channel transfer.');
        _safeSetState(() => _scanning = false);
        _incomingFileUris.remove(update.id);
        _showError('Connection lost.');
        break;

      case PayloadStatus.NONE:
        break;
      case PayloadStatus.CANCELED:
        _safeSetState(() => _scanning = false);
        _showError('Transfer canceled.');
        break;
    }
  }

  // ── File Picker ─────────────────────────────────────────────────────────
  Future<void> _pickImageFile() async {
    if (_pendingScan != null) return;
    final completer = Completer<void>();
    _pendingScan = completer.future;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'zip'],
        allowMultiple: false,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        throw const ImageReadError('Could not open the selected file.');
      }

      if (file.path!.toLowerCase().endsWith('.zip')) {
        await _processZipAndVerify(file.path!);
      } else {
        await _verifyImage(file.path!);
      }
    } catch (e) {
      debugPrint('File picking process context error: $e');
      _safeSetState(() => _scanning = false);
      _showError('$e');
    } finally {
      completer.complete();
      _pendingScan = null;
    }
  }

  // ── ZIP Decompression Handler ──────────────────────────────────────────
  Future<void> _processZipAndVerify(String zipPath) async {
    _safeSetState(() {
      _scanning = true;
      _statusMessage = 'Opening ZIP file...';
    });

    String? extractedImagePath;

    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw const ZipExtractError('File not found.');
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? targetImageFile;
      for (final file in archive) {
        if (file.isFile) {
          final ext = file.name.split('.').last.toLowerCase();
          if (['png', 'jpg', 'jpeg', 'bmp'].contains(ext)) {
            targetImageFile = file;
            break;
          }
        }
      }

      if (targetImageFile == null) {
        throw const ZipExtractError(
            'No ticket image found inside the ZIP file.');
      }

      final tempDir = await getTemporaryDirectory();
      extractedImagePath =
          '${tempDir.path}/extracted_${DateTime.now().millisecondsSinceEpoch}_${targetImageFile.name}';

      final extractedData = targetImageFile.content as List<int>;
      await File(extractedImagePath).writeAsBytes(extractedData);

      await _verifyImage(extractedImagePath);
    } on ScanError {
      rethrow;
    } catch (e) {
      debugPrint('Decompression exception during package extraction: $e');
      throw const ZipExtractError('Could not open the ZIP file.');
    } finally {
      if (extractedImagePath != null) {
        final localFile = File(extractedImagePath);
        if (localFile.existsSync()) {
          try {
            localFile.deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  // ── Core pipeline ─────────────────────────────────────────────────────
  Future<void> _verifyImage(String sourcePath) async {
    _safeSetState(() {
      _scanning = true;
      _statusMessage = 'Reading image...';
    });

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    String ext = 'png';
    final filename = sourcePath.split('/').last;
    final dotIdx = filename.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < filename.length - 1) {
      ext = filename.substring(dotIdx + 1).toLowerCase();
    }

    final String persistentPath = '${tempDir.path}/scan_orig_$ts.$ext';
    final persistentFile = _AutoDeleteFile(persistentPath);

    try {
      final src = File(sourcePath);
      if (!await src.exists()) {
        throw const ImageReadError('Ticket image not found.');
      }

      await src.copy(persistentPath);

      final fileBytes = await File(persistentPath).length();
      if (fileBytes < 1024) {
        throw const ImageReadError('Image file is invalid or too small.');
      }

      debugPrint(
          '[Scanner] Image ready: $persistentPath (${(fileBytes / 1024).toStringAsFixed(1)} KB)');

      final ffi = EventChainFFI.instance;
      List<String> eventNames = ffi.listEvents();

      if (eventNames.isEmpty) {
        _setStatus('Loading event details...');
        eventNames = await _tryDownloadChains();
      }

      if (eventNames.isEmpty) throw const NoChainsError();

      final result = await _runVerification(ffi, eventNames, persistentPath);

      Map<String, dynamic>? dbData;
      if (result.verified &&
          result.eventName != null &&
          result.blockIndex != null) {
        _setStatus('Loading ticket details...');
        dbData =
            await _supabaseLookupByBlock(result.eventName!, result.blockIndex!);
      } else {
        _setStatus('Checking database...');
        dbData = await _supabaseLookupByImageHash(persistentPath);
      }

      if (!mounted) throw const VerificationInterrupted();

      // ── Duplicate-scan guard ──────────────────────────────────────────────
      bool alreadyScanned = false;
      if (result.verified && dbData != null) {
        final ticketId = dbData['ticket_id'] as String?;
        if (ticketId != null) {
          // Check whether this ticket was scanned in a previous session.
          // The scanned_at column may already be set if dbData came from the
          // view; fall back to a direct DB check only when the column is absent.
          final existingTs = dbData.containsKey('scanned_at')
              ? dbData['scanned_at'] as String?
              : await ref
                  .read(eventsProvider.notifier)
                  .checkTicketScanned(ticketId);

          if (existingTs != null) {
            // Ticket was already used — surface the duplicate warning.
            alreadyScanned = true;
            dbData = {...dbData, 'scanned_at': existingTs};
          } else {
            // First scan — stamp the timestamp now.
            _setStatus('Marking ticket as used...');
            final stamped = await ref
                .read(eventsProvider.notifier)
                .markTicketScanned(ticketId);
            if (stamped) {
              dbData = {
                ...dbData,
                'scanned_at': DateTime.now().toUtc().toIso8601String(),
              };
            }
          }
        }
      }

      _safeSetState(() => _scanning = false);

      // FIX: use_build_context_synchronously — explicit mounted guard
      // immediately before the context usage, after all async gaps above.
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationResultScreen(
            authentic: result.verified,
            imagePath: persistentPath,
            eventName: result.eventName,
            blockIndex: result.blockIndex,
            supabaseTicketData: dbData,
            alreadyScanned: alreadyScanned,
          ),
        ),
      );
    } on VerificationInterrupted {
      debugPrint('[Scanner] Widget unmounted during scan');
    } on ScanError catch (e) {
      debugPrint('Scan validation rule handled: ${e.message}');
      _safeSetState(() => _scanning = false);
      _showError(e.message);
    } catch (e, stack) {
      debugPrint('[Scanner] Unexpected layout framework error: $e\n$stack');
      _safeSetState(() => _scanning = false);
      _showError('Something went wrong. Please try again.');
    } finally {
      persistentFile.dispose();
    }
  }

  // ── Verification loop ─────────────────────────────────────────────────
  Future<_ScanResult> _runVerification(
    EventChainFFI ffi,
    List<String> eventNames,
    String imagePath,
  ) async {
    for (final eventName in eventNames) {
      if (!mounted) break;

      final chainSize = ffi.getEventSize(eventName);
      if (chainSize <= 1) continue;

      for (int i = 1; i < chainSize; i++) {
        if (!mounted) break;

        _setStatus('Checking $eventName · step $i / ${chainSize - 1}…');

        try {
          final ok = await ffi.extractAndVerify(
            stegoPath: imagePath,
            eventName: eventName,
            blockIndex: i,
          );
          if (ok) {
            debugPrint('[Scanner] MATCH → $eventName block $i');
            return _ScanResult(
                verified: true, eventName: eventName, blockIndex: i);
          }
        } catch (e, stack) {
          debugPrint(
              '[Scanner] block $i layout evaluation error (skipping): $e\n$stack');
          continue;
        }
      }
    }
    return const _ScanResult(verified: false);
  }

  // ── Chain download & Supabase ─────────────────────────────────────────
  Future<List<String>> _tryDownloadChains() async {
    try {
      // Reuses the same full sync the screen already kicked off in
      // initState. If that sync is still running, this just waits on it
      // (syncAllEvents is a no-op re-entry guard, not a duplicate fetch);
      // if it already finished, this re-syncs to pick up anything new.
      await ref.read(eventsProvider.notifier).syncAllEvents();

      if (!mounted) return [];

      return EventChainFFI.instance.listEvents();
    } catch (e) {
      debugPrint(
          '[Scanner] background block initialization download error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _supabaseLookupByBlock(
    String eventName,
    int blockIndex,
  ) async {
    try {
      return await Supabase.instance.client
          .from('v_ticket_detail')
          .select()
          .eq('event_name', eventName)
          .eq('block_index', blockIndex)
          .maybeSingle();
    } catch (e) {
      debugPrint('[Scanner] Supabase query context lookup error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _supabaseLookupByImageHash(
      String imagePath) async {
    return null;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  /// Small status strip showing background sync progress / errors.
  /// Watches [eventsProvider] so it updates live as chains download.
  Widget _buildSyncBanner() {
    final eventsState = ref.watch(eventsProvider);
    final isSyncing = eventsState.loading || eventsState.syncing.isNotEmpty;

    if (!isSyncing && eventsState.message == null) {
      return const SizedBox.shrink();
    }

    final isError = !isSyncing && eventsState.message != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isError
          ? AppTheme.tamperedColor.withValues(alpha: 0.15)
          : AppTheme.primaryColor.withValues(alpha: 0.12),
      child: Row(
        children: [
          if (isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor,
              ),
            )
          else
            Icon(Icons.error_outline, size: 16, color: AppTheme.tamperedColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isSyncing
                  ? (eventsState.syncing.isNotEmpty
                      ? 'Syncing ${eventsState.syncing.length} event(s) to this device…'
                      : 'Syncing latest event data…')
                  : eventsState.message!,
              style: AppTheme.sans(
                fontSize: 12,
                color: isError ? AppTheme.tamperedColor : Colors.white,
              ),
            ),
          ),
          if (isError)
            TextButton(
              onPressed: () =>
                  ref.read(eventsProvider.notifier).syncAllEvents(force: true),
              child: Text('Retry', style: AppTheme.sans(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: Text('Ticket Scanner', style: AppTheme.merri(fontSize: 20)),
        actions: [
          if (_scanning)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                _safeSetState(() => _scanning = false);
              },
            )
        ],
      ),
      body: Column(
        children: [
          _buildSyncBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _scanning ? _buildScanning() : _buildIdle(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    return Center(
      key: const ValueKey('scanning'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              // FIX: prefer_const_constructors — add const to CircularProgressIndicator
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'VERIFYING TICKET',
              style: AppTheme.merri(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Center(
      key: const ValueKey('idle'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isAdvertising
                    ? Colors.green.withValues(alpha: 0.1)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                border: Border.all(
                  color: _isAdvertising
                      ? Colors.green
                      : AppTheme.primaryColor.withValues(alpha: 0.3),
                  width: 3,
                ),
              ),
              child: Icon(
                _isAdvertising
                    ? Icons.wifi_tethering_rounded
                    : Icons.image_rounded,
                size: 80,
                color: _isAdvertising ? Colors.green : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _isAdvertising ? 'Ready to Receive' : 'Select Ticket File',
              style: AppTheme.merri(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _isAdvertising
                  ? 'Ready to get tickets…\nKeep the sender device close by.'
                  : 'Choose a PNG, BMP, or ZIP file\ncontaining your ticket.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
            ),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _pickImageFile,
                      icon: const Icon(Icons.folder_open, size: 22),
                      label: Text(
                        'CHOOSE TICKET FILE',
                        style: AppTheme.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            _isAdvertising ? Colors.red : Colors.white,
                        side: BorderSide(
                          color: _isAdvertising
                              ? Colors.red
                              : AppTheme.primaryColor,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _toggleNearbyReceiver,
                      icon: Icon(
                          _isAdvertising
                              ? Icons.portable_wifi_off
                              : Icons.rss_feed,
                          size: 22),
                      label: Text(
                        _isAdvertising
                            ? 'STOP WIRELESS RECEIVE'
                            : 'RECEIVE FROM NEARBY DEVICE',
                        style: AppTheme.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _ScanResult {
  final bool verified;
  final String? eventName;
  final int? blockIndex;

  const _ScanResult({
    required this.verified,
    this.eventName,
    this.blockIndex,
  });
}
