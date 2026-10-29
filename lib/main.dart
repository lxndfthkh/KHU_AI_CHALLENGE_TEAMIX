import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'onboarding.dart';

// 실제 실행: Firebase 초기화 후 온보딩부터 시작
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TeamixApp());
}

// 시연·테스트용: 로그인 없이 내 모임 홈부터 보기
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showEmpty = false});

  final bool showEmpty;

  @override
  Widget build(BuildContext context) => TeamixApp(
    demoMode: true,
    showEmpty: showEmpty,
  );
}
