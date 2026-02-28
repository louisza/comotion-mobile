// lib/data/models/ble_packet.dart
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// Parsed representation of the 20-byte CoMotion manufacturer advertisement.
///
/// Manufacturer ID: 0xFFFF
/// Format:
///   [0]     status flags (b0=logging, b1=GPS fix, b2=low battery,
///                         b3=impact, b4=BLE connected, b5=focus)
///   [1]     battery % (0-100)
///   [2]     intensity 1s (0-255)
///   [3]     intensity 1-min avg (0-255)
///   [4-5]   intensity 10-min score uint16 LE
///   [6]     speed km/h (current)
///   [7]     max speed session
///   [8]     impact count session
///   [9]     GPS status (upper 4 bits = age seconds, lower 4 bits = satellites)
///   [10-11] movement count uint16 LE
///   [12-13] session time seconds uint16 LE
///   [14]    audio peak scaled 0-255
///   [15-16] GPS lat offset from field center (int16 LE, units = 0.00001 deg)
///   [17-18] GPS lng offset from field center (int16 LE, units = 0.00001 deg)
///   [19]    reserved
///
/// GPS decoding:
///   lat = FIELD_CENTER_LAT + (int16 at bytes 15-16) / 100000.0
///   lng = FIELD_CENTER_LNG + (int16 at bytes 17-18) / 100000.0
///   Sentinel value 0x7FFF (32767) in either field = no GPS fix.
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

  /// GPS position decoded from bytes 15-18.
  /// Null if firmware reported no fix (sentinel 0x7FFF).
  final LatLng? gpsPosition;

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
  });

  /// Parse raw manufacturer data bytes (must be at least 20 bytes).
  /// [fieldCenterLat] and [fieldCenterLng] must match FIELD_CENTER_LAT/LNG
  /// configured in the firmware's config.h.
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

    // Decode GPS position from bytes 15-18 (int16 LE offsets, 0.00001 deg units)
    final latRaw = bd.getInt16(15, Endian.little);
    final lngRaw = bd.getInt16(17, Endian.little);
    // 0x7FFF (32767) is the firmware sentinel for "no GPS fix"
    final LatLng? position = (latRaw == 32767 || lngRaw == 32767)
        ? null
        : LatLng(
            fieldCenterLat + latRaw / 100000.0,
            fieldCenterLng + lngRaw / 100000.0,
          );

    return BlePacket(
      isLogging:     (flags & 0x01) != 0,
      hasGpsFix:     (flags & 0x02) != 0,
      isLowBattery:  (flags & 0x04) != 0,
      hasImpact:     (flags & 0x08) != 0,
      isBleConnected:(flags & 0x10) != 0,
      isFocus:       (flags & 0x20) != 0,
      batteryPercent: data[1].clamp(0, 100),
      intensity1s:    data[2],
      intensity1min:  data[3],
      intensity10min: intensity10min,
      speedKmh:       data[6] / 2.0,      // 0.5 km/h steps
      maxSpeedKmh:    data[7] / 2.0,
      impactCount:    data[8],
      gpsAgeSec:      (gpsStatus >> 4) & 0x0F,
      gpsSatellites:  gpsStatus & 0x0F,
      movementCount:  movementCount,
      sessionTimeSec: sessionTimeSec,
      audioPeak:      data[14],
      gpsPosition:    position,
    );
  }
}
