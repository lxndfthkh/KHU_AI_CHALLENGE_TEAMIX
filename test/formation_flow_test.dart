import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/data/formation_backend.dart';
import 'package:teamix/models/activity.dart';
import 'package:teamix/models/formation.dart';
import 'package:teamix/screens/formation_screen.dart';
import 'package:teamix/theme.dart';
import 'package:teamix/widgets/my_team_card.dart';

const questions = [
  ActivityQuestion(
    id: 'role',
    label: '희망 역할',
    type: 'single',
    options: [QuestionOption('o1', '기획'), QuestionOption('o2', '개발')],
  ),
  ActivityQuestion(
    id: 'time',
    label: '가능 시간',
    type: 'multiple',
    options: [QuestionOption('o1', '평일 저녁'), QuestionOption('o2', '주말')],
  ),
];

ActivityRecord activityIn(String status, {int? published}) => ActivityRecord(
  id: 'a1',
  groupId: 'g1',
  title: '해커톤',
  description: '',
  deadlineAt: DateTime(2030),
  capacity: 10,
  targetTeamSize: 2,
  status: status,
  participantCount: 4,
  publishedVersion: published,
);

/// Server draft document as repository.draft_to_doc writes it.
Map<String, dynamic> draftDoc({bool valid = true}) => {
  'version': 3,
  'teams': [
    {
      'teamId': 'team_1',
      'members': ['u1', 'u2'],
    },
    {
      'teamId': 'team_2',
      'members': ['u3'],
    },
  ],
  'unassigned': ['u4'],
  'locks': {
    'u1': {'teamId': 'team_1', 'type': 'manual'},
  },
  'discarded': false,
  'validation': {
    'valid': valid,
    'conflicts': valid ? [] : ['미배정 참가자가 있습니다'],
    'summary': {
      'team_1': {
        'members': ['u1', 'u2'],
        'size': 2,
        'commonTimes': ['o2'],
        'rolePreferences': {'o1': 1, 'o2': 1},
        'selfReportedExperience': {'sum': 7, 'respondents': 2, 'mean': 3.5},
      },
    },
  },
};

class FakeFormation implements FormationBackend {
  final draftStream = StreamController<FormationDraft?>.broadcast();
  final calls = <String>[];
  List<String> problems = const [];

  FormationDraft? _shown;

  /// Bump to simulate a sign-up or cancellation after the operator reviewed.
  int roster = 1;

  @override
  Stream<FormationDraft?> draft(String groupId, String activityId) =>
      draftStream.stream.map((d) => _shown = d);
  List<PublishedTeam> published = const [];
  @override
  Future<List<PublishedTeam>> publishedTeams(String a, int version) async =>
      published;
  @override
  Future<Map<String, Object>> reviewVersions(String g, String a) async => {
    'roster': roster,
    'settings': 1,
    'draft': _shown?.version ?? 0,
  };
  @override
  Future<Map<String, String>> memberNames(String groupId) async => {
    'u1': '가나',
    'u2': '다라',
    'u3': '마바',
    'u4': '사아',
  };
  @override
  Future<List<String>> precheck(String g, String a) async => problems;
  @override
  Future<FormationOutcome> closeRecruitment(String g, String a) async {
    calls.add('close');
    return const FormationOutcome(true, '신청을 마감했어요.');
  }

  @override
  Future<FormationOutcome> generate(
    String g,
    String a, {
    required bool republish,
  }) async {
    calls.add(republish ? 'republish' : 'generate');
    return const FormationOutcome(true, '추천 편성안을 만들었어요.');
  }

  @override
  Future<FormationOutcome> move(
    String g,
    String a,
    String uid,
    String? t,
  ) async {
    calls.add('move $uid ${t ?? '-'}');
    return const FormationOutcome(true, '옮겼어요.');
  }

  @override
  Future<FormationOutcome> publish(
    String g,
    String a, {
    required Map<String, Object> reviewed,
  }) async {
    if (reviewed['roster'] != roster) {
      calls.add('publish stale');
      return ServerFormationBackend.reviewedStale;
    }
    calls.add('publish');
    return const FormationOutcome(true, '팀을 공개했어요.');
  }

