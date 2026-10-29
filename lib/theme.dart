import 'package:flutter/material.dart';

const ink = Color(0xFF202438),
    coral = Color(0xFFF07868),
    mint = Color(0xFFE0F2E8),
    butter = Color(0xFFFFF0BF),
    lilac = Color(0xFFEDE6FA);

ThemeData buildTeamixTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFFFFEFA),
  colorScheme: ColorScheme.fromSeed(seedColor: coral)
      .copyWith(primary: coral, onPrimary: ink),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
  ),
);
