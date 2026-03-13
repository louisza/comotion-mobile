// lib/data/models/ble_packet.dart
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// Parsed representation of the CoMotion BLE manufacturer advertisement.
///
/// Supports packet formats by length:
///   - ≥27 bytes → v2.1 (v2 + bearing, HDOP, fix quality)
///   - ≥23 bytes → v2   (absolute GPS as int32 × 10⁷)
///   - ≥20 bytes → v1   (relative GPS offsets from field center)
///
/// Manufacturer ID: 0xFFFF
///
/// ═══ v2.1 Format (27 bytes) — Extended fields ═══
///   [0-22]  Same as v2
///   [23-24] bearing   uint16 LE, ×10 (0–3600 = 0.0–360.0°)
///   [25]    HDOP      uint8, ×10 (0–255 = 0.0–25.5)
///   [26]    fix quality uint8 (0=none, 1=SPS, 2=DGNSS, 3=PPS, 4=RTK)
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
/// ═══ v1 Format (20 bytes) — Legacy advertising ═══
///   [0-14]  Same as v2
///   [15-16] GPS lat offset int16 LE (units = 0.00001 deg from field center)
///   [17-18] GPS lng offset int16 LE (same)
///   [19]    reserved
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

  /// GPS position decoded from the packet. Null if no fix.
  final LatLng? gpsPosition;

  /// GPS bearing in degrees (0.0–360.0). Null if not available (v1/v2 or no fix).
  final double? gpsBearingDeg;

  /// Horizontal dilution of precision (0.0–25.5). Null if not available.
  final double? gpsHdop;

  /// GPS fix quality: 0=none, 1=SPS, 2=DGNSS, 3=PPS, 4=RTK. Null if not available.
  final int? gpsFixQuality;

  /// Packet version: 1 (20-byte), 2 (23-byte), or 21 (27-byte v2.1).
  final int packetVersion;

  /// Rolling sequence number (0-255). Null if not available (pre-v2.2 firmware).
  final int? seq;

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
    this.gpsBearingDeg,
    this.gpsHdop,
    this.gpsFixQuality,
    this.packetVersion = 2,
    this.seq,
  });

  /// Human-readable fix quality string.
  String get fixQualityLabel {
    switch (gpsFixQuality) {
      case 0: return 'None';
      case 1: return 'SPS';
      case 2: return 'DGNSS';
      case 3: return 'PPS';
      case 4: return 'RTK';
      default: return '?';
    }
  }

  /// Parse raw manufacturer data bytes.
  ///
  /// Auto-detects packet version:
  ///   - ≥27 bytes → v2.1 (v2 + bearing/HDOP/fix)
  ///   - ≥23 bytes → v2   (absolute GPS as int32 × 10⁷)
  ///   - ≥20 bytes → v1   (relative GPS offsets from field center)
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

    // ─── GPS decoding ───
    LatLng? position;
    int version;
    double? bearingDeg;
    double? hdop;
    int? fixQuality;

    if (data.length >= 23) {
      // v2+: absolute coordinates as int32 × 10⁷
      version = data.length >= 27 ? 21 : 2;
      final latRaw = bd.getInt32(15, Endian.little);
      final lngRaw = bd.getInt32(19, Endian.little);
      if (latRaw != 0x7FFFFFFF && lngRaw != 0x7FFFFFFF) {
        position = LatLng(latRaw / 10000000.0, lngRaw / 10000000.0);
      }

      // v2.1 extended fields
      if (data.length >= 27) {
        final bearingRaw = bd.getUint16(23, Endian.little);
        bearingDeg = bearingRaw / 10.0; // 0.0–360.0°
        hdop = data[25] / 10.0;         // 0.0–25.5
        fixQuality = data[26];           // 0–4
      }
    } else {
      // v1: relative offsets from field center
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
    final isV1 = version == 1;
    return BlePacket(
      isLogging:      (flags & 0x01) != 0,
      hasGpsFix:      (flags & 0x02) != 0,
      isLowBattery:   isV1 ? (flags & 0x04) != 0 : false,
      hasImpact:      isV1 ? (flags & 0x08) != 0 : (flags & 0x04) != 0,
      isBleConnected: isV1 ? (flags & 0x10) != 0 : false,
      isFocus:        isV1 ? (flags & 0x20) != 0 : (flags & 0x08) != 0,
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
      gpsBearingDeg:   bearingDeg,
      gpsHdop:         hdop,
      gpsFixQuality:   fixQuality,
      packetVersion:   version,
      seq:             data.length >= 28 ? data[27] : null,
    );
  }
}
