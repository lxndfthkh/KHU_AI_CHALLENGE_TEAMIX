import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildInviteContent({
  required OnboardingWidgets ui,
  required TextEditingController code,
  required String invitationCode,
  required VoidCallback onCheck,
  required VoidCallback onCancel,
  bool demo = true,
}) => [
  ui.title('초대 코드로\n모임에 참가해요.'),
  ui.panel(mint, [
    ui.field(demo ? '초대 코드 · 시연 $invitationCode' : '초대 코드 (8자리)', code),
    ui.button('모임 확인하기', onCheck),
  ]),
  ui.button('취소', onCancel),
];
