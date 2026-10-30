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
}
