import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/models/formation.dart';
import 'package:teamix/screens/activity_feedback_flow.dart';
import 'package:teamix/screens/feedback_screen.dart';
import 'package:teamix/screens/formation_screen.dart';
import 'package:teamix/screens/formation_settings_screen.dart';
import 'package:teamix/screens/group_card_palette.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/theme.dart';

import 'activity_flow_test.dart' show FakeBackend, sampleQuestions;
import 'formation_flow_test.dart' show FakeFormation, draftDoc;

ActivityRecord activity(
  String status, {
  int? published,
  DateTime? endedAt,
  bool closed = false,
}) => ActivityRecord(
  id: 'a1',
  groupId: 'g1',
  title: '해커톤',
  description: '',
  status: status,
  participantCount: 8,
  capacity: 20,
  targetTeamSize: 4,
  deadlineAt: DateTime(2030),
  publishedVersion: published,
  endedAt: endedAt,
  feedbackClosed: closed,
);

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  test('후기 기간: 종료 후 7일, 마감되면 닫힌다', () {
    final ended = activity('ended', endedAt: DateTime(2030, 1, 1));
    expect(ended.feedbackOpen, isTrue);
    expect(ended.feedbackDaysLeft(DateTime(2030, 1, 3)), 5);
    expect(ended.feedbackDaysLeft(DateTime(2030, 2, 1)), 0);
    expect(activity('ended', closed: true).feedbackOpen, isFalse);
    expect(activity('active').feedbackDaysLeft(DateTime(2030)), isNull);
  });

  test('편성 설정 패치는 서버 내부 형식으로 나간다', () {
    final json = const FormationSettingsPatch(
      teamCount: 3,
      participants: 8,
      priority: ['time', 'role', 'size'],
      method: 'similar',
      requireCommonTime: true,
      learningEnabled: false,
      requiredRole: ('o2', 1),
    ).toJson();
    expect(json['teamIds'], ['team_1', 'team_2', 'team_3']);
    expect(json['capacity'], {'team_1': 3, 'team_2': 3, 'team_3': 3});
    expect(json['criteria'], [
      {'key': 'time', 'priority': 1},
      {'key': 'role', 'priority': 2},
      {'key': 'size', 'priority': 3},
    ]);
    expect(json['formationMode'], 'similar');
    expect((json['extraRequirements'] as List).first, {'type': 'commonTime'});
    expect((json['extraRequirements'] as List).length, 4);
    expect(json['learningEnabled'], false);
  });

  testWidgets('후기 작성: 별점 4개를 모두 줘야 보내고 동의도 함께 보낸다', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <(Map<String, int>, bool)>[];
    await tester.pumpWidget(
      app(
        FeedbackScreen(
          activityTitle: '해커톤',
          teamName: '2팀',
          onSubmit: (s, c) async => sent.add((s, c)),
        ),
      ),
    );
    await tester.tap(find.text('후기 보내기'));
    await tester.pumpAndSettle();
    expect(find.text('"전체적으로 만족했나요?"에 별점을 주세요.'), findsOneWidget);

    for (final (key, v) in [
      ('overall', 4),
      ('schedule', 3),
      ('roles', 5),
      ('rejoin', 4),
    ]) {
      await tester.tap(find.byKey(ValueKey('star-$key-$v')));
    }
    await tester.tap(find.byKey(const ValueKey('learning-consent')));
    await tester.tap(find.text('후기 보내기'));
    await tester.pumpAndSettle();
    expect(sent.single.$1, {
      'overall': 4,
      'schedule': 3,
      'roles': 5,
      'rejoin': 4,
    });
    expect(sent.single.$2, isTrue);
  });

  Future<void> panel(WidgetTester tester, FakeBackend b, ActivityRecord a) =>
      tester.pumpWidget(
        app(
          Scaffold(
            body: ActivityLifecyclePanel(
              backend: b,
              activity: a,
              palette: GroupCardPalette.defaultJoined,
            ),
          ),
        ),
      );

  testWidgets('활동 단계: 공개 후 시작, 진행 중 종료, 종료 후 후기 마감', (tester) async {
    final b = FakeBackend();
    await panel(tester, b, activity('closed'));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('팀을 편성하고 공개하면 활동을 시작할 수 있어요.'), findsOneWidget);

    await panel(tester, b, activity('closed', published: 1));
    await tester.tap(find.text('활동 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    await panel(tester, b, activity('active', published: 1));
    await tester.tap(find.text('활동 종료하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(b.calls, ['start', 'end']);

    await panel(
      tester,
      b,
      activity('ended', published: 1, endedAt: DateTime.now()),
    );
    await tester.tap(find.text('후기 마감하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(b.calls, ['start', 'end', 'closeFeedback']);

    // Closed feedback: no action left, and no summary screen exists.
    await panel(
      tester,
      b,
      activity('ended', published: 1, endedAt: DateTime.now(), closed: true),
    );
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('후기가 마감됐어요.'), findsOneWidget);
  });

  testWidgets('후기 진입: 팀원만, 쓴 뒤에는 수정하기', (tester) async {
    final b = FakeBackend();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: FeedbackAction(
            backend: b,
            groupId: 'g1',
            activity: activity('ended', published: 1, endedAt: DateTime.now()),
            palette: GroupCardPalette.defaultJoined,
          ),
        ),
      ),
    );
    b.feedback.add(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('후기 남기기 · D-'), findsOneWidget);
    b.feedback.add({'overall': 4});
    await tester.pumpAndSettle();
    expect(find.text('후기 수정하기'), findsOneWidget);
  });

  testWidgets('편성 설정: 저장된 설정을 불러와 순서·팀 수·필수 역할을 바꾼다', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = FakeFormation();
    await tester.pumpWidget(
      app(
        FormationSettingsScreen(
          activity: activity('closed'),
          settings: f.settingsStream.stream,
          learning: f.learning('g1', 'a1'),
          questions: sampleQuestions,
          onSave: (p) => f.saveSettings('g1', 'a1', p),
        ),
      ),
    );
    f.settingsStream.add(
      const FormationSettings(
        teamIds: ['team_1', 'team_2'],
        priority: ['role', 'time', 'experience', 'size'],
        questionCriteria: {
          'role': 'role',
          'time': 'time',
          'experience': 'experience',
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2팀'), findsOneWidget);
    expect(find.text('학습 ↑'), findsOneWidget);
    expect(find.text('학습 ↓'), findsOneWidget);

    await tester.tap(find.byTooltip('팀 늘리기'));
    // Second row (가능 시간) moves up to first.
    await tester.tap(find.byTooltip('위로').at(1));
    await tester.tap(find.text('개발'));
    await tester.tap(find.text('설정 저장'));
    await tester.pumpAndSettle();
    final p = f.saved!;
    expect(p.teamCount, 3);
    expect(p.priority, ['time', 'role', 'experience', 'size']);
    expect(p.requiredRole, ('o2', 1));
  });

  testWidgets('검토 도구: 고정, 선택한 팀만 재편성, 초안 버리기', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = FakeFormation();
    await tester.pumpWidget(
      app(
        FormationScreen(
          groupId: 'g1',
          activity: Stream.value(activity('closed', published: 1)),
          backend: f,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('편성 설정'), findsNothing);
    f.draftStream.add(FormationDraft.fromFirestore(draftDoc()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lock-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lock-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-team_2')));
    await tester.pump();
    await tester.tap(find.text('선택한 팀만 다시 편성 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 초안 버리기 · 공개된 팀은 그대로'));
    await tester.pumpAndSettle();
    expect(f.calls, ['unlock u1', 'lock u2', 'partial [team_2]', 'discard']);
  });

  testWidgets('공개 전에는 편성 설정으로 들어갈 수 있다', (tester) async {
    final f = FakeFormation();
    await tester.pumpWidget(
      app(
        FormationScreen(
          groupId: 'g1',
          activity: Stream.value(activity('closed')),
          backend: f,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('편성 설정'));
    // The settings screen spins until the settings document arrives.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FormationSettingsScreen), findsOneWidget);
  });

  testWidgets('계정 정보: 학습 동의를 바꾸고 계정을 삭제한다', (tester) async {
    final b = FakeBackend();
    var signedOut = false;
    await tester.pumpWidget(
      app(
        MyGroupsHome(
          groups: const [],
          activityBackend: b,
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async => signedOut = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('계정 정보'));
    await tester.pumpAndSettle();
    b.consent.add(false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('account-learning-consent')));
    await tester.pump();
    expect(b.calls, ['consent true']);

    await tester.tap(find.text('계정 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(b.calls.last, 'delete');
    expect(signedOut, isTrue);
  });
}
