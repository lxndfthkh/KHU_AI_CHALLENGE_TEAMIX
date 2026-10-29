import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildWelcomeContent({
  required OnboardingWidgets ui,
  required bool hasInvite,
  required VoidCallback onSignup,
  required VoidCallback onLogin,
}) => [
  ui.title('우리 모임이,\n좋은 팀이 되는 곳.'),
  ui.panel(mint, [
    const Icon(Icons.diversity_2, size: 72),
    const Text('초대받은 모임과 함께 시작해요.'),
  ]),
  if (hasInvite) const Text('초대 정보를 유지하고 있어요.'),
  ui.button('회원가입', onSignup),
  ui.button('로그인', onLogin),
];
