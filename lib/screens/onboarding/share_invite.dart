import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildShareInviteContent({
  required OnboardingWidgets ui,
  required String group,
  required VoidCallback onSkip,
  bool demo = true,
}) => [
  ui.title(demo ? '모임 생성 완료 · 시연' : '모임 생성 완료'),
  ui.panel(mint, [ui.title(group), const Text('대표자 · 별도 승인 없음')]),
  Text(
    demo
        ? '초대 링크 / 코드 공유\n실제 모임 저장 및 초대 발급 전이므로 공유는 아직 사용할 수 없어요.'
        : '초대 링크 / 코드 공유\n모임은 저장됐어요. 초대 발급은 아직 지원하지 않아 공유는 사용할 수 없어요.',
  ),
  ui.button('건너뛰기', onSkip),
];
