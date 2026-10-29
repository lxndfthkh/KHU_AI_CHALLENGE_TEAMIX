import 'package:flutter/material.dart';

const ink = Color(0xFF20283F);
const coral = Color(0xFFF07868);
const mint = Color(0xFFEFF7F1);
const butter = Color(0xFFFFF4E8);
const lilac = Color(0xFFF4F1FA);

const teamixPrimary = Color(0xFF739680);
const teamixBackground = Colors.white;
const teamixLogoAccent = Color(0xFFFF5949);

const teamixPeachAccent = Color(0xFFAD886A);
const teamixPurpleAccent = Color(0xFF897B9A);

const teamixAddBackground = Color(0xFFFFF0ED);
const teamixAddForeground = Color(0xFFEC7569);
const teamixAccountBackground = Color(0xFFEAF4ED);

const teamixCardBorder = Color(0xFFEFF0F3);
const teamixEmptyBackground = Color(0xFFF4F8F4);
const teamixEmptyBorder = Color(0xFFDFE6E0);
const teamixEmptyIconBackground = Color(0xFFE6F0E7);
const teamixEmptyIcon = Color(0xFF87A28B);
const teamixEmptyTitle = Color(0xFF414B44);
const teamixEmptyBody = Color(0xFF87918A);

const teamixActionBackground = Color(0xFFF6F7F8);
const teamixActionForeground = Color(0xFF727A8B);
const teamixMuted = Color(0xFF9399A5);
const teamixRequestForeground = Color(0xFF756583);

ThemeData buildTeamixTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: teamixBackground,
  colorScheme: ColorScheme.fromSeed(seedColor: teamixPrimary).copyWith(
    primary: teamixPrimary,
    onPrimary: Colors.white,
    surface: teamixBackground,
    onSurface: ink,
  ),
  fontFamilyFallback: const ['Pretendard', 'Noto Sans KR', 'sans-serif'],
  appBarTheme: const AppBarTheme(
    backgroundColor: teamixBackground,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
    ),
  ),
);
