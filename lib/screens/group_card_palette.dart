import 'package:flutter/material.dart';

/// Joined-group indices exclude pending groups; pending always uses lavender.
class GroupCardPalette {
  const GroupCardPalette(this.background, this.accent);
  final Color background;
  final Color accent;

  static const joined = <GroupCardPalette>[
    GroupCardPalette(Color(0xFFEFF7F1), Color(0xFF739680)),
    GroupCardPalette(Color(0xFFFFF4E8), Color(0xFFAD886A)),
    GroupCardPalette(Color(0xFFEDF4FC), Color(0xFF7898BA)),
    GroupCardPalette(Color(0xFFFCEFF2), Color(0xFFB58394)),
  ];
  static const pending = GroupCardPalette(Color(0xFFF4F1FA), Color(0xFF897B9A));

  static GroupCardPalette forGroup(int joinedIndex, {bool isPending = false}) {
    if (isPending) return pending;
    return joined[joinedIndex % joined.length];
  }
}
