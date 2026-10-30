import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_group_writer.dart';
import 'package:teamix/data/firestore_groups_source.dart';
import 'package:teamix/data/firestore_invitations.dart';
import 'package:teamix/data/firestore_join_requests.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/screens/join_requests_screen.dart';
import 'package:teamix/theme.dart';

/// A group with two pending requests made through an invite code.
Future<(FakeFirebaseFirestore, String)> withRequests() async {
  final db = FakeFirebaseFirestore();
  final groupId = await createGroupInFirestore(
    db,
    uid: 'owner',
    displayName: '임원진',
    name: '경희 메이커스',
    description: '함께 만들어요',
  );
  final code = await issueInvitation(db, uid: 'owner', groupId: groupId);
  final invite = (await findInvitation(db, code))!;
  for (final (uid, name) in [('first', '먼저 요청'), ('second', '나중 요청')]) {
    await requestJoin(db, uid: uid, displayName: name, invitation: invite);
  }
  // Fake server timestamps can tie; make the order explicit.
  await db.doc('memberships/${groupId}_first').update({
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 30, 9)),
  });
  await db.doc('memberships/${groupId}_second').update({
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 30, 10)),
  });
  return (db, groupId);
}

void main() {
  test('대기 요청만 오래된 순으로 보인다', () async {
    final (db, groupId) = await withRequests();
    final requests = await watchJoinRequests(db, groupId).first;
    expect(requests.map((r) => r.displayName), ['먼저 요청', '나중 요청']);
    expect(requests.first.userId, 'first');
    expect(requests.first.requestedAt, DateTime(2026, 10, 30, 9));
  });

  test('승인하면 참가원으로 홈에 보이고, 거절하면 홈에서 사라진다', () async {
    final (db, groupId) = await withRequests();
    await decideJoin(db, groupId: groupId, userId: 'first', approve: true);
    await decideJoin(db, groupId: groupId, userId: 'second', approve: false);

    final approved = (await db.doc('memberships/${groupId}_first').get())
        .data()!;
    expect(approved['status'], 'approved');
    expect(approved['role'], 'member');
    expect(
      (await db.doc('memberships/${groupId}_second').get()).data()!['status'],
      'rejected',
    );
    expect(await watchJoinRequests(db, groupId).first, isEmpty);

    final firstHome = await FirestoreGroupsSource(
      db,
      'first',
    ).watchMyGroups().first;
    expect(firstHome.single.name, '경희 메이커스');
    expect(firstHome.single.roleLabel, '참가원');
    expect(
      await FirestoreGroupsSource(db, 'second').watchMyGroups().first,
      isEmpty,
    );
  });

  Widget screen(
    Stream<List<JoinRequest>> requests,
    Future<void> Function(JoinRequest, bool) onDecide,
  ) => MaterialApp(
    theme: buildTeamixTheme(),
    home: JoinRequestsScreen(
      groupName: '경희 메이커스',
      requests: requests,
      onDecide: onDecide,
    ),
  );

  testWidgets('요청마다 승인·거절 버튼이 있고 결과를 알려준다', (tester) async {
    final decided = <(String, bool)>[];
    final requests = StreamController<List<JoinRequest>>();
    addTearDown(requests.close);
    await tester.pumpWidget(
      screen(requests.stream, (r, approve) async {
        decided.add((r.userId, approve));
      }),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    requests.add(const [
      JoinRequest(userId: 'first', displayName: '먼저 요청'),
      JoinRequest(userId: 'second', displayName: '나중 요청'),
    ]);
    await tester.pump();
    expect(find.text('경희 메이커스 · 대기 2명'), findsOneWidget);

    await tester.tap(find.text('승인').first);
    await tester.pump();
    expect(find.text('먼저 요청님의 요청을 승인했어요.'), findsOneWidget);
    await tester.tap(find.text('거절').last);
    await tester.pump();
    expect(decided, [('first', true), ('second', false)]);

    requests.add(const []);
    await tester.pump();
    expect(find.text('기다리는 가입 요청이 없어요.'), findsOneWidget);
  });

  testWidgets('처리에 실패하면 안내한다', (tester) async {
    await tester.pumpWidget(
      screen(
        Stream.value(const [JoinRequest(userId: 'x', displayName: '누군가')]),
        (_, _) async => throw StateError('denied'),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('승인'));
    await tester.pump();
    expect(find.text('처리하지 못했어요. 이미 처리된 요청일 수 있어요.'), findsOneWidget);
  });

  testWidgets('임원진 모임 홈의 가입 요청 관리는 실제 목록을 연다', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeamixTheme(),
        home: GroupHome(
          groupName: '경희 메이커스',
          isOperator: true,
          onOpenJoinRequests: () => opened++,
        ),
      ),
    );
    await tester.tap(find.text('가입 요청 관리'));
    expect(opened, 1);
  });
}