  final settingsStream = StreamController<FormationSettings?>.broadcast();
  FormationSettingsPatch? saved;
  @override
  Stream<FormationSettings?> settings(String a) => settingsStream.stream;
  @override
  Future<(bool, Map<String, String>)> learning(String g, String a) async =>
      (true, {'time': 'up', 'experience': 'down'});
  @override
  Future<FormationOutcome> saveSettings(
    String g,
    String a,
    FormationSettingsPatch patch,
  ) async {
    saved = patch;
    calls.add('settings');
    return const FormationOutcome(true, '편성 설정을 저장했어요.');
  }

  @override
  Future<FormationOutcome> setLocked(
    String g,
    String a,
    String uid, {
    required bool locked,
  }) async {
    calls.add('${locked ? 'lock' : 'unlock'} $uid');
    return const FormationOutcome(true, '고정');
  }

  @override
  Future<FormationOutcome> generatePartial(
    String g,
    String a,
    List<String> teamIds,
  ) async {
    calls.add('partial $teamIds');
    return const FormationOutcome(true, '부분');
  }

  @override
  Future<FormationOutcome> discardDraft(String g, String a) async {
    calls.add('discard');
    return const FormationOutcome(true, '버림');
  }
}

Widget screen(FakeFormation backend, ActivityRecord activity) => MaterialApp(
  theme: buildTeamixTheme(),
  home: FormationScreen(
    groupId: 'g1',
    activity: Stream.value(activity),
    backend: backend,
    questions: questions,
  ),
);

