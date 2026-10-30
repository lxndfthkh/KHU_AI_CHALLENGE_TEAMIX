import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildGroupPreviewContent({
  required OnboardingWidgets ui,
  required String group,
  required VoidCallback onRequest,
  required VoidCallback onCancel,
  String? description,
  bool demo = true,
}) => [
  ui.title('초대받은 모임이에요.'),
  ui.panel(mint, [
    ui.title(group),
    Text(description ?? '캠퍼스의 작은 불편을 함께 해결해요.\n인원 20명 · 가상 데이터'),
  ]),
  const Text('참여 요청 후 운영진 승인이 필요해요.'),
  ui.button(demo ? '참여 요청 보내기 · 시연' : '참여 요청 보내기', onRequest),
  ui.button('참여 취소', onCancel),
];
