import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/invite_code_dialog.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildShareInviteContent({
  required OnboardingWidgets ui,
  required String group,
  required VoidCallback onSkip,
  bool demo = true,
  String? inviteCode,
  VoidCallback? onIssueInvite,
}) => [
  ui.title(demo ? '모임 생성 완료 · 시연' : '모임 생성 완료'),
  ui.panel(mint, [ui.title(group), const Text('대표자 · 별도 승인 없음')]),
  if (demo)
    const Text('초대 링크 / 코드 공유\n실제 모임 저장 및 초대 발급 전이므로 공유는 아직 사용할 수 없어요.')
  else if (inviteCode != null)
    InviteCodeCard(code: inviteCode)
  else if (onIssueInvite != null) ...[
    const Text('초대 링크 / 코드 공유'),
    ui.button('초대 코드 만들기', onIssueInvite),
  ],
  ui.button(inviteCode == null ? '건너뛰기' : '완료', onSkip),
];
