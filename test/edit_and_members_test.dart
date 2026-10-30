import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/data/group_admin.dart';
import 'package:teamix/screens/edit_activity_screen.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/members_screen.dart';
import 'package:teamix/theme.dart';

final open = ActivityRecord(
  id: 'a1',
  groupId: 'g1',
  title: '해커톤',
  description: '소개',
  status: 'recruiting',
  participantCount: 6,
  capacity: 20,
  targetTeamSize: 4,
  deadlineAt: DateTime(2030, 1, 1, 23, 59),
  type: 'project',
);

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  testWidgets('소모임 수정: 바뀐 항목만 보내고 신청 인원보다 정원을 못 줄인다', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <Map<String, Object>>[];
    await tester.pumpWidget(
      app(
        EditActivityScreen(
          activity: open,
          now: () => DateTime(2026, 10, 30),
          onSave: (p) async => sent.add(p),
        ),
      ),
    );
    expect(find.text('해커톤'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('edit-capacity')), '5');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('이미 6명이 신청해서 그보다 줄일 수 없어요.'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('edit-capacity')), '30');
    await tester.enterText(find.byKey(const ValueKey('edit-title')), '새 해커톤');
    await tester.tap(find.text('스터디'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(sent.single, {'title': '새 해커톤', 'type': 'study', 'capacity': 30});
  });

  testWidgets('소모임 수정: 바꾼 게 없으면 보내지 않고 닫는다', (tester) async {
    final sent = <Map<String, Object>>[];
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => EditActivityScreen(
                  activity: open,
                  now: () => DateTime(2026, 10, 30),
                  onSave: (p) async => sent.add(p),
                ),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.byType(EditActivityScreen), findsNothing);
  });

  test('부원 목록: 승인된 멤버만, 운영진 여부와 함께', () async {
    final db = FakeFirebaseFirestore();
    final admin = FirestoreGroupAdmin(db, 'owner');
    for (final (uid, role, status) in [
      ('owner', 'admin', 'approved'),
      ('m1', 'member', 'approved'),
      ('p1', 'member', 'pending'),
      ('x1', 'member', 'left'),
    ]) {
      await db.doc('memberships/g1_$uid').set({
        'groupId': 'g1',
        'userId': uid,
        'displayName': uid,
        'role': role,
        'status': status,
      });
    }
    await db.doc('groups/g1').set({'name': '모임', 'ownerId': 'owner'});
    final members = await admin.members('g1').first;
    expect(
      {for (final m in members) m.userId: m.admin},
      {'owner': true, 'm1': false},
    );
    expect(await admin.ownerId('g1'), 'owner');
    expect(admin.selfId, 'owner');
  });

  Future<void> membersScreen(
    WidgetTester tester,
    StreamController<List<GroupMember>> members,
    List<String> calls,
  ) async {
    await tester.pumpWidget(
      app(
        MembersScreen(
          groupName: '경희 메이커스',
          members: members.stream,
          ownerId: Future.value('owner'),
          selfId: 'me',
          onSetRole: (m, admin) async => calls.add('${m.userId} $admin'),
          onRemove: (m) async => calls.add('remove ${m.userId}'),
        ),
      ),
    );
    members.add(const [
      GroupMember(userId: 'm1', displayName: '부원1', admin: false),
      GroupMember(userId: 'owner', displayName: '대표', admin: true),
      GroupMember(userId: 'me', displayName: '나', admin: true),
      GroupMember(userId: 'a2', displayName: '운영2', admin: true),
    ]);
    await tester.pumpAndSettle();
  }

  testWidgets('부원 관리: 대표자와 나는 못 바꾸고, 지정·해제·내보내기를 보낸다', (tester) async {
    final members = StreamController<List<GroupMember>>.broadcast();
    addTearDown(members.close);
    final calls = <String>[];
    await membersScreen(tester, members, calls);

    expect(find.text('경희 메이커스 · 4명 · 운영진 3명'), findsOneWidget);
    expect(find.text('대표자'), findsOneWidget);
    expect(find.text('나 (나)'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-menu-owner')), findsNothing);
    expect(find.byKey(const ValueKey('member-menu-me')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('member-menu-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('운영진으로 지정'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('member-menu-a2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('운영진 해제'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('member-menu-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모임에서 내보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내보내기'));
    await tester.pumpAndSettle();
    expect(calls, ['m1 true', 'a2 false', 'remove m1']);
  });

  testWidgets('모임 홈의 부원 관리는 실제 화면을 연다', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      app(
        GroupHome(
          groupName: '경희 메이커스',
          isOperator: true,
          onOpenMembers: () => opened++,
        ),
      ),
    );
    await tester.tap(find.text('부원 관리'));
    expect(opened, 1);
  });
}
