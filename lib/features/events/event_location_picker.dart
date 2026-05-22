// lib/features/events/event_location_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/theme/app_theme.dart';

class EventLocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation; // for editing

  const EventLocationPickerScreen({super.key, this.initialLocation});

  @override
  State<EventLocationPickerScreen> createState() =>
      _EventLocationPickerScreenState();
}

class _EventLocationPickerScreenState extends State<EventLocationPickerScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  bool _isLoadingLocation = false;

  // Default center = Blantyre, Malawi (your location)
  static const LatLng _blantyre = LatLng(-15.7861, 35.0037);

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation ?? _blantyre;
    // Center map on initial location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_selectedLocation!, 15.0);
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final newPerm = await Geolocator.requestPermission();
        if (newPerm == LocationPermission.denied) return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPos = LatLng(position.latitude, position.longitude);
      setState(() => _selectedLocation = newPos);

      _mapController.move(newPos, 16.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() => _selectedLocation = point);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        title: Text('Set Event Location', style: AppTheme.merri(fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: _selectedLocation == null
                ? null
                : () => Navigator.pop(context, _selectedLocation),
            icon: const Icon(Icons.check, color: AppTheme.primaryColor),
            label: Text(
              'Save',
              style: AppTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Flutter Map ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation ?? _blantyre,
              initialZoom: 15.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.eventchain',
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFFF1744),
                        size: 50,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Info banner at top ─────────────────────────────────────
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardColor.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFFF1744)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedLocation != null
                          ? '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                              '${_selectedLocation!.longitude.toStringAsFixed(6)}'
                          : 'Tap anywhere on the map',
                      style: AppTheme.sans(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Current location button ────────────────────────────────
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              child: _isLoadingLocation
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
