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
  const NoChainsError() : super('No event chains available');
}

final class VerificationInterrupted extends ScanError {
  const VerificationInterrupted() : super('Scan interrupted');
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
      _showError("P2P sharing requires Location and Bluetooth permissions.");
      return;
    }

    _safeSetState(() {
      _scanning = true;
      _statusMessage = 'Initializing local P2P discovery server…';
    });

    try {
      await Nearby().startAdvertising(
        "Ticket_Receiver_${Platform.localHostname}",
        Strategy.P2P_STAR,
        onConnectionInitiated: (endpointId, connectionInfo) async {
          _setStatus('Connecting to ${connectionInfo.endpointName}…');
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
              _statusMessage = 'Connected! Waiting for sender payload…';
            });
          } else {
            _safeSetState(() {
              _scanning = false;
              _connectedEndpointId = null;
            });
            _showError('Connection failed.');
          }
        },
        onDisconnected: (endpointId) {
          _safeSetState(() {
            _connectedEndpointId = null;
            if (_scanning && _statusMessage.contains('Waiting for sender')) {
              _scanning = false;
            }
          });
          _showError('Sender disconnected.');
        },
      );

      _safeSetState(() {
        _isAdvertising = true;
        _statusMessage =
            'Visible to nearby senders. Open Share menu on source…';
      });
    } catch (e) {
      _safeSetState(() {
        _scanning = false;
        _isAdvertising = false;
      });
      _showError('Could not start P2P sharing platform: $e');
    }
  }

  void _onP2PPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.FILE) {
      if (payload.uri != null) {
        _incomingFileUris[payload.id] = payload.uri!;
        _setStatus('Receiving inbound file container stream…');
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
          _setStatus('Downloading data payload: $progress%');
        }
        break;

      case PayloadStatus.SUCCESS:
        final String? tempUriPath = _incomingFileUris[update.id];

        if (tempUriPath != null) {
          _setStatus('Extracting local transport stream…');
          try {
            final tempDir = await getTemporaryDirectory();
            final String originalFileName = tempUriPath.split('/').last;
            final targetDestPath =
                '${tempDir.path}/p2p_${DateTime.now().millisecondsSinceEpoch}_$originalFileName';

            await Nearby()
                .copyFileAndDeleteOriginal(tempUriPath, targetDestPath);

            _incomingFileUris.remove(update.id);

            // ── FIX 1: Direct inspect file signatures (Magic Bytes) ──
            final file = File(targetDestPath);
            bool isZipFile = false;

            if (await file.exists()) {
              final raf = await file.open(mode: FileMode.read);
              final bytes = await raf.read(4);
              await raf.close();

              // ZIP files always start with 'PK' hex markers (0x50, 0x4B)
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
            _safeSetState(() => _scanning = false);
            _showError('Failed to decode incoming streaming container: $e');
          }
        } else {
          _safeSetState(() => _scanning = false);
          _showError('Payload verified transfer but index tracking was lost.');
        }
        break;

      case PayloadStatus.FAILURE:
        _safeSetState(() => _scanning = false);
        _incomingFileUris.remove(update.id);
        _showError('Local connection transfer dropped.');
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
        throw const ImageReadError('Could not access selected file');
      }

      if (file.path!.toLowerCase().endsWith('.zip')) {
        await _processZipAndVerify(file.path!);
      } else {
        await _verifyImage(file.path!);
      }
    } catch (e) {
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
      _statusMessage = 'Unpacking ZIP archive…';
    });

    String? extractedImagePath;

    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw const ZipExtractError('ZIP archive file no longer exists');
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
            'No valid ticket images (.png, .bmp, .jpg) found inside ZIP');
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
      throw ZipExtractError('Failed to parse ZIP archive contents: $e');
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
      _statusMessage = 'Reading image…';
    });

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // ── FIX 2: Safe Extension Extraction Strategy ──
    String ext = 'png'; // Fallback default
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
        throw const ImageReadError('Source image no longer exists');
      }

      await src.copy(persistentPath);

      final fileBytes = await File(persistentPath).length();
      if (fileBytes < 1024) {
        throw ImageReadError('Image too small (${fileBytes}B)');
      }

      debugPrint(
          '[Scanner] Image ready: $persistentPath (${(fileBytes / 1024).toStringAsFixed(1)} KB)');

      final ffi = EventChainFFI.instance;
      List<String> eventNames = ffi.listEvents();

      if (eventNames.isEmpty) {
        _setStatus('Fetching event chains from server…');
        eventNames = await _tryDownloadChains();
      }

      if (eventNames.isEmpty) throw const NoChainsError();

      final result = await _runVerification(ffi, eventNames, persistentPath);

      Map<String, dynamic>? dbData;
      if (result.verified &&
          result.eventName != null &&
          result.blockIndex != null) {
        _setStatus('Loading ticket details…');
        dbData =
            await _supabaseLookupByBlock(result.eventName!, result.blockIndex!);
      } else {
        _setStatus('Checking ticket database…');
        dbData = await _supabaseLookupByImageHash(persistentPath);
      }

      if (!mounted) throw const VerificationInterrupted();

      _safeSetState(() => _scanning = false);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationResultScreen(
            authentic: result.verified,
            imagePath: persistentPath,
            eventName: result.eventName,
            blockIndex: result.blockIndex,
            supabaseTicketData: dbData,
          ),
        ),
      );
    } on VerificationInterrupted {
      debugPrint('[Scanner] Widget unmounted during scan');
    } on ScanError catch (e) {
      _safeSetState(() => _scanning = false);
      _showError(e.message);
    } catch (e, stack) {
      debugPrint('[Scanner] Unexpected error: $e\n$stack');
      _safeSetState(() => _scanning = false);
      _showError('Unexpected error: $e');
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

        _setStatus('Checking $eventName · block $i / ${chainSize - 1}…');

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
          debugPrint('[Scanner] block $i error (skipping): $e\n$stack');
          continue;
        }
      }
    }
    return const _ScanResult(verified: false);
  }

  // ── Chain download & Supabase ─────────────────────────────────────────
  Future<List<String>> _tryDownloadChains() async {
    try {
      final supabase = Supabase.instance.client;
      final rows =
          await supabase.from('events').select('id, event_name').limit(50);

      if (!mounted) return [];

      final notifier = ref.read(eventsProvider.notifier);
      final events = List<Map<String, dynamic>>.from(rows);

      final chunks = _chunk(events, 4);
      for (final chunk in chunks) {
        await Future.wait(chunk.map((row) async {
          final name = row['event_name'] as String?;
          if (name != null) await notifier.loadRemoteChain(name);
        }));
      }

      return EventChainFFI.instance.listEvents();
    } catch (e) {
      debugPrint('[Scanner] chain download error: $e');
      return [];
    }
  }

  List<List<T>> _chunk<T>(List<T> list, int size) => [
        for (int i = 0; i < list.length; i += size)
          list.sublist(i, (i + size < list.length) ? i + size : list.length),
      ];

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
      debugPrint('[Scanner] Supabase block lookup error: $e');
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _scanning ? _buildScanning() : _buildIdle(),
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
              _isAdvertising ? 'P2P Network Active' : 'Select Ticket Payload',
              style: AppTheme.merri(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _isAdvertising
                  ? 'Ready to capture incoming file transfers…\nKeep your sender device nearby.'
                  : 'Pick a PNG, BMP, or ZIP archive file\ncontaining ticket payloads.',
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
                        'PICK FILE PAYLOAD',
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
                            : 'RECEIVE VIA NEARBY SHARE',
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
