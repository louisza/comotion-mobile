// lib/data/models/ble_packet.dart
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// Parsed representation of the CoMotion BLE manufacturer advertisement.
///
/// Supports both v1 (20-byte) and v2 (23-byte) packet formats.
/// Auto-detects version based on packet length.
///
/// Manufacturer ID: 0xFFFF
///
/// ═══ v2 Format (23 bytes) — Coded PHY / Extended Advertising ═══
///   [0]     status flags (b0=logging, b1=GPS fix, b2=impact, b3=focus)
///   [1]     battery % (0-100)
///   [2]     intensity 1s (0-255)
///   [3]     intensity 1-min avg (0-255)
///   [4-5]   intensity 10-min score uint16 LE
///   [6]     speed km/h × 2 (0.5 km/h resolution)
///   [7]     max speed session × 2
///   [8]     impact count session (0-255)
///   [9]     GPS status (upper 4 bits = age seconds, lower 4 bits = satellites)
///   [10-11] movement count uint16 LE
///   [12-13] session time seconds uint16 LE
///   [14]    audio level (peak dB in last window)
///   [15-18] latitude  int32 LE (degrees × 10⁷)
///   [19-22] longitude int32 LE (degrees × 10⁷)
///
/// GPS decoding (v2):
///   lat = int32 / 10000000.0
///   lng = int32 / 10000000.0
///   No-fix sentinel: 0x7FFFFFFF (2147483647)
///
/// ═══ v1 Format (20 bytes) — Legacy advertising ═══
///   [0-14]  Same as v2
///   [15-16] GPS lat offset int16 LE (units = 0.00001 deg from field center)
///   [17-18] GPS lng offset int16 LE (same)
///   [19]    reserved
///   No-fix sentinel: 0x7FFF (32767)
class BlePacket {
  final bool isLogging;
  final bool hasGpsFix;
  final bool isLowBattery;
  final bool hasImpact;
  final bool isBleConnected;
  final bool isFocus;

  final int batteryPercent;
  final int intensity1s;
  final int intensity1min;
  final int intensity10min;
  final double speedKmh;
  final double maxSpeedKmh;
  final int impactCount;
  final int gpsAgeSec;
  final int gpsSatellites;
  final int movementCount;
  final int sessionTimeSec;
  final int audioPeak;

  /// GPS position decoded from the packet.
  /// Null if firmware reported no fix.
  final LatLng? gpsPosition;

  /// Packet version: 1 (20-byte legacy) or 2 (23-byte coded PHY).
  final int packetVersion;

  const BlePacket({
    required this.isLogging,
    required this.hasGpsFix,
    required this.isLowBattery,
    required this.hasImpact,
    required this.isBleConnected,
    required this.isFocus,
    required this.batteryPercent,
    required this.intensity1s,
    required this.intensity1min,
    required this.intensity10min,
    required this.speedKmh,
    required this.maxSpeedKmh,
    required this.impactCount,
    required this.gpsAgeSec,
    required this.gpsSatellites,
    required this.movementCount,
    required this.sessionTimeSec,
    required this.audioPeak,
    this.gpsPosition,
    this.packetVersion = 2,
  });

  /// Parse raw manufacturer data bytes.
  ///
  /// Auto-detects packet version:
  ///   - ≥23 bytes → v2 (absolute GPS as int32 × 10⁷)
  ///   - ≥20 bytes → v1 (relative GPS offsets from field center)
  ///
  /// [fieldCenterLat] / [fieldCenterLng] only used for v1 fallback.
  static BlePacket? parse(
    Uint8List data, {
    double fieldCenterLat = -25.7479,
    double fieldCenterLng = 28.2293,
  }) {
    if (data.length < 20) return null;

    final bd = ByteData.sublistView(data);
    final flags = data[0];
    final gpsStatus = data[9];

    final intensity10min = bd.getUint16(4, Endian.little);
    final movementCount  = bd.getUint16(10, Endian.little);
    final sessionTimeSec = bd.getUint16(12, Endian.little);

    // ─── GPS decoding (auto-detect v1 vs v2) ───
    LatLng? position;
    int version;

    if (data.length >= 23) {
      // v2: absolute coordinates as int32 × 10⁷
      version = 2;
      final latRaw = bd.getInt32(15, Endian.little);
      final lngRaw = bd.getInt32(19, Endian.little);
      // 0x7FFFFFFF = no fix sentinel
      if (latRaw != 0x7FFFFFFF && lngRaw != 0x7FFFFFFF) {
        position = LatLng(latRaw / 10000000.0, lngRaw / 10000000.0);
      }
    } else {
      // v1: relative offsets from field center as int16 × 10⁵
      version = 1;
      final latRaw = bd.getInt16(15, Endian.little);
      final lngRaw = bd.getInt16(17, Endian.little);
      if (latRaw != 32767 && lngRaw != 32767) {
        position = LatLng(
          fieldCenterLat + latRaw / 100000.0,
          fieldCenterLng + lngRaw / 100000.0,
        );
      }
    }

    // ─── Status flags ───
    // v2 flags: b0=logging, b1=GPS, b2=impact, b3=focus
    // v1 flags: b0=logging, b1=GPS, b2=lowBattery, b3=impact, b4=bleConn, b5=focus
    // We handle both — unused bits just read as 0.
    return BlePacket(
      isLogging:      (flags & 0x01) != 0,
      hasGpsFix:      (flags & 0x02) != 0,
      isLowBattery:   version == 1 ? (flags & 0x04) != 0 : false,
      hasImpact:      version == 2 ? (flags & 0x04) != 0 : (flags & 0x08) != 0,
      isBleConnected: version == 1 ? (flags & 0x10) != 0 : false,
      isFocus:        version == 2 ? (flags & 0x08) != 0 : (flags & 0x20) != 0,
      batteryPercent:  data[1].clamp(0, 100),
      intensity1s:     data[2],
      intensity1min:   data[3],
      intensity10min:  intensity10min,
      speedKmh:        data[6] / 2.0,
      maxSpeedKmh:     data[7] / 2.0,
      impactCount:     data[8],
      gpsAgeSec:       (gpsStatus >> 4) & 0x0F,
      gpsSatellites:   gpsStatus & 0x0F,
      movementCount:   movementCount,
      sessionTimeSec:  sessionTimeSec,
      audioPeak:       data[14],
      gpsPosition:     position,
      packetVersion:   version,
    );
  }
}
