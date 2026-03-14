// lib/ui/widgets/player_name_dialog.dart
import 'package:flutter/material.dart';

/// Dialog to assign a player name to a device.
/// Returns the entered name, or null if cancelled.
class PlayerNameDialog extends StatefulWidget {
  final String deviceName;
  final String? currentName;

  const PlayerNameDialog({
    super.key,
    required this.deviceName,
    this.currentName,
  });

  @override
  State<PlayerNameDialog> createState() => _PlayerNameDialogState();

  /// Show the dialog and return the entered name (null if cancelled).
  static Future<String?> show(BuildContext context, {
    required String deviceName,
    String? currentName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PlayerNameDialog(
        deviceName: deviceName,
        currentName: currentName,
      ),
    );
  }
}

class _PlayerNameDialogState extends State<PlayerNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: Text(
        'Assign Player — ${widget.deviceName}',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Player name (e.g. Alice Pienaar)',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent),
          ),
        ),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
          child: const Text('Set Name', style: TextStyle(color: Colors.blueAccent)),
        ),
      ],
    );
  }
}
