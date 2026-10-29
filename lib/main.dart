import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'onboarding.dart';
import 'screens/my_groups_home.dart';

// 실제 실행: Firebase 초기화 후 온보딩부터 시작
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TeamixApp());
}

// 시연·테스트용: 로그인 없이 내 모임 홈부터 보기
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
