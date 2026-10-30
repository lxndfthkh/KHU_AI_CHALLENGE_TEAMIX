import 'package:flutter/material.dart';

import '../theme.dart';

/// Joined-group indices exclude pending groups; pending always uses lavender.
class GroupCardPalette {
  const GroupCardPalette(this.background, this.accent);
  final Color background;
  final Color accent;

  static const joined = <GroupCardPalette>[
    defaultJoined,
    GroupCardPalette(butter, teamixPeachAccent),
    GroupCardPalette(Color(0xFFEDF4FC), Color(0xFF7898BA)),
    GroupCardPalette(Color(0xFFFCEFF2), Color(0xFFB58394)),
  ];
  static const pending = GroupCardPalette(lilac, teamixPurpleAccent);
  static const defaultJoined = GroupCardPalette(mint, teamixPrimary);

  static GroupCardPalette forGroup(int joinedIndex, {bool isPending = false}) {
    if (isPending) return pending;
    return joined[joinedIndex % joined.length];
  }
}
