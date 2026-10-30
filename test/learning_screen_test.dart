import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/formation_backend.dart';
import 'package:teamix/data/learning_admin.dart';
import 'package:teamix/models/formation.dart';
import 'package:teamix/screens/learning_screen.dart';
import 'package:teamix/theme.dart';

class FakeLearning implements LearningAdmin {
  LearningStatus current = const LearningStatus();
  final calls = <String>[];
  List<CompareTarget> trainedTargets = const [];

  static final trained = LearningStatus.fromJson({
    'active': null,
    'latest': {
      'status': 'candidate',
      'modelId': 'm1',
      'modelStatus': 'candidate',
      'rowCount': 36,
      'activityCount': 6,
      'rmse': {
        'model': 0.28,
        'baseline_mean': 0.69,
        'baseline_weighted_loss': 0.64,
      },
      'b': {
        'time': 1.52,
        'role': 1.17,
        'experience': 0.93,
        'interest': 0.72,
        'size': 1.0,
      },
    },
  });

  @override
  Future<bool> isServiceAdmin() async => true;
  @override
  Future<LearningStatus> status() async => current;
  @override
  Future<LearningStatus> train() async {
    calls.add('train');
    return current = LearningStatus(
      latest: trained.latest,
      targets: trainedTargets,
    );
  }

  @override
  Future<FormationCompare> compare(CompareTarget target) async {
    calls.add('compare ${target.activityId}');
    List<CompareTeam> teams(List<List<int>> g) => [
      for (final t in g) CompareTeam([for (final i in t) '$i'], const ['월 저녁']),
    ];
    return FormationCompare(
      before: teams([
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]),
      after: teams([
        [1, 2, 5, 8],
        [3, 4, 6, 7],
      ]),
      b: const {'time': 1.52, 'interest': 0.72},
    );
  }

  @override
  Future<void> apply(String modelId) async {
    calls.add('apply $modelId');
    current = LearningStatus(
      activeModelId: modelId,
      activeB: trained.latest!.b,
      latest: LearningRun.fromJson({
        'status': 'candidate',
        'modelId': modelId,
        'modelStatus': 'active',
      }),
      targets: trainedTargets,
    );
  }

  @override
  Future<void> reset() async {
    calls.add('reset');
    current = LearningStatus(targets: trainedTargets);
  }
}

/// Forms 1-4 / 5-8 with default weights and 1,2,5,8 / 3,4,6,7 with a model.
class FakeFormation implements FormationBackend {
  FakeFormation(this.admin);

  final FakeLearning admin;
  final drafts = StreamController<FormationDraft?>.broadcast();
  final runs = <String>[];

  @override
  Stream<FormationDraft?> draft(String activityId) => drafts.stream;

  @override
  Future<Map<String, String>> memberNames(String groupId) async => {
    for (var i = 1; i <= 8; i++) 'u$i': '참가자 $i',
  };

  @override
  Future<FormationOutcome> generate(
    String groupId,
    String activityId, {
    required bool republish,
  }) async {
    final learned = admin.current.activeModelId != null;
    runs.add('$activityId ${learned ? 'learned' : 'default'}');
    final groups = learned
        ? [
            [1, 2, 5, 8],
            [3, 4, 6, 7],
          ]
        : [
            [5, 6, 7, 8],
            [1, 2, 3, 4],
          ];
    drafts.add(
      FormationDraft(
        version: runs.length,
        teams: [
          for (final (i, g) in groups.indexed)
            TeamDraft(
              teamId: 't$i',
              members: [for (final m in g) 'u$m'],
              summary: const TeamSummary(),
            ),
        ],
      ),
    );
    return const FormationOutcome(true, '편성했어요');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('학습 관리: 기본값 → 학습 → 적용 → 기본값으로', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final admin = FakeLearning();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeamixTheme(),
        home: LearningScreen(admin: admin),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기본값 · 모든 기준 1.0배'), findsOneWidget);
    expect(find.text('아직 학습한 적이 없어요.'), findsOneWidget);

    await tester.tap(find.text('후기로 학습하기'));
    await tester.pumpAndSettle();
    expect(find.text('검증 통과 · 적용할 수 있어요'), findsOneWidget);
    expect(find.text('학습 데이터 36팀 · 소모임 6개'), findsOneWidget);
    expect(find.text('1.52'), findsOneWidget);

    await tester.tap(find.text('이 보정값 적용'));
    await tester.pumpAndSettle();
    expect(find.text('학습 모델 적용 중 · m1'), findsOneWidget);
    expect(find.text('이 보정값을 편성에 쓰고 있어요.'), findsOneWidget);

    await tester.tap(find.text('기본값으로 되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text('기본값 · 모든 기준 1.0배'), findsOneWidget);
    expect(admin.calls, ['train', 'apply m1', 'reset']);
  });

  testWidgets('편성 비교: 마감된 소모임을 두 방식으로 편성해 바뀐 팀을 보여준다', (tester) async {
    tester.view.physicalSize = const Size(900, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final admin = FakeLearning()
      ..current = LearningStatus.fromJson({
        'targets': [
          {
            'groupId': 'g1',
            'activityId': 'a1',
            'title': '데모 소모임',
            'groupName': '데모 모임',
          },
        ],
      });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeamixTheme(),
        home: LearningScreen(admin: admin),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('데모 모임 · 데모 소모임'), findsOneWidget);

    await tester.tap(find.text('두 방식으로 편성해 보기'));
    await tester.pumpAndSettle();
    expect(admin.calls, ['compare a1']);
    expect(find.text('팀 1 · 1, 2, 3, 4'), findsOneWidget);
    expect(find.text('팀 1 · 1, 2, 5, 8'), findsOneWidget);
    expect(find.textContaining('2팀 바뀜'), findsOneWidget);
    expect(find.text('학습 보정: 시간 1.52배 · 관심사 0.72배'), findsOneWidget);
  });

  testWidgets('시연 버튼: 학습하기와 학습 전으로가 데모 소모임을 다시 편성한다', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final admin = FakeLearning()
      ..current = LearningStatus.fromJson({
        'targets': [
          {'groupId': 'g9', 'activityId': 'other', 'title': '다른 소모임'},
          {
            'groupId': 'g1',
            'activityId': 'mock_compare_act',
            'title': '데모 소모임',
          },
        ],
      });
    final targets = admin.current.targets;
    final formation = FakeFormation(admin);
    addTearDown(formation.drafts.close);
    // Training and reset keep the comparison targets.
    admin.trainedTargets = targets;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeamixTheme(),
        home: LearningScreen(admin: admin, formation: formation),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('데모 소모임을(를) 지금 값으로 다시 편성해요.'), findsOneWidget);

    await tester.tap(find.text('학습하기'));
    await tester.pumpAndSettle();
    expect(admin.calls, ['train', 'apply m1']);
    expect(formation.runs, ['mock_compare_act learned']);
    expect(find.text('현재 편성 · 학습 보정'), findsOneWidget);
    expect(find.text('팀 1 · 참가자 1, 참가자 2, 참가자 5, 참가자 8'), findsOneWidget);

    await tester.tap(find.text('학습 전으로'));
    await tester.pumpAndSettle();
    expect(formation.runs.last, 'mock_compare_act default');
    expect(find.text('현재 편성 · 기본값'), findsOneWidget);
    expect(find.text('팀 1 · 참가자 1, 참가자 2, 참가자 3, 참가자 4'), findsOneWidget);
  });
}
