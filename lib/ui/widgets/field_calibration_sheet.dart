// lib/ui/widgets/field_calibration_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/field_calibration_service.dart';
import '../../services/field_mapper.dart';

/// Bottom sheet that guides the coach through two-point field calibration.
///
/// Step 1: Tracker on center spot       → coach confirms, app reads GPS from BLE
/// Step 2: Coach at halfway sideline    → app captures phone GPS
/// Done:   Field is calibrated, dots map correctly
void showFieldCalibrationSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12122A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<FieldCalibrationService>(),
      child: const _CalibrationSheetBody(),
    ),
  );
}

class _CalibrationSheetBody extends StatelessWidget {
  const _CalibrationSheetBody();

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<FieldCalibrationService>();

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: Color(0xFF2196F3), size: 22),
              const SizedBox(width: 10),
              const Text(
                'Calibrate Field',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (svc.isCalibrated && svc.step == CalibrationStep.idle)
                TextButton(
                  onPressed: svc.clearCalibration,
                  child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Current state display
          if (svc.isCalibrated && svc.step == CalibrationStep.idle)
            _CalibratedSummary(svc: svc)
          else
            _CalibrationSteps(svc: svc),

          // Error
          if (svc.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(svc.error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalibrationSteps extends StatelessWidget {
  final FieldCalibrationService svc;
  const _CalibrationSteps({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Two quick steps to orient the field map to any pitch.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Step 1
        _StepRow(
          number: '1',
          title: 'Tracker on center spot',
          subtitle: 'Place the tracker (or have player stand) on the center spot of the field.',
          isActive: svc.step == CalibrationStep.idle ||
                    svc.step == CalibrationStep.waitingTracker,
          isDone: svc.trackerCenter != null,
        ),
        const SizedBox(height: 16),

        // Step 2
        _StepRow(
          number: '2',
          title: 'You at halfway sideline',
          subtitle: 'Stand at the midpoint of either sideline. Keep phone in hand.',
          isActive: svc.step == CalibrationStep.captureCoach,
          isDone: svc.coachPosition != null,
        ),
        const SizedBox(height: 24),

        // Action button
        SizedBox(
          width: double.infinity,
          child: _actionButton(context, svc),
        ),

        if (svc.step != CalibrationStep.idle) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                svc.cancel();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton(BuildContext context, FieldCalibrationService svc) {
    switch (svc.step) {
      case CalibrationStep.idle:
        return ElevatedButton.icon(
          onPressed: svc.startCalibration,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Calibration'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        );

      case CalibrationStep.waitingTracker:
        // In this step the app waits for the coach to confirm the tracker
        // is on the center spot. The tracker GPS comes from the BLE packet.
        // We use the trackerCenter already set (or show waiting state).
        return svc.trackerCenter != null
            ? ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                label: const Text('Tracker position received ✓'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            : OutlinedButton.icon(
                onPressed: null,
                icon: const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Waiting for tracker GPS…'),
              );

      case CalibrationStep.captureCoach:
        return svc.capturingGps
            ? OutlinedButton.icon(
                onPressed: null,
                icon: const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Getting your GPS…'),
              )
            : ElevatedButton.icon(
                onPressed: svc.captureCoachPosition,
                icon: const Icon(Icons.my_location),
                label: const Text('Capture My Position'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );

      case CalibrationStep.done:
        // Auto-close sheet on success
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return const SizedBox.shrink();
    }
  }
}

class _CalibratedSummary extends StatelessWidget {
  final FieldCalibrationService svc;
  const _CalibratedSummary({required this.svc});

  @override
  Widget build(BuildContext context) {
    final cal = svc.calibration!;
    final width = cal.measuredWidthM.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Field calibrated',
                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              _infoRow('Center spot',
                  '${cal.centerSpot.latitude.toStringAsFixed(5)}, ${cal.centerSpot.longitude.toStringAsFixed(5)}'),
              _infoRow('Your position',
                  '${cal.sidelineMid.latitude.toStringAsFixed(5)}, ${cal.sidelineMid.longitude.toStringAsFixed(5)}'),
              _infoRow('Measured width', '${width}m (standard 55m)'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: svc.startCalibration,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Recalibrate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
      );
}

class _StepRow extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isDone;

  const _StepRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? Colors.greenAccent
                : isActive
                    ? const Color(0xFF2196F3)
                    : Colors.white12,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : Text(number,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    )),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: isActive || isDone ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    color: isActive ? Colors.white54 : Colors.white24,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
