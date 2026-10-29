import 'package:flutter/material.dart';
import 'screens/my_groups_home.dart';

// Design preview: intentionally bypass authentication and Firebase startup.
// firebase_options.dart is retained for the future production flow.
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
    home: MyGroupsHome(initiallyEmpty: showEmpty),
  );
}
