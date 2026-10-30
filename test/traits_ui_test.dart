import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/models/activity.dart';
import 'package:teamix/models/formation.dart';
import 'package:teamix/screens/create_activity_screen.dart';

Future<NewActivity?> _create(
  WidgetTester tester, {
  bool turnTraitsOff = false,
}) async {
  NewActivity? created;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CreateActivityScreen(
                  groupName: '경희 메이커스',
                  onCreate: (a) async {
                    created = a;
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ChoiceChip).first);
  await tester.enterText(find.byKey(const ValueKey('activity-title')), '스터디');
  await tester.pump();

  final list = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  if (turnTraitsOff) {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('traits-switch')),
      300,
      scrollable: list,
    );
    await tester.tap(find.byKey(const ValueKey('traits-switch')));
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    find.text('소모임 만들기'),
    300,
    scrollable: list,
  );
  await tester.tap(find.text('소모임 만들기'));
  await tester.pumpAndSettle();
  return created;
}

void main() {
  testWidgets('기본 성향 템플릿으로 traits와 personality 우선순위를 보낸다', (tester) async {
    final a = await _create(tester);
    expect(a, isNotNull);
    expect(a!.traits.map((t) => t.id), ['ext', 'lead', 'plan']);
    final traitQuestions = a.questions.where((q) => q.id.startsWith('tr'));
    expect(traitQuestions.length, 6);
    expect(traitQuestions.every((q) => q.type == 'scale'), isTrue);
    expect(a.traits.first.items, [('tr11', false), ('tr12', true)]);

    final matching = a.toJson()['matching']! as Map;
    final priority = matching['priority']! as List;
    expect(priority.first, 'personality');
    expect(priority.last, 'size');
    expect(priority.where((p) => p == 'personality').length, 1);
    final traits = matching['traits']! as List;
    expect((traits.first as Map)['items'], [
      {'questionId': 'tr11'},
      {'questionId': 'tr12', 'reverse': true},
    ]);
  });

  testWidgets('성향 스위치를 끄면 traits 없이 기존 형식 그대로', (tester) async {
    final a = await _create(tester, turnTraitsOff: true);
    expect(a, isNotNull);
    expect(a!.traits, isEmpty);
    expect(a.questions.any((q) => q.id.startsWith('tr')), isFalse);
    final matching = a.toJson()['matching']! as Map;
    expect(matching.containsKey('traits'), isFalse);
    expect(matching['priority'], isNot(contains('personality')));
  });

  test('팀 요약은 성향 축 평균을 1~5 척도로 읽는다', () {
    final s = TeamSummary.fromJson({
      'size': 4,
      'personality': {
        'ext': {'sum': 28, 'items': 2, 'respondents': 4, 'mean': 3.5},
      },
    });
    expect(s.personality['ext']!.mean, 3.5);
    expect(TeamSummary.fromJson({'size': 2}).personality, isEmpty);
  });

  test('설정 문서의 traits로 축 이름과 기본 우선순위를 만든다', () {
    final s = FormationSettings.fromFirestore({
      'questionCriteria': {'role': 'role'},
      'traits': [
        {'id': 'ext', 'label': '외향성', 'items': []},
      ],
    });
    expect(s.traitLabels, {'ext': '외향성'});
    expect(s.defaultPriority, ['personality', 'role', 'size']);
    expect(criterionLabels['personality'], '성향 균형');
  });
}
