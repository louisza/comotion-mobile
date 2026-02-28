// lib/main.dart
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'data/sources/ble_direct_source.dart';
import 'data/sources/data_source.dart';
import 'data/sources/mock_data_source.dart';
import 'services/field_calibration_service.dart';
import 'ui/screens/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => DataSourceNotifier(),
      child: ChangeNotifierProvider(
        create: (_) => FieldCalibrationService(),
        child: const ComotionApp(),
      ),
    ),
  );
}

class ComotionApp extends StatelessWidget {
  const ComotionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataSourceNotifier>(
      builder: (context, notifier, _) => MultiProvider(
        providers: [
          Provider<DataSource>.value(value: notifier.current),
        ],
        child: MaterialApp(
          title: 'CoMotion',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF2196F3),
              secondary: Color(0xFF4CAF50),
            ),
            textTheme: ThemeData.dark().textTheme,
          ),
          home: const GameScreen(),
        ),
      ),
    );
  }
}

/// ChangeNotifier that owns the active [DataSource] and allows toggling
/// between [MockDataSource] and [BleDirectSource] at runtime.
class DataSourceNotifier extends ChangeNotifier {
  MockDataSource _mock = MockDataSource();
  BleDirectSource _ble = BleDirectSource();
  bool _isMock = true;
  bool _toggling = false;

  bool get isMock => _isMock;
  bool get toggling => _toggling;

  DataSource get current => _isMock ? _mock : _ble;

  /// Stop current source, switch, recreate, notify.
  /// Async so callers can await the stop completing before subscribing.
  Future<void> toggle() async {
    if (_toggling) return;
    _toggling = true;

    // Stop current source cleanly
    await current.stop();

    _isMock = !_isMock;

    // Recreate the new source fresh (reset all internal state)
    if (_isMock) {
      _mock = MockDataSource();
    } else {
      _ble = BleDirectSource();
    }

    _toggling = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _mock.dispose();
    _ble.dispose();
    super.dispose();
  }
}
