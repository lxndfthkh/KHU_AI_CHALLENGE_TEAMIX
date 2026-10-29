import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildShareInviteContent({
  required OnboardingWidgets ui,
  required String group,
  required VoidCallback onSkip,
}) => [
  ui.title('모임 생성 완료 · 시연'),
  ui.panel(mint, [ui.title(group), const Text('대표자 · 별도 승인 없음')]),
  const Text('초대 링크 / 코드 공유\n실제 모임 저장 및 초대 발급 전이므로 공유는 아직 사용할 수 없어요.'),
  ui.button('건너뛰기', onSkip),
];
