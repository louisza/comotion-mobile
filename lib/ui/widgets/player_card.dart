// lib/ui/widgets/player_card.dart
import 'package:flutter/material.dart';

import '../../data/models/player_state.dart';
import '../../data/sources/ble_direct_source.dart';
import '../../data/sources/data_source.dart';
import '../../main.dart' show DataSourceNotifier, navigatorKey;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'log_transfer_sheet.dart';
import 'player_dot.dart';

/// Opens log transfer as a full-screen page via global navigator.
void _openLogTransfer(BluetoothDevice device, String deviceId) {
  final ctx = navigatorKey.currentContext;
  if (ctx != null) {
    showLogTransferSheet(ctx, device: device, deviceId: deviceId);
  }
}

String _gpsFixLabel(int q) {
  switch (q) {
    case 1: return 'SPS';
    case 2: return 'DGNSS';
    case 3: return 'PPS';
    case 4: return 'RTK';
    default: return '?';
  }
}

/// Bottom sheet showing detailed metrics for a single player.
/// Subscribes to the DataSource stream so metrics update in real time.
void showPlayerCard(BuildContext context, PlayerState state) {
  final source = context.read<DataSource>();
  final rootContext = context; // Capture the game screen context for later use
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LivePlayerCard(
      playerId: state.player.id,
      initialState: state,
      stream: source.playerStates,
    ),
  );
}

class _LivePlayerCard extends StatelessWidget {
  final String playerId;
  final PlayerState initialState;
  final Stream<List<PlayerState>> stream;

  _LivePlayerCard({
    required this.playerId,
    required this.initialState,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlayerState>>(
      stream: stream,
      initialData: [initialState],
      builder: (context, snapshot) {
        final players = snapshot.data ?? [initialState];
        final state = players.cast<PlayerState?>().firstWhere(
          (p) => p!.player.id == playerId,
          orElse: () => null,
        ) ?? initialState;
        return PlayerCard(state: state);
      },
    );
  }
}

class PlayerCard extends StatelessWidget {
  final PlayerState state;

  const PlayerCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme
        .apply(bodyColor: Colors.white, displayColor: Colors.white);

    return SingleChildScrollView(
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: number + name + GPS.
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: state.player.color,
                child: Text(
                  '${state.player.number}',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.player.name,
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      state.hasGpsFix
                          ? '${state.gpsSatellites} sats · ${state.gpsAgeSec}s ago'
                              '${state.gpsHdop != null ? ' · HDOP ${state.gpsHdop!.toStringAsFixed(1)}' : ''}'
                              '${state.gpsFixQuality != null && state.gpsFixQuality! > 0 ? ' · ${_gpsFixLabel(state.gpsFixQuality!)}' : ''}'
                          : 'No GPS fix',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              _SignalBadge(lastSeen: state.lastSeen),
              const SizedBox(width: 8),
              _BatteryBadge(percent: state.batteryPercent),
            ],
          ),
          const SizedBox(height: 24),

          // Logging status + start/stop button
          _LoggingControlRow(state: state),
          const SizedBox(height: 16),

          // Intensity gauge.
          Text('Intensity (1s)', style: textTheme.labelLarge?.copyWith(color: Colors.white54)),
          const SizedBox(height: 6),
          _IntensityGauge(value: state.intensity1s / 255.0),
          const SizedBox(height: 20),

          // Sparkline.
          Text('Last 5 min', style: textTheme.labelLarge?.copyWith(color: Colors.white54)),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: _Sparkline(samples: state.intensityHistory),
          ),
          const SizedBox(height: 20),

          // Stats grid.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatChip(
                label: 'Distance',
                value: state.distanceMeters >= 1000
                    ? '${(state.distanceMeters / 1000).toStringAsFixed(2)} km'
                    : '${state.distanceMeters.toStringAsFixed(0)} m',
                highlight: true,
              ),
              _StatChip(label: 'm/min', value: state.distancePerMin.toStringAsFixed(0)),
              _StatChip(label: 'Speed', value: '${state.speedKmh.toStringAsFixed(1)} km/h'),
              _StatChip(label: 'Max Speed', value: '${state.maxSpeedKmh.toStringAsFixed(1)} km/h'),
              _StatChip(label: 'Sprints', value: '${state.sprintCount}'),
              _StatChip(
                label: 'Player Load',
                value: state.playerLoad.toStringAsFixed(0),
                highlight: true,
              ),
              _StatChip(label: 'Impacts', value: '${state.impactCount}'),
              _StatChip(
                label: 'Session',
                value: _formatTime(state.sessionTimeSec),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Fatigue indicator
          _FatigueBar(ratio: state.fatigueRatio, standingSec: state.standingSeconds),

          const SizedBox(height: 20),

          // Download Logs button (only for BLE devices)
          // Note: we avoid using Provider.read inside build to prevent !_dirty issues
          _DownloadLogsButton(playerId: state.player.id),
        ],
      ),
    ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Separate StatefulWidget for the download button — isolates Provider.read
