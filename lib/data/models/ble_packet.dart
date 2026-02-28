// lib/data/models/ble_packet.dart
import 'dart:typed_data';

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
///   [15-19] reserved
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
  final int speedKmh;
  final int maxSpeedKmh;
  final int impactCount;
  final int gpsAgeSec;
  final int gpsSatellites;
  final int movementCount;
  final int sessionTimeSec;
  final int audioPeak;

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
  });

  /// Parse raw manufacturer data bytes (must be exactly 20 bytes).
  /// Returns null if the data is malformed.
  static BlePacket? parse(Uint8List data) {
    if (data.length < 20) return null;

    final flags = data[0];
    final gpsStatus = data[9];
    final intensity10min =
        ByteData.sublistView(data, 4, 6).getUint16(0, Endian.little);
    final movementCount =
        ByteData.sublistView(data, 10, 12).getUint16(0, Endian.little);
    final sessionTimeSec =
        ByteData.sublistView(data, 12, 14).getUint16(0, Endian.little);

    return BlePacket(
      isLogging: (flags & 0x01) != 0,
      hasGpsFix: (flags & 0x02) != 0,
      isLowBattery: (flags & 0x04) != 0,
      hasImpact: (flags & 0x08) != 0,
      isBleConnected: (flags & 0x10) != 0,
      isFocus: (flags & 0x20) != 0,
      batteryPercent: data[1].clamp(0, 100),
      intensity1s: data[2],
      intensity1min: data[3],
      intensity10min: intensity10min,
      speedKmh: data[6],
      maxSpeedKmh: data[7],
      impactCount: data[8],
      gpsAgeSec: (gpsStatus >> 4) & 0x0F,
      gpsSatellites: gpsStatus & 0x0F,
      movementCount: movementCount,
      sessionTimeSec: sessionTimeSec,
      audioPeak: data[14],
    );
  }
}
