import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_groups_source.dart';
import 'package:teamix/data/user_profile.dart';
import 'package:teamix/models/group_summary.dart';
import 'package:teamix/screens/my_groups_home.dart';
import 'package:teamix/theme.dart';

Timestamp at(int minute) =>
    Timestamp.fromDate(DateTime(2026, 10, 30, 9, minute));

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  Future<void> put(String path, Map<String, dynamic> data) =>
      db.doc(path).set(data);
  Future<void> membership(
    String groupId,
    String uid,
    String role,
    String status,
    int updated,
  ) => put('memberships/${groupId}_$uid', {
    'groupId': groupId,
    'userId': uid,
    'displayName': uid,
    'role': role,
    'status': status,
    'createdAt': at(0),
    'updatedAt': at(updated),
  });

  await put('groups/makers', {
    'name': '경희 메이커스',
    'ownerId': 'me',
    'themeColor': 'mint',
  });
  await put('groups/walk', {
    'name': '주말 산책 모임',
    'ownerId': 'someone',
    'themeColor': 'peach',
  });
  await put('groups/secret', {'name': '비공개 이름', 'ownerId': 'someone'});
  await membership('makers', 'me', 'admin', 'approved', 1);
  await membership('walk', 'me', 'member', 'approved', 3);
  await membership('secret', 'me', 'member', 'pending', 2);
  await membership('gone', 'me', 'member', 'left', 5);
  await membership('makers', 'other', 'member', 'approved', 4);
  for (final (id, title, status, created) in [
    ('a1', '오래된 모집', 'recruiting', 1),
    ('a2', '새 모집', 'recruiting', 3),
    ('a3', '중간 모집', 'recruiting', 2),
    ('a4', '마감된 활동', 'closed', 4),
  ]) {
    await put('activities/$id', {
      'groupId': 'makers',
      'title': title,
      'status': status,
      'createdAt': at(created),
    });
  }
  return db;
}

void main() {
  test('본인 승인·대기 멤버십만 최근 순으로 모임 카드가 된다', () async {
    final db = await seeded();
    final groups = await FirestoreGroupsSource(db, 'me').watchMyGroups().first;

    expect(groups.map((g) => g.groupId), ['walk', 'secret', 'makers']);

    final walk = groups[0];
    expect(walk.name, '주말 산책 모임');
    expect(walk.roleLabel, '참가원');
    expect(walk.isOperator, isFalse);
    expect(walk.themeColor, 'peach');
    expect(walk.activityTitles, isEmpty);

    // Pending members can't read the group, so its name stays hidden.
    final secret = groups[1];
    expect(secret.pending, isTrue);
    expect(secret.name, GroupSummary.pendingName);
    expect(secret.roleLabel, '승인 대기');
    expect(secret.activityTitles, isEmpty);

    final makers = groups[2];
    expect(makers.name, '경희 메이커스');
    expect(makers.roleLabel, '임원진');
    expect(makers.isOperator, isTrue);
    expect(makers.activityTitles, ['새 모집', '중간 모집']);
  });

  test('멤버십이 바뀌면 홈 목록도 다시 내려온다', () async {
    final db = await seeded();
    final stream = FirestoreGroupsSource(db, 'me').watchMyGroups();
    final emitted = <List<String>>[];
    final sub = stream.listen(
      (g) => emitted.add([for (final x in g) x.groupId]),
    );
    await pumpEventQueue();
    await db.doc('memberships/secret_me').update({
      'status': 'approved',
      'updatedAt': at(9),
    });
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted.first, ['walk', 'secret', 'makers']);
    expect(emitted.last, ['secret', 'walk', 'makers']);
  });

  test('만든 사람이 아닌 admin도 임원진으로 표시된다', () {
    final summary = GroupSummary.fromFirestore(
      uid: 'me',
      membership: {'groupId': 'g', 'role': 'admin', 'status': 'approved'},
      group: {'name': '모임', 'ownerId': 'someone'},
    );
    expect(summary.roleLabel, '임원진');
    expect(summary.isOperator, isTrue);
  });

  test('프로필은 한 번만 만들고 이름은 40자로 자른다', () async {
    final db = FakeFirebaseFirestore();
    await ensureUserProfile(db, 'me', '  ${'가' * 50}  ');
    final first = (await db.doc('users/me').get()).data()!;
    expect(first.keys.toSet(), {'displayName', 'createdAt', 'updatedAt'});
    expect(first['displayName'], '가' * 40);

    await ensureUserProfile(db, 'me', '다른 이름');
    expect((await db.doc('users/me').get()).data()!['displayName'], '가' * 40);

    await ensureUserProfile(db, 'blank', '   ');
    expect(
      (await db.doc('users/blank').get()).data()!['displayName'],
      '팀믹스 사용자',
    );
  });

  Widget home(List<GroupSummary>? groups, {bool loadFailed = false}) =>
      MaterialApp(
        theme: buildTeamixTheme(),
        home: MyGroupsHome(
          groups: groups,
          loadFailed: loadFailed,
          onCreateGroup: () {},
          onJoinGroup: () {},
          onSignOut: () async {},
        ),
      );

  testWidgets('홈은 Firestore 데이터를 그대로 카드로 그린다', (tester) async {
    final db = await seeded();
    final groups = await FirestoreGroupsSource(db, 'me').watchMyGroups().first;
    await tester.pumpWidget(home(groups));

    expect(find.text('주말 산책 모임'), findsOneWidget);
    expect(find.text('새 모집'), findsOneWidget);
    expect(find.text('등록된 소모임이 없어요.'), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('임원진'), 150);
    expect(find.text('임원진'), findsOneWidget);
    expect(find.text(GroupSummary.pendingName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('불러오는 중과 실패 상태를 보여준다', (tester) async {
    await tester.pumpWidget(home(null));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(home(null, loadFailed: true));
    expect(find.byKey(const ValueKey('groups-load-failed')), findsOneWidget);
    expect(find.text('아직 함께하는 모임이 없어요'), findsNothing);
  });
}
