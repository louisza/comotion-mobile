# CoMotion Mobile

Flutter companion app for the CoMotion wearable sports tracker.

## Overview

Real-time player tracking dashboard for field hockey (and other sports). Displays player positions, intensity metrics, speed, impacts, and battery status from CoMotion wearable devices over BLE.

## Architecture

```
lib/
  main.dart                        # App entry point + DataSourceNotifier
  data/
    sources/
      data_source.dart             # Abstract interface
      ble_direct_source.dart       # Live BLE passive scan
      wifi_relay_source.dart       # Future WiFi relay stub
      mock_data_source.dart        # Demo simulation (3 players)
    models/
      player.dart                  # Static player identity
      player_state.dart            # Live telemetry + trail
      ble_packet.dart              # 20-byte firmware packet parser
  ui/
    screens/
      game_screen.dart             # Main live game view
    widgets/
      field_view.dart              # Top-down hockey field + dots
      player_dot.dart              # Dual-ring intensity dot
      player_card.dart             # Bottom sheet metrics
      player_list.dart             # Horizontal roster strip
  services/
    ble_scanner.dart               # BLE scan helper
    field_mapper.dart              # GPS → canvas pixel mapping
```

## Setup

### Prerequisites

- Flutter SDK ≥ 3.10 ([install guide](https://docs.flutter.dev/get-started/install))
- Android SDK (API 21+)
- Android device or emulator

### Install dependencies

```bash
cd comotion-mobile
flutter pub get
```

### Run (mock mode — no hardware needed)

```bash
flutter run
```

The app launches in **Mock mode** by default — 3 simulated players move around the field with varying intensity. No hardware required.

### Toggle to BLE mode

Tap the **FAB** (bottom-right) to switch between Mock ↔ BLE mode at runtime.

In BLE mode the app scans for devices named `CoMotion` broadcasting manufacturer data with ID `0xFFFF`.

## BLE Packet Format

| Bytes | Field |
|-------|-------|
| 0     | Status flags (b0=logging, b1=GPS fix, b2=low battery, b3=impact, b4=BLE connected, b5=focus) |
| 1     | Battery % |
| 2     | Intensity 1s |
| 3     | Intensity 1-min avg |
| 4-5   | Intensity 10-min score (uint16 LE) |
| 6     | Speed km/h |
| 7     | Max speed session |
| 8     | Impact count |
| 9     | GPS status (upper 4 = age sec, lower 4 = satellites) |
| 10-11 | Movement count (uint16 LE) |
| 12-13 | Session time seconds (uint16 LE) |
| 14    | Audio peak (0-255) |
| 15-19 | Reserved |

## Field Configuration

The `FieldMapper` accepts 4 GPS corner coordinates (topLeft, topRight, bottomRight, bottomLeft) to map player GPS positions to field pixels. Configure in `game_screen.dart`:

```dart
final _mapper = FieldMapper(corners: [
  LatLng(-26.0010, 28.0990), // top-left
  LatLng(-26.0010, 28.1010), // top-right
  LatLng(-25.9990, 28.1010), // bottom-right
  LatLng(-25.9990, 28.0990), // bottom-left
]);
```

If no corners are set, the mapper uses the mock GPS bounds automatically.

## Android Permissions

The app requires BLE scan permissions. On Android 12+ these are:
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`

On older Android versions:
- `BLUETOOTH` + `BLUETOOTH_ADMIN`
- `ACCESS_FINE_LOCATION`

Permissions are declared in `android/app/src/main/AndroidManifest.xml`.

## Next Steps

- [ ] Active BLE connection to read GPS coordinates from watch characteristic
- [ ] WiFi relay box implementation (`wifi_relay_source.dart`)
- [ ] Field corner GPS configuration UI
- [ ] Session recording + replay
- [ ] Push notifications for high-intensity alerts
