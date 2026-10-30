import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/main.dart';
import 'package:teamix/screens/group_card_palette.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/subgroup_detail_screen.dart';

void main() {
  testWidgets('Makers opens operator home and returns to groups', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('경희 메이커스'));
    await tester.pumpAndSettle();
    expect(find.text('운영진'), findsOneWidget);
    expect(find.text('가입 요청 관리'), findsOneWidget);
    expect(find.text('부원 관리'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNWidgets(2));
    expect(find.text('활동 후기'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('내 모임으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('내 모임'), findsOneWidget);
  });

  testWidgets('모임 홈은 목록 카드와 같은 색을 쓴다', (tester) async {
    await tester.pumpWidget(const MyApp());
    // Second joined card in the rotation: butter.
    await tester.tap(find.text('주말 산책 모임'));
    await tester.pumpAndSettle();

    final home = tester.widget<GroupHome>(find.byType(GroupHome));
    expect(home.palette, same(GroupCardPalette.joined[1]));
    final badge = find.ancestor(
      of: find.text('부원'),
      matching: find.byType(Container),
    );
    final decoration =
        tester.widget<Container>(badge.first).decoration! as BoxDecoration;
    expect(decoration.color, GroupCardPalette.joined[1].background);

    // The subgroup detail keeps the same group color.
    await tester.ensureVisible(find.text('소모임 상세보기 ↗').first);
    await tester.tap(find.text('소모임 상세보기 ↗').first);
    await tester.pumpAndSettle();
    final detail = tester.widget<SubgroupDetailScreen>(
      find.byType(SubgroupDetailScreen),
    );
    expect(detail.palette, same(GroupCardPalette.joined[1]));
    final status = find.ancestor(
      of: find.text('모집 중'),
      matching: find.byType(Material),
    );
    expect(
      tester.widget<Material>(status.first).color,
      GroupCardPalette.joined[1].background,
    );
    expect(tester.takeException(), isNull);
  });
}
