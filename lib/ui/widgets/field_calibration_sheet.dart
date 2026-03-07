// lib/ui/widgets/field_calibration_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../data/sources/data_source.dart';
import '../../data/models/player_state.dart';
import '../../services/field_calibration_service.dart';

/// Shows a full-screen satellite map where the user taps two diagonal
/// corners of the field. The field boundary is drawn as a white rectangle.
void showFieldCalibrationSheet(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<FieldCalibrationService>(),
      child: Provider.value(
        value: context.read<DataSource>(),
        child: const _CalibrationMapScreen(),
      ),
    ),
  ));
}

class _CalibrationMapScreen extends StatefulWidget {
  const _CalibrationMapScreen();

  @override
  State<_CalibrationMapScreen> createState() => _CalibrationMapScreenState();
}

class _CalibrationMapScreenState extends State<_CalibrationMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _cornerA;
  LatLng? _cornerB;

  LatLng get _initialCenter {
    // Use first player GPS, or calibration center, or Pretoria default
    final calSvc = context.read<FieldCalibrationService>();
    if (calSvc.calibration != null) return calSvc.calibration!.centerSpot;

    final source = context.read<DataSource>();
    // Try to get a player position from the stream's last value
    return const LatLng(-25.7479, 28.2293); // Default — Pretoria
  }

  List<LatLng>? get _rectCorners {
    if (_cornerA == null || _cornerB == null) return null;
    final minLat = _cornerA!.latitude < _cornerB!.latitude ? _cornerA!.latitude : _cornerB!.latitude;
    final maxLat = _cornerA!.latitude > _cornerB!.latitude ? _cornerA!.latitude : _cornerB!.latitude;
    final minLng = _cornerA!.longitude < _cornerB!.longitude ? _cornerA!.longitude : _cornerB!.longitude;
    final maxLng = _cornerA!.longitude > _cornerB!.longitude ? _cornerA!.longitude : _cornerB!.longitude;
    return [
      LatLng(maxLat, minLng), // TL
      LatLng(maxLat, maxLng), // TR
      LatLng(minLat, maxLng), // BR
      LatLng(minLat, minLng), // BL
    ];
  }

  void _onTap(TapPosition tapPos, LatLng point) {
    setState(() {
      if (_cornerA == null) {
        _cornerA = point;
      } else if (_cornerB == null) {
        _cornerB = point;
      } else {
        // Reset and start over
        _cornerA = point;
        _cornerB = null;
      }
    });
  }

  void _confirm() {
    if (_cornerA == null || _cornerB == null) return;
    final calSvc = context.read<FieldCalibrationService>();
    calSvc.setFromCorners(_cornerA!, _cornerB!);
    Navigator.of(context).pop();
  }

  void _clear() {
    final calSvc = context.read<FieldCalibrationService>();
    calSvc.clearCalibration();
    setState(() {
      _cornerA = null;
      _cornerB = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final calSvc = context.watch<FieldCalibrationService>();
    final corners = _rectCorners;
    final existingCorners = calSvc.calibration?.corners;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Calibrate Field', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (calSvc.isCalibrated)
            TextButton(
              onPressed: _clear,
              child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 18.0,
              maxZoom: 20.0,
              minZoom: 14.0,
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.comotion.mobile',
                maxZoom: 20,
              ),

              // Show existing calibration corners (green)
              if (existingCorners != null && existingCorners.length >= 4 && corners == null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: existingCorners,
                      borderColor: Colors.greenAccent,
                      borderStrokeWidth: 2.5,
                      color: Colors.greenAccent.withOpacity(0.08),
                    ),
                  ],
                ),

              // Show new selection rectangle (yellow)
              if (corners != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: corners,
                      borderColor: Colors.yellowAccent,
                      borderStrokeWidth: 2.5,
                      color: Colors.yellowAccent.withOpacity(0.08),
                    ),
                  ],
                ),

              // Corner markers
              MarkerLayer(
                markers: [
                  if (_cornerA != null)
                    Marker(
                      point: _cornerA!,
                      width: 20, height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Center(child: Text('1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  if (_cornerB != null)
                    Marker(
                      point: _cornerB!,
                      width: 20, height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Center(child: Text('2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Instructions banner at top
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _cornerA == null
                    ? '📍 Tap the TOP-LEFT corner of the field'
                    : _cornerB == null
                        ? '📍 Now tap the BOTTOM-RIGHT corner'
                        : '✅ Field marked! Tap Confirm or tap again to redo.',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Confirm button at bottom
          if (_cornerA != null && _cornerB != null)
            Positioned(
              bottom: 32,
              left: 40,
              right: 40,
              child: ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('Confirm Field Boundary'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
