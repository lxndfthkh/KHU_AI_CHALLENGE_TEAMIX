import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildInviteContent({
  required OnboardingWidgets ui,
  required TextEditingController code,
  required String invitationCode,
  required VoidCallback onCheck,
  required VoidCallback onCancel,
}) => [
  ui.title('초대 코드로\n모임에 참가해요.'),
  ui.panel(mint, [
    ui.field('초대 코드 · 시연 $invitationCode', code),
    ui.button('모임 확인하기', onCheck),
  ]),
  ui.button('취소', onCancel),
];