/// from the StreamBuilder's constantly-dirty build context.
class _DownloadLogsButton extends StatefulWidget {
  final String playerId;
  const _DownloadLogsButton({required this.playerId});

  @override
  State<_DownloadLogsButton> createState() => _DownloadLogsButtonState();
}

class _DownloadLogsButtonState extends State<_DownloadLogsButton> {
  BluetoothDevice? _device;
  bool _isMock = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final notifier = Provider.of<DataSourceNotifier>(context, listen: false);
      _isMock = notifier.isMock;
      if (!_isMock) {
        final ble = notifier.current;
        if (ble is BleDirectSource) {
          _device = ble.getDevice(widget.playerId);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isMock || _device == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Download Logs'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF2196F3),
          side: const BorderSide(color: Color(0xFF2196F3), width: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => _openLogTransfer(_device!, widget.playerId),
      ),
    );
  }
}

class _IntensityGauge extends StatelessWidget {
  final double value; // 0-1

  const _IntensityGauge({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 20,
        backgroundColor: Colors.white12,
        valueColor: AlwaysStoppedAnimation<Color>(
          PlayerDot.intensityColor((value * 255).toInt()),
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<int> samples;

  const _Sparkline({required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text('No data yet', style: TextStyle(color: Colors.white38)),
      );
    }
    return CustomPaint(
      painter: _SparklinePainter(samples: samples),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> samples;
  const _SparklinePainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = i / (samples.length - 1) * size.width;
      final y = size.height - (samples[i] / 255.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = PlayerDot.intensityColor(samples.last)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.samples != samples;
}

class _SignalBadge extends StatelessWidget {
  final DateTime lastSeen;
  const _SignalBadge({required this.lastSeen});

  @override
  Widget build(BuildContext context) {
    final ageSec = DateTime.now().difference(lastSeen).inSeconds;
    final color = ageSec < 3
        ? const Color(0xFF4CAF50)
        : ageSec < 10
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);
    final label = ageSec < 3 ? 'LIVE' : '${ageSec}s';
    return Row(
      children: [
        Icon(Icons.sensors, color: color, size: 16),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}

class _BatteryBadge extends StatelessWidget {
  final int percent;
  const _BatteryBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = percent > 30
        ? const Color(0xFF4CAF50)
        : percent > 15
            ? const Color(0xFFFFEB3B)
            : const Color(0xFFF44336);
    return Row(
      children: [
        Icon(Icons.battery_full, color: color, size: 18),
        const SizedBox(width: 2),
        Text('$percent%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _StatChip({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? Colors.white.withOpacity(0.15) : Colors.white10,
        borderRadius: BorderRadius.circular(10),
        border: highlight ? Border.all(color: Colors.white24) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}

class _FatigueBar extends StatelessWidget {
  final double ratio; // 0.0–1.0 (1.0 = fresh, <0.5 = fatigued)
  final int standingSec;
  const _FatigueBar({required this.ratio, required this.standingSec});

  @override
  Widget build(BuildContext context) {
    final color = ratio > 0.7
        ? const Color(0xFF4CAF50) // Green — fresh
        : ratio > 0.4
            ? const Color(0xFFFFEB3B) // Yellow — moderate
            : const Color(0xFFF44336); // Red — fatigued
    final label = ratio > 0.7
        ? 'Fresh'
        : ratio > 0.4
            ? 'Moderate'
            : 'Fatigued';
    final standingMin = standingSec ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Fatigue', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            if (standingMin > 0) ...[
              const SizedBox(width: 8),
              Text('⏸ ${standingMin}m idle', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _LoggingControlRow extends StatefulWidget {
  final PlayerState state;
  const _LoggingControlRow({required this.state});

  @override
  State<_LoggingControlRow> createState() => _LoggingControlRowState();
}

class _LoggingControlRowState extends State<_LoggingControlRow> {
  bool _sending = false;

  Future<void> _toggleLogging() async {
    final notifier = Provider.of<DataSourceNotifier>(context, listen: false);
    if (notifier.isMock) return;
    final source = notifier.current;
    if (source is! BleDirectSource) return;

    final command = widget.state.isLogging ? 'stop' : 'start';
    setState(() => _sending = true);

    try {
      final device = source.getDevice(widget.state.player.id);
      if (device != null) {
        await source.sendCommand(device, command);
      }
    } catch (e) {
      debugPrint('[PlayerCard] Failed to send $command: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logging = widget.state.isLogging;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: logging
            ? const Color(0xFFF44336).withOpacity(0.15)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: logging ? const Color(0xFFF44336).withOpacity(0.4) : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Icon(
            logging ? Icons.fiber_manual_record : Icons.stop_circle_outlined,
            color: logging ? const Color(0xFFF44336) : Colors.white38,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              logging ? 'Recording' : 'Idle',
              style: TextStyle(
                color: logging ? const Color(0xFFF44336) : Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _toggleLogging,
              icon: _sending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(logging ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
              label: Text(logging ? 'Stop' : 'Start', style: const TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: logging ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
