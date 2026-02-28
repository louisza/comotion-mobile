// lib/data/models/player.dart
import 'package:flutter/material.dart';

/// Static identity of a player (does not change during a session).
class Player {
  final String id;
  final String name;
  final int number;
  final Color color;

  const Player({
    required this.id,
    required this.name,
    required this.number,
    required this.color,
  });

  @override
  bool operator ==(Object other) => other is Player && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
