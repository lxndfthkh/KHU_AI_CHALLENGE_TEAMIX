import 'package:flutter/material.dart';

import '../../widgets/onboarding_widgets.dart';

List<Widget> buildAuthContent({
  required OnboardingWidgets ui,
  required bool signup,
  required TextEditingController nickname,
  required TextEditingController email,
  required TextEditingController password,
  required TextEditingController confirmation,
  required VoidCallback onSubmit,
  required VoidCallback onResetPassword,
  required VoidCallback onBack,
}) => [
  ui.title(signup ? '어떻게 불러드릴까요?' : '다시 만나서 반가워요!'),
  if (signup) ...[const Text('2 / 2 · 최소 계정 정보'), ui.field('닉네임', nickname)],
  ui.field('이메일', email, keyboardType: TextInputType.emailAddress),
  ui.field('비밀번호', password, secret: true),
  if (signup) ui.field('비밀번호 확인', confirmation, secret: true),
  ui.button(
    ui.busy
        ? '처리 중…'
        : signup
        ? '가입하기'
        : '로그인',
    onSubmit,
  ),
  if (!signup)
    TextButton(
      onPressed: ui.busy ? null : onResetPassword,
      child: const Text('비밀번호 재설정'),
    ),
  ui.button('뒤로', onBack),
];
