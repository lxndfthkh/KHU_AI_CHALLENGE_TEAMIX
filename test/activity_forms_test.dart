import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/activity_registration.dart';
import 'package:teamix/data/feedback_learning_api.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/screens/activity_forms.dart';
import 'package:teamix/screens/registration_action.dart';

class FakeActivityApi implements ActivityRegistrationApi {
  final changes = StreamController<Map<String, dynamic>?>.broadcast();
  Map<String, dynamic>? registration, created, sent;
  bool? wasEditing;
  Object? failure;
  @override
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> data) async {
    created = {'groupId': groupId, ...data};
    return {'activityId': 'newactivity'};
  }
  @override
  Future<List<Map<String, dynamic>>> questions(String activityId) async => [
    for (final id in ['role', 'time', 'interest', 'experience']) {
      'id': id, 'label': id, 'required': true,
      'type': id == 'role' ? 'single' : id == 'experience' ? 'scale' : 'multiple',
      'options': id == 'experience' ? [] : [
        {'id': 'a', 'label': '$id A'}, {'id': 'b', 'label': '$id B'},
      ],
    },
  ];
  @override
  Stream<Map<String, dynamic>?> ownRegistration(String groupId, String activityId) async* {
    yield registration;
    yield* changes.stream;
  }
  @override
  Future<void> submit(String activityId, Map<String, dynamic> answers, {required bool editing}) async {
    final e = failure;
    if (e != null) {
      throw e;
    }
    sent = answers;
    wasEditing = editing;
    registration = {'status': 'submitted', 'answers': answers};
    changes.add(registration);
  }
  @override
  Future<void> cancel(String activityId) async {
    registration = {'status': 'cancelled'};
    changes.add(registration);
  }
  @override
  void dispose() {}
}

void main() {
  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
  testWidgets('생성 필수값·정수 검증 후 서버 계약과 목표 포함', (tester) async {
    final api = FakeActivityApi();
    addTearDown(api.changes.close);
    await tester.pumpWidget(MaterialApp(home: CreateActivityScreen(api: api, groupId: 'g', themeColor: 'peach')));
    await tap(tester, '소모임 생성');
    expect(api.created, isNull);
    for (final (label, value) in [('제목', '활동'), ('설명', '설명'), ('활동 목표', '함께 만들기'), ('모집 정원', '501'), ('팀당 목표 인원', '5')]) {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }
    await tap(tester, '소모임 생성');
    expect(api.created, isNull);
    final capacity = find.widgetWithText(TextFormField, '모집 정원');
    await tester.ensureVisible(capacity);
    await tester.enterText(capacity, '20');
    await tap(tester, '소모임 생성');
    expect(api.created!['description'], '설명\n\n활동 목표: 함께 만들기');
    expect(api.created!['targetTeamSize'], 5);
    expect(api.created!['themeColor'], 'peach');
    expect((api.created!['questions'] as List).length, 4);
    expect((api.created!['matching'] as Map)['questionCriteria'],
      {'role': 'role', 'time': 'time', 'experience': 'experience', 'interest': 'interest'});
  });

  testWidgets('단일·복수·척도 검증, 제출·수정·취소 후 상세 버튼 갱신', (tester) async {
    final api = FakeActivityApi();
    addTearDown(api.changes.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RegistrationAction(
      factory: () => api, activity: ActivityRecord(id: 'a', groupId: 'g', title: '활동', description: '설명',
        status: 'recruiting', participantCount: 0, capacity: 20, targetTeamSize: 5,
        deadlineAt: DateTime.now().add(const Duration(days: 1))),
    ))));
    await tester.pumpAndSettle();
    await tap(tester, '참가 신청하기');
    await tap(tester, '참가 신청 제출');
    expect(api.sent, isNull);
    await tap(tester, 'role A');
    await tap(tester, 'role B');
    await tap(tester, 'time A');
    await tap(tester, 'time B');
    await tap(tester, 'interest A');
    await tap(tester, '참가 신청 제출');
    expect(api.sent, isNull);
    await tap(tester, '5');
    api.failure = const TeamixApiException('RESOURCE_EXHAUSTED', 'internal detail');
    await tap(tester, '참가 신청 제출');
    expect(find.text('모집 인원이 다 찼어요.'), findsOneWidget);
    expect(find.text('internal detail'), findsNothing);
    api.failure = null;
    await tap(tester, '참가 신청 제출');
    expect(api.sent, {'role': 'b', 'time': ['a', 'b'], 'interest': ['a'], 'experience': 5});
    expect(api.wasEditing, false);
    expect(find.text('응답 수정·취소'), findsOneWidget);
    await tap(tester, '응답 수정·취소');
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '5')).selected, isTrue);
    await tap(tester, '응답 저장');
    expect(api.wasEditing, true);
    await tap(tester, '응답 수정·취소');
    await tap(tester, '참가 신청 취소');
    expect(find.text('참가 신청하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