void main() {
  test('서버 초안 문서를 팀·요약·고정으로 읽는다', () {
    final d = FormationDraft.fromFirestore(draftDoc(valid: false));
    expect(d.version, 3);
    expect(d.teams.map((t) => t.teamId), ['team_1', 'team_2']);
    expect(d.unassigned, ['u4']);
    expect(d.locked, {'u1'});
    expect(d.valid, isFalse);
    expect(d.conflicts, ['미배정 참가자가 있습니다']);
    final s = d.teams.first.summary;
    expect(s.commonTimes, ['o2']);
    expect(s.roleCounts, {'o1': 1, 'o2': 1});
    expect(s.experienceMean, 3.5);
    expect(d.teams.last.summary.size, 0);
    expect(d.usable, isTrue);
  });

  test('팀 ID는 n팀으로 보인다', () {
    expect(teamLabel('team_3'), '3팀');
    expect(teamLabel('blue'), 'blue');
  });

  testWidgets('모집 중이면 신청 마감부터 한다', (tester) async {
    final backend = FakeFormation();
    await tester.pumpWidget(screen(backend, activityIn('recruiting')));
    await tester.pumpAndSettle();
    expect(find.textContaining('지금 4명이 신청했어요'), findsOneWidget);
    await tester.tap(find.text('신청 마감하고 편성 시작'));
    await tester.pumpAndSettle();
    expect(backend.calls, ['close']);
    expect(find.text('신청을 마감했어요.'), findsOneWidget);
  });

  testWidgets('편성안: 팀 요약을 라벨로 보여주고 옮기기·공개를 보낸다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeFormation();
    await tester.pumpWidget(screen(backend, activityIn('closed')));
    await tester.pumpAndSettle();
    expect(find.text('AI로 편성하기'), findsOneWidget);

    backend.draftStream.add(FormationDraft.fromFirestore(draftDoc()));
    await tester.pumpAndSettle();
    expect(find.text('1팀 · 2명'), findsOneWidget);
    expect(find.text('공통 시간 주말'), findsOneWidget);
    expect(find.text('역할 기획 1 · 개발 1'), findsOneWidget);
    expect(find.text('경험 평균 3.5'), findsOneWidget);
    expect(find.text('미배정 · 1명'), findsOneWidget);
    expect(find.text('사아'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    await tester.tap(find.text('옮기기').at(2)); // 마바 in 2팀
    await tester.pumpAndSettle();
    await tester.tap(find.text('1팀 · 2명').last);
    await tester.pumpAndSettle();
    expect(backend.calls, ['move u3 team_1']);

    await tester.tap(find.text('팀 공개하기'));
    await tester.pumpAndSettle();
    expect(backend.calls.last, 'publish');
  });

  testWidgets('검토한 뒤 신청이 바뀌면 공개하지 않고, 다시 확인하면 공개한다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeFormation();
    await tester.pumpWidget(screen(backend, activityIn('closed')));
    await tester.pumpAndSettle();
    backend.draftStream.add(FormationDraft.fromFirestore(draftDoc()));
    await tester.pumpAndSettle();

    backend.roster = 2; // someone cancels while the operator is reviewing
    await tester.tap(find.text('팀 공개하기'));
    await tester.pumpAndSettle();
    expect(backend.calls.last, 'publish stale');
    expect(find.textContaining('검토한 뒤에 신청·설정·초안이 바뀌어'), findsOneWidget);

    // The screen takes a fresh review of the draft it shows; then it publishes.
    await tester.tap(find.text('팀 공개하기'));
    await tester.pumpAndSettle();
    expect(backend.calls.last, 'publish');
  });

  testWidgets('공개 후에는 공개된 팀 구성을 보여준다', (tester) async {
    final backend = FakeFormation()
      ..published = [
        PublishedTeam.fromFirestore({
          'teamId': 'team_1',
          'members': [
            {'uid': 'u1', 'displayName': '가나'},
            {'uid': 'u2', 'displayName': '다라'},
          ],
          'size': 2,
          'commonTimes': ['weekend'],
        }),
        const PublishedTeam(teamId: 'team_2', names: ['마바', '사아']),
      ];
    await tester.pumpWidget(
      screen(backend, activityIn('closed', published: 1)),
    );
    await tester.pumpAndSettle();
    backend.draftStream.add(null);
    await tester.pumpAndSettle();
    expect(find.text('1팀 · 2명'), findsOneWidget);
    expect(find.text('가나, 다라'), findsOneWidget);
    expect(find.text('2팀 · 2명'), findsOneWidget);
    expect(find.text('마바, 사아'), findsOneWidget);
  });

  testWidgets('충돌 안내는 팀 ID 대신 팀 이름으로 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeFormation()..problems = ['team_2: 정원 초과'];
    await tester.pumpWidget(screen(backend, activityIn('closed')));
    await tester.pumpAndSettle();
    expect(find.text('· 2팀: 정원 초과'), findsOneWidget);
  });

  testWidgets('필수 조건을 못 채운 편성안은 공개할 수 없다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeFormation()..problems = ['참가자보다 팀이 많습니다'];
    await tester.pumpWidget(screen(backend, activityIn('closed')));
    await tester.pumpAndSettle();
    expect(find.text('· 참가자보다 팀이 많습니다'), findsOneWidget);

    backend.draftStream.add(
      FormationDraft.fromFirestore(draftDoc(valid: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('· 미배정 참가자가 있습니다'), findsOneWidget);
    final publish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '팀 공개하기'),
    );
    expect(publish.onPressed, isNull);
  });

  testWidgets('공개 후에는 기존 팀을 유지하는 재편성을 쓴다', (tester) async {
    final backend = FakeFormation();
    await tester.pumpWidget(
      screen(backend, activityIn('closed', published: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('공개된 팀'), findsOneWidget);
    await tester.tap(find.text('기존 팀 유지하며 다시 편성'));
    await tester.pumpAndSettle();
    expect(backend.calls, ['republish']);
  });

  testWidgets('내 팀 카드: 공개 전에는 숨고, 공개되면 팀원과 공통 시간을 보여준다', (tester) async {
    final team = StreamController<MyTeam?>.broadcast();
    addTearDown(team.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyTeamCard(
            team: () => team.stream,
            questions: () async => questions,
          ),
        ),
      ),
    );
    team.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-team-card')), findsNothing);

    team.add(
      MyTeam.fromFirestore({
        'teamId': 'team_2',
        'members': [
          {'uid': 'u1', 'displayName': '가나', 'role': 'o2'},
          {'uid': 'u2', 'displayName': '다라', 'role': null},
        ],
        'commonTimes': ['o1'],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('내 팀 · 2팀'), findsOneWidget);
    expect(find.text('가나 · 개발'), findsOneWidget);
    expect(find.text('다라'), findsOneWidget);
    expect(find.text('모두 가능한 시간 · 평일 저녁'), findsOneWidget);
  });
}
