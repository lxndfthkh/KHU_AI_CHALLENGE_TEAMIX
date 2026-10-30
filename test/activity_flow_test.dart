import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/activity_backend.dart';
import 'package:teamix/models/activity.dart';
import 'package:teamix/screens/create_activity_screen.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/registration_screen.dart';
import 'package:teamix/theme.dart';

const sampleQuestions = [
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
    options: [QuestionOption('o1', '평일'), QuestionOption('o2', '주말')],
    order: 1,
  ),
  ActivityQuestion(id: 'experience', label: '경험 수준', type: 'scale', order: 2),
];

final activity = Activity(
  id: 'a1',
  groupId: 'g1',
  title: '캠퍼스 해커톤',
  description: '함께 만들어요',
  capacity: 20,
  targetTeamSize: 4,
  deadline: DateTime(2030, 1, 1),
  status: 'recruiting',
  participantCount: 6,
);

/// In-memory backend recording what the screens send.
class FakeBackend implements ActivityBackend {
  final list = StreamController<List<Activity>>.broadcast();
  final registration = StreamController<Registration?>.broadcast();
  final created = <(String, NewActivity)>[];
  final submitted = <Map<String, Object>>[];
  final updated = <Map<String, Object>>[];

  @override
  Stream<List<Activity>> activities(String groupId) => list.stream;
  @override
  Future<List<ActivityQuestion>> questions(String activityId) async =>
      sampleQuestionsOverride;
  List<ActivityQuestion> sampleQuestionsOverride = sampleQuestions;
  @override
  Stream<Registration?> myRegistration(String groupId, String activityId) =>
      registration.stream;
  @override
  Future<String> createActivity(String groupId, NewActivity a) async {
    created.add((groupId, a));
    return 'new';
  }

