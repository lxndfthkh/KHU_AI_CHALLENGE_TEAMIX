import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/onboarding_widgets.dart';

List<Widget> buildCreateGroupContent({
  required OnboardingWidgets ui,
  required TextEditingController name,
  required TextEditingController intro,
  required TextEditingController other,
  required Set<String> categories,
  required void Function(String category, bool selected) onCategorySelected,
  required VoidCallback onCreate,
  required VoidCallback onCancel,
  bool demo = true,
}) => [
  ui.title('함께할 사람들을\n모아보세요.'),
  const Text('팀 편성은 소모임을 만든 뒤 진행해요.'),
  ui.panel(lilac, [
    const Icon(Icons.diversity_2, size: 48),
    const Text('기본 이미지 · 사진 업로드 추후 지원'),
  ]),
  ui.field('모임 이름 *', name),
  ui.field('한 줄 소개 *', intro),
  const Text('관심 카테고리 · 최대 2개'),
  Wrap(
    spacing: 8,
    children: ['친목', '스터디', '프로젝트', '취미', '운동', '기타']
        .map(
          (category) => FilterChip(
            label: Text(category),
            selected: categories.contains(category),
            onSelected: (selected) {
              onCategorySelected(category, selected);
            },
          ),
        )
        .toList(),
  ),
  if (categories.contains('기타')) ui.field('카테고리 직접 입력', other),
  ui.panel(butter, [
    const Text('생성자는 승인 없이 대표자가 됩니다. 비공개 배치 선호 열람 권한은 포함되지 않습니다.'),
  ]),
  ui.button(demo ? '모임 만들기 · 시연' : '모임 만들기', onCreate),
  ui.button('취소', onCancel),
];
