import 'package:flutter/material.dart';
import 'screens/my_groups_home.dart';
import 'screens/group_home.dart';

// UI preview: bypass authentication and Firebase initialization.
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showEmpty = false});
  final bool showEmpty;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TEAMIX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF739680)),
      fontFamilyFallback: const ['Pretendard', 'Noto Sans KR', 'sans-serif'],
    ),
    builder: (context, child) => _GroupPreviewNavigation(child: child!),
    home: MyGroupsHome(initiallyEmpty: showEmpty),
  );
}

/// Intercepts the old preview snackbar for this group without changing the
/// existing home widget. Replaced by explicit navigation in the home screen.
class _GroupPreviewNavigation extends StatelessWidget {
  const _GroupPreviewNavigation({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
