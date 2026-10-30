import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_notifications.dart';
import 'package:teamix/models/group_summary.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/screens/notifications_screen.dart';
import 'package:teamix/theme.dart';

Timestamp at(int hour) => Timestamp.fromDate(DateTime(2026, 10, 30, hour));

/// Three of mine in the shapes the servers write, plus someone else's.
Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.doc('groups/walk').set({'name': '주말 산책 모임'});
  await db.doc('activities/a1').set({'groupId': 'walk', 'title': '가을 소풍'});
  Future<void> put(
    String id,
    String uid,
    String type,
    int hour, {
    bool read = false,
  }) => db.doc('notifications/$id').set({
    'userId': uid,
    'type': type,
    'groupId': 'walk',
    'activityId': 'a1',
    'createdAt': at(hour),
    'readAt': read ? at(hour + 1) : null,
  });
  await put('a1_v1_me', 'me', 'teamPublished', 9, read: true);
  await put('a1_v2_me', 'me', 'teamChanged', 10);
  await put('feedbackRequested_a1_me', 'me', 'feedbackRequested', 11);
  await put('a1_v1_other', 'other', 'teamPublished', 12);
  return db;
}

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  test('내 알림만 최신순으로, 모임·소모임 이름과 함께 가져온다', () async {
    final db = await seeded();
    final items = await FirestoreNotifications(db, 'me').watch().first;
    expect(items.map((n) => n.id), [
      'feedbackRequested_a1_me',
      'a1_v2_me',
      'a1_v1_me',
    ]);
    expect(items.map((n) => n.unread), [true, true, false]);
    expect(items.first.groupName, '주말 산책 모임');
    expect(items.first.activityTitle, '가을 소풍');
  });

  test('읽음 표시는 readAt만 바꾼다', () async {
    final db = await seeded();
    await FirestoreNotifications(db, 'me').markRead(['a1_v2_me']);
    final doc = (await db.doc('notifications/a1_v2_me').get()).data()!;
    expect(doc['readAt'], isNotNull);
    expect(doc['type'], 'teamChanged');
  });

  test('알 수 없는 종류와 읽을 수 없는 이름에도 문장을 만든다', () {
    expect(
      describeNotification(
        const AppNotification(id: 'x', type: 'teamPublished', groupId: 'g'),
      ).title,
      '소모임 팀이 공개됐어요',
    );
    expect(
      describeNotification(
        const AppNotification(id: 'x', type: 'something', groupId: 'g'),
      ).title,
      '새 알림',
    );
  });

  testWidgets('알림 화면: 종류별 문장, 안 읽음 표시, 모두 읽음', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(
      app(NotificationsScreen(source: FirestoreNotifications(db, 'me'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('가을 소풍 활동이 끝났어요'), findsOneWidget);
    expect(find.text('가을 소풍 내 팀이 바뀌었어요'), findsOneWidget);
    expect(find.text('가을 소풍 팀이 공개됐어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-a1_v2_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-a1_v1_me')), findsNothing);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unread-a1_v2_me')), findsNothing);
    expect(
      find.byKey(const ValueKey('unread-feedbackRequested_a1_me')),
      findsNothing,
    );
  });

  testWidgets('알림을 누르면 읽음이 되고 그 모임을 연다', (tester) async {
    final db = await seeded();
    final opened = <String>[];
    await tester.pumpWidget(
      app(
        NotificationsScreen(
          source: FirestoreNotifications(db, 'me'),
          onOpenGroup: (_, groupId) {
            opened.add(groupId);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('가을 소풍 내 팀이 바뀌었어요'));
    await tester.pumpAndSettle();

    expect(opened, ['walk']);
    expect(
      (await db.doc('notifications/a1_v2_me').get()).data()!['readAt'],
      isNotNull,
    );
  });

  testWidgets('빈 목록 안내', (tester) async {
    await tester.pumpWidget(
      app(
        NotificationsScreen(
          source: FirestoreNotifications(FakeFirebaseFirestore(), 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 받은 알림이 없어요'), findsOneWidget);
  });

  testWidgets('홈 종 아이콘: 안 읽은 수를 보여주고 누르면 알림 화면', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(
      app(
        MyGroupsHome(
          groups: const <GroupSummary>[],
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async {},
          notifications: FirestoreNotifications(db, 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bell = find.byKey(const ValueKey('notification-bell'));
    expect(find.descendant(of: bell, matching: find.text('2')), findsOneWidget);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('시연 모드(알림 없음)에는 종 아이콘이 없다', (tester) async {
    await tester.pumpWidget(
      app(
        MyGroupsHome(
          groups: const <GroupSummary>[],
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('notification-bell')), findsNothing);
  });
}
