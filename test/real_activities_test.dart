import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/models/group_summary.dart';
import 'package:teamix/screens/group_card_palette.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/screens/subgroup_detail_screen.dart';

class FakeActivities implements ActivitiesSource {
  final list = StreamController<List<ActivityRecord>>.broadcast();
  final detail = StreamController<ActivityRecord?>.broadcast();
  String? requestedGroup, requestedActivity;
  @override
  Stream<List<ActivityRecord>> watchActivities(String groupId) {
    requestedGroup = groupId;
    return list.stream;
  }
  @override
  Stream<ActivityRecord?> watchActivity(String activityId) {
    requestedActivity = activityId;
    return detail.stream;
  }
  Future<void> close() async { await list.close(); await detail.close(); }
}
ActivityRecord record({int count = 7}) => ActivityRecord(
  id: 'a', groupId: 'g', title: '실제 소모임', description: '실제 설명',
  status: 'closed', participantCount: count, capacity: 18,
  targetTeamSize: 6, deadlineAt: DateTime(2026, 11, 2, 16, 30),
  themeColor: 'lilac', type: 'study');

void main() {
  testWidgets('목록에서 상세까지 본문 필드와 색상 및 실시간 갱신', (tester) async {
    final source = FakeActivities();
    addTearDown(source.close);
    await tester.pumpWidget(MaterialApp(home: MyGroupsHome(
      groups: [GroupSummary(groupId: 'g', name: '실제 모임', role: 'member',
        status: 'approved', themeColor: 'peach', activitiesSource: source)],
      onCreateGroup: () {}, onJoinGroup: () {}, onSignOut: () async {},
    )));
    await tester.tap(find.text('실제 모임'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(source.requestedGroup, 'g');
    // First joined card in the four-color rotation, whatever themeColor says.
    expect(tester.widget<GroupHome>(find.byType(GroupHome)).palette,
      same(GroupCardPalette.joined[0]));
    source.list.add([record()]);
    await tester.pump();
    await tester.ensureVisible(find.text('소모임 상세보기 ↗'));
    await tester.tap(find.text('소모임 상세보기 ↗'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(source.requestedActivity, 'a');
    source.detail.add(record());
    await tester.pump();
    expect(find.text('실제 설명'), findsOneWidget);
    expect(find.text('7 / 18명'), findsOneWidget);
    expect(find.text('팀당 목표 6명'), findsOneWidget);
    expect(find.text('11월 2일 · 16:30'), findsOneWidget);
    expect(find.text('실제 모임 · 스터디'), findsOneWidget);
    expect(find.byKey(const ValueKey('subgroup-operator-panel')), findsNothing);
    final screen = tester.widget<SubgroupDetailScreen>(find.byType(SubgroupDetailScreen));
    // The detail keeps the group card's color, not the activity's themeColor.
    expect(screen.palette, same(GroupCardPalette.joined[0]));
    source.detail.add(record(count: 8));
    await tester.pump();
    expect(find.text('8 / 18명'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('목록 로딩·빈 상태·오류', (tester) async {
    final source = FakeActivities();
    addTearDown(source.close);
    await tester.pumpWidget(MaterialApp(home: GroupHome(
      groupId: 'g', activitiesSource: source)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    source.list.add([]);
    await tester.pump();
    expect(find.text('등록된 소모임이 없어요.'), findsOneWidget);
    source.list.addError(StateError('private internal error'));
    await tester.pump();
    expect(find.text('소모임을 불러오지 못했어요. 잠시 후 다시 열어 주세요.'), findsOneWidget);
    expect(find.textContaining('private internal'), findsNothing);
  });

  testWidgets('상세 삭제·오류는 이전 데이터를 노출하지 않는다', (tester) async {
    final source = FakeActivities();
    addTearDown(source.close);
    await tester.pumpWidget(MaterialApp(home: RealSubgroupDetailScreen(
      source: source, activityId: 'a', groupId: 'g', groupName: '모임',
      isOperator: true, palette: GroupCardPalette.defaultJoined)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    source.detail.add(null);
    await tester.pump();
    expect(find.text('소모임이 없거나 더 이상 확인할 수 없어요.'), findsOneWidget);
    source.detail.addError(StateError('private'));
    await tester.pump();
    expect(find.text('소모임을 불러오지 못했어요. 잠시 후 다시 열어 주세요.'), findsOneWidget);
  });

  test('Firestore 목록은 모임·상태 필터 및 생성일 역순, 상세는 문서 구독', () async {
    final db = FakeFirebaseFirestore();
    for (final (id, group, status, day) in [
      ('old', 'g', 'recruiting', 1), ('new', 'g', 'active', 2),
      ('ended', 'g', 'ended', 3), ('other', 'other', 'recruiting', 4),
    ]) {
      await db.doc('activities/$id').set({
        'groupId': group, 'status': status, 'title': id, 'description': '설명',
        'participantCount': 2, 'capacity': 10, 'targetTeamSize': 5,
        'deadlineAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
      });
    }
    final source = FirestoreActivitiesSource(db);
    expect((await source.watchActivities('g').first).map((a) => a.id), ['new', 'old']);
    expect((await source.watchActivity('old').first)!.capacity, 10);
    expect(await source.watchActivity('missing').first, isNull);
  });
}
