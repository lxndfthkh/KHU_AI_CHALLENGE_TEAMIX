import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_groups_source.dart';
import 'package:teamix/data/firestore_pending_join.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/screens/pending_join_screen.dart';
import 'package:teamix/theme.dart';

/// A pending request to `walk` made with invite code ABCDEFGH.
Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.doc('invitations/ABCDEFGH').set({
    'groupId': 'walk',
    'groupName': '주말 산책 모임',
    'description': '토요일 아침마다 함께 걸어요.',
    'active': true,
    'expiresAt': Timestamp.fromDate(DateTime(2099)),
  });
  await db.doc('memberships/walk_me').set({
    'groupId': 'walk',
    'userId': 'me',
    'displayName': '나',
    'role': 'member',
    'status': 'pending',
    'invitationId': 'ABCDEFGH',
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 30, 9)),
    'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 30, 9)),
  });
  return db;
}

Future<void> decide(FakeFirebaseFirestore db, String status) =>
    db.doc('memberships/walk_me').update({
      'status': status,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 31, 10)),
    });

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  test('내 요청을 실시간으로 따라가고 초대 코드에서 소개를 가져온다', () async {
    final db = await seeded();
    final updates = FirestorePendingJoins(db, 'me').watch('walk');
    final seen = <String>[];
    final sub = updates.listen((j) => seen.add(j!.status));

    final first = await updates.first;
    expect(first!.status, 'pending');
    expect(first.requestedAt, DateTime(2026, 10, 30, 9));
    expect(first.description, '토요일 아침마다 함께 걸어요.');

    await decide(db, 'approved');
    await pumpEventQueue();
    expect(seen.last, 'approved');
    await sub.cancel();
  });

  test('초대 코드를 읽을 수 없으면 소개 없이 보여준다', () async {
    final db = await seeded();
    await db.doc('invitations/ABCDEFGH').delete();
    final join = await FirestorePendingJoins(db, 'me').watch('walk').first;
    expect(join!.status, 'pending');
    expect(join.description, isNull);
  });

  testWidgets('대기 화면은 단계와 안내를 보여주고 거절되면 바로 바뀐다', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(
      app(
        PendingJoinScreen(
          groupName: '주말 산책 모임',
          request: FirestorePendingJoins(db, 'me').watch('walk'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('가입 대기'), findsOneWidget);
    final header = find.byKey(const ValueKey('pending-header'));
    for (final text in [
      '참여를 요청한 모임',
      '주말 산책 모임',
      '승인 대기 중',
      '2026년 10월 30일 요청',
    ]) {
      expect(
        find.descendant(of: header, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(find.text('토요일 아침마다 함께 걸어요.'), findsOneWidget);
    expect(find.text('참여 요청 보냄'), findsOneWidget);
    expect(find.text('2026년 10월 30일'), findsOneWidget);
    expect(find.text('임원진 확인 중'), findsOneWidget);
    expect(find.text('가입 완료'), findsOneWidget);

    await decide(db, 'rejected');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-rejected')), findsOneWidget);
    expect(find.textContaining('2026년 10월 31일'), findsOneWidget);
    expect(find.text('임원진 확인 중'), findsNothing);
    expect(find.text('승인되지 않음'), findsOneWidget);
  });

  testWidgets('홈 카드 이름을 모르면 초대 코드의 모임 이름을 보여준다', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(
      app(
        PendingJoinScreen(
          groupName: '승인 대기 중인 모임',
          request: FirestorePendingJoins(db, 'me').watch('walk'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('주말 산책 모임'), findsOneWidget);
  });

  testWidgets('승인되면 가입 완료 안내와 돌아가기 버튼을 보여준다', (tester) async {
    final db = await seeded();
    await decide(db, 'approved');
    await tester.pumpWidget(
      app(
        PendingJoinScreen(
          groupName: '주말 산책 모임',
          request: FirestorePendingJoins(db, 'me').watch('walk'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-approved')), findsOneWidget);
    expect(find.text('내 모임으로'), findsOneWidget);
  });

  testWidgets('시연 모드(데이터 없음)에서도 대기 상태로 열린다', (tester) async {
    await tester.pumpWidget(
      app(const PendingJoinScreen(groupName: '참여 요청한 모임')),
    );
    await tester.pumpAndSettle();
    expect(find.text('임원진 확인 중'), findsOneWidget);
    expect(find.text('방금'), findsOneWidget);
  });

  testWidgets('홈의 승인 대기 카드를 누르면 대기 화면이 열린다', (tester) async {
    final db = await seeded();
    final groups = await FirestoreGroupsSource(db, 'me').watchMyGroups().first;
    await tester.pumpWidget(
      app(
        MyGroupsHome(
          groups: groups,
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async {},
          pendingJoins: FirestorePendingJoins(db, 'me'),
        ),
      ),
    );

    expect(find.text('승인되면 소모임을 볼 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('요청 상태 보기 ↗'));
    await tester.pumpAndSettle();
    expect(find.byType(PendingJoinScreen), findsOneWidget);
    expect(find.text('주말 산책 모임'), findsOneWidget);
  });
}