  @override
  Future<void> submitRegistration(String id, Map<String, Object> a) async =>
      submitted.add(a);
  @override
  Future<void> updateRegistration(String id, Map<String, Object> a) async =>
      updated.add(a);
  @override
  Future<void> cancelRegistration(String id) async {}
}

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  test('Activity는 createActivity가 쓴 문서를 읽는다', () {
    final a = Activity.fromFirestore('a1', {
      'groupId': 'g1',
      'title': '해커톤',
      'capacity': 10,
      'targetTeamSize': 3,
      'deadlineAt': Timestamp.fromDate(DateTime(2030)),
      'status': 'closed',
      'participantCount': 7,
      'publishedVersion': 2,
    });
    expect(a.estimatedTeamCount, 3);
    expect(a.published, isTrue);
    expect(a.statusLabel, '팀 공개');
    expect(a.deadline, DateTime(2030));
  });

  test('NewActivity는 functions의 createActivity 형식으로 보낸다', () {
    final json = NewActivity(
      title: ' 해커톤 ',
      capacity: 20,
      targetTeamSize: 4,
      deadline: DateTime(2030),
      questions: sampleQuestions,
      criteria: {'role': 'role', 'time': 'time', 'experience': 'experience'},
      requireCommonTime: true,
    ).toJson();
    expect(json['title'], '해커톤');
    expect(json['deadlineAt'], DateTime(2030).millisecondsSinceEpoch);
    final qs = json['questions']! as List;
    expect(qs.first, {
      'id': 'role',
      'label': '희망 역할',
      'type': 'single',
      'options': [
        {'id': 'o1', 'label': '기획'},
        {'id': 'o2', 'label': '개발'},
      ],
      'required': true,
    });
    expect((qs.last as Map).containsKey('options'), isFalse);
    expect(json['matching'], {
      'method': 'balanced',
      'questionCriteria': {
        'role': 'role',
        'time': 'time',
        'experience': 'experience',
      },
      'priority': ['role', 'time', 'experience', 'size'],
      'requireCommonTime': true,
    });
  });

  group('Firestore 읽기', () {
    late FakeFirebaseFirestore db;
    late FirebaseActivityBackend backend;
    setUp(() async {
      db = FakeFirebaseFirestore();
      backend = FirebaseActivityBackend(db, 'me');
      for (final (id, status, minute) in [
        ('old', 'recruiting', 1),
        ('new', 'closed', 2),
        ('done', 'ended', 3),
      ]) {
        await db.doc('activities/$id').set({
          'groupId': 'g1',
          'title': id,
          'status': status,
          'capacity': 10,
          'targetTeamSize': 2,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 0, minute)),
        });
      }
      await db.doc('activities/other').set({
        'groupId': 'g2',
        'title': 'other',
        'status': 'recruiting',
        'createdAt': Timestamp.now(),
      });
    });

    test('모임의 진행 중 소모임만 최신순으로', () async {
      final list = await backend.activities('g1').first;
      expect(list.map((a) => a.id), ['new', 'old']);
    });

    test('질문은 켜진 것만 순서대로', () async {
      await db.doc('activities/old/questions/time').set({
        'label': '시간',
        'type': 'multiple',
        'options': [
          {'id': 'o1', 'label': '평일'},
        ],
        'order': 2,
        'enabled': true,
      });
      await db.doc('activities/old/questions/role').set({
        'label': '역할',
        'type': 'single',
        'options': [],
        'order': 1,
        'enabled': true,
      });
      await db.doc('activities/old/questions/mbti').set({
        'label': 'MBTI',
        'type': 'single',
        'order': 3,
        'enabled': false,
      });
      final qs = await backend.questions('old');
      expect(qs.map((q) => q.id), ['role', 'time']);
      expect(qs.last.options.single.label, '평일');
    });

    test('내 신청은 없으면 null, 생기면 바로 보인다', () async {
      final stream = backend.myRegistration('g1', 'old');
      expect(await stream.first, isNull);
      await db.doc('registrations/old_me').set({
        'groupId': 'g1',
        'activityId': 'old',
        'userId': 'me',
        'status': 'submitted',
        'answers': {'role': 'o1'},
      });
      final mine = await stream.first;
      expect(mine?.submitted, isTrue);
      expect(mine?.answers, {'role': 'o1'});
    });
  });

  testWidgets('소모임 창설: 입력값을 확인하고 형식에 맞게 보낸다', (tester) async {
    // Tall enough that the whole form is built without scrolling.
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <NewActivity>[];
    await tester.pumpWidget(
      app(
        CreateActivityScreen(
          groupName: '경희 메이커스',
          now: () => DateTime(2026, 10, 30),
          onCreate: (a) async => sent.add(a),
        ),
      ),
    );
    final submit = find.text('소모임 만들기');

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('소모임 이름을 1~120자로 입력해 주세요.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('activity-title')), '해커톤');
    await tester.enterText(
      find.byKey(const ValueKey('activity-team-size')),
      '30',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('팀당 인원은 1~50명, 모집 정원 이하로 입력해 주세요.'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('activity-team-size')),
      '4',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final a = sent.single;
    expect(a.title, '해커톤');
    expect(a.capacity, 20);
    expect(a.targetTeamSize, 4);
    expect(a.deadline, DateTime(2026, 11, 6, 23, 59));
    expect(a.criteria.keys, ['role', 'time', 'experience', 'interest']);
    expect(a.questions.first.options.map((o) => o.id), [
      'o1',
      'o2',
      'o3',
      'o4',
    ]);
    expect(a.questions[2].label, '경험 수준');
  });

  testWidgets('참가 신청: 필수 질문을 모두 답해야 보낸다', (tester) async {
    final sent = <Map<String, Object>>[];
    await tester.pumpWidget(
      app(
        RegistrationScreen(
          activity: activity,
          questions: sampleQuestions,
          onSubmit: (a) async => sent.add(a),
        ),
      ),
    );
    await tester.tap(find.text('신청하기'));
    await tester.pump();
    expect(find.text('"희망 역할"에 답해 주세요.'), findsOneWidget);

    await tester.tap(find.text('개발'));
    await tester.tap(find.text('주말'));
    await tester.tap(find.text('평일'));
    await tester.tap(find.text('4'));
    await tester.tap(find.text('신청하기'));
    await tester.pumpAndSettle();
    expect(sent.single, {
      'role': 'o2',
      'time': ['o1', 'o2'],
      'experience': 4,
    });
  });

  testWidgets('모임 홈: 실제 소모임을 보여주고 신청까지 이어진다', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      app(
        GroupHome(
          groupName: '경희 메이커스',
          isOperator: true,
          groupId: 'g1',
          activityBackend: backend,
        ),
      ),
    );
    backend.list.add([activity]);
    await tester.pump();
    expect(find.text('캠퍼스 해커톤'), findsOneWidget);
    expect(find.text('6 / 20명 · 팀당 4명'), findsOneWidget);
    expect(find.text('모집 중'), findsOneWidget);

    await tester.ensureVisible(find.text('소모임 상세보기 ↗'));
    await tester.tap(find.text('소모임 상세보기 ↗'));
    await tester.pumpAndSettle();
    backend.registration.add(null);
    await tester.pump();
    await tester.tap(find.text('참가 신청하기'));
    await tester.pumpAndSettle();
    expect(find.byType(RegistrationScreen), findsOneWidget);

    await tester.tap(find.text('기획'));
    await tester.tap(find.text('평일'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('신청하기'));
    await tester.pumpAndSettle();
    expect(backend.submitted.single, {
      'role': 'o1',
      'time': ['o1'],
      'experience': 3,
    });

    backend.registration.add(
      const Registration(status: 'submitted', answers: {'role': 'o1'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('신청 완료 · 응답 수정하기'), findsOneWidget);
  });

  testWidgets('모임 홈: 소모임 창설은 실제 생성 화면을 연다', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      app(
        GroupHome(
          groupName: '경희 메이커스',
          isOperator: true,
          groupId: 'g1',
          activityBackend: backend,
        ),
      ),
    );
    backend.list.add(const []);
    await tester.pump();
    expect(find.text('아직 소모임이 없어요. 소모임 창설로 첫 활동을 열어 보세요.'), findsOneWidget);
    await tester.tap(find.text('소모임 창설'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateActivityScreen), findsOneWidget);
  });
}
