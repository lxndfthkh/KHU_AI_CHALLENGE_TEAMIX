import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/demo_group_repository.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/screens/subgroup_detail_screen.dart';
import 'package:teamix/theme.dart';

void main() {
  Widget detail(bool isOperator) => MaterialApp(
        theme: buildTeamixTheme(),
        home: SubgroupDetailScreen(
          groupName: '경희 메이커스',
          subgroup: DemoGroupRepository.subgroupsFor('경희 메이커스').first,
          isOperator: isOperator,
        ),
      );

  for (final isOperator in [true, false]) {
    testWidgets('상세 관리 박스와 하단 안내: isOperator=$isOperator', (tester) async {
      await tester.pumpWidget(detail(isOperator));
      expect(find.text('캠퍼스 불편 해결 미니 프로젝트'), findsOneWidget);
      expect(find.text('12 / 20명'), findsOneWidget);
      expect(find.text('4팀 · 팀당 5명'), findsOneWidget);
      expect(find.text('10월 30일 · 15:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('subgroup-operator-panel')),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text('신청 현황 · 12명'),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text('팀 편성 관리 →'),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text(isOperator
          ? '운영진도 신청하면 팀 편성에 참여할 수 있어요.'
          : '설문을 제출하면 참가 신청이 완료돼요.'), findsOneWidget);
      await tester.tap(find.text('참가 신청하기'));
      await tester.pump();
      expect(find.text('참가 신청 기능은 준비 중이에요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('역할별 메뉴와 준비 중 안내: isOperator=$isOperator', (tester) async {
      await tester.pumpWidget(detail(isOperator));
      await tester.tap(find.byTooltip('소모임 메뉴'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('소모임 정보 수정'),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text('모집 마감하기'),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text('활동 종료하기'),
          isOperator ? findsOneWidget : findsNothing);
      expect(find.text('소모임 링크 공유'),
          isOperator ? findsNothing : findsOneWidget);
      final item = isOperator ? '소모임 정보 수정' : '소모임 링크 공유';
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
      expect(find.text('$item 기능은 준비 중이에요.'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in ['owner', 'member']) {
    testWidgets('내 모임에서 상세까지 역할 전달: $role', (tester) async {
      final repository = DemoGroupRepository(seedExamples: true);
      final name = role == 'owner' ? '경희 메이커스' : '주말 산책 모임';
      await tester.pumpWidget(MaterialApp(
        theme: buildTeamixTheme(),
        home: MyGroupsHome(
          groups: DemoGroupRepository.summariesOf(repository),
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async {},
        ),
      ));
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(GroupHome), findsOneWidget);
      await tester.ensureVisible(find.text('소모임 상세보기 ↗').first);
      await tester.tap(find.text('소모임 상세보기 ↗').first);
      await tester.pumpAndSettle();
      final screen = tester.widget<SubgroupDetailScreen>(
          find.byType(SubgroupDetailScreen));
      expect(screen.isOperator, role == 'owner');
      expect(screen.groupName, name);
      expect(tester.takeException(), isNull);
    });
  }
}
