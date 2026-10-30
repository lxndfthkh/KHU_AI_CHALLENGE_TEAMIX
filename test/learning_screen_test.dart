import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/learning_admin.dart';
import 'package:teamix/screens/learning_screen.dart';
import 'package:teamix/theme.dart';

class FakeLearning implements LearningAdmin {
  LearningStatus current = const LearningStatus();
  final calls = <String>[];

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
    return current = trained;
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
    );
  }

  @override
  Future<void> reset() async {
    calls.add('reset');
    current = const LearningStatus();
  }
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
}
