import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildTermsContent({
  required OnboardingWidgets ui,
  required bool terms,
  required bool privacy,
  required ValueChanged<bool?> onAllChanged,
  required ValueChanged<bool?> onTermsChanged,
  required ValueChanged<bool?> onPrivacyChanged,
  required VoidCallback onDetail,
  required VoidCallback onNext,
  required VoidCallback onBack,
}) => [
  ui.title('시작하기 전,\n확인해 주세요.'),
  const Text('1 / 2 · 약관 동의'),
  ui.panel(butter, [
    CheckboxListTile(
      title: const Text('필수 항목 모두 동의'),
      value: terms && privacy,
      onChanged: ui.busy ? null : onAllChanged,
    ),
    CheckboxListTile(
      title: const Text('[필수] 이용약관'),
      value: terms,
      onChanged: onTermsChanged,
    ),
    CheckboxListTile(
      title: const Text('[필수] 개인정보 수집·이용'),
      value: privacy,
      onChanged: onPrivacyChanged,
    ),
    TextButton(onPressed: onDetail, child: const Text('임시 약관 안내 보기')),
  ]),
  if (terms && privacy) ui.button('동의하고 다음', onNext),
  ui.button('뒤로', onBack),
];
