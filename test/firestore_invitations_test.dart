import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_group_writer.dart';
import 'package:teamix/data/firestore_groups_source.dart';
import 'package:teamix/data/firestore_invitations.dart';
import 'package:teamix/models/group_summary.dart';
import 'package:teamix/screens/group_home.dart';
import 'package:teamix/theme.dart';

final codePattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

Future<(FakeFirebaseFirestore, String)> withGroup() async {
  final db = FakeFirebaseFirestore();
  final groupId = await createGroupInFirestore(
    db,
    uid: 'owner',
    displayName: '임원진',
    name: '경희 메이커스',
    description: '함께 만들어요',
  );
  return (db, groupId);
}

void main() {
  test('초대 코드는 헷갈리는 글자 없이 8자리다', () {
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      expect(newInviteCode(random), matches(codePattern));
    }
  });

  test('임원진이 발급한 코드에 모임 이름·소개와 7일 만료가 담긴다', () async {
    final (db, groupId) = await withGroup();
    final code = await issueInvitation(db, uid: 'owner', groupId: groupId);

    expect(code, matches(codePattern));
    final data = (await db.doc('invitations/$code').get()).data()!;
    expect(data['groupId'], groupId);
    expect(data['groupName'], '경희 메이커스');
    expect(data['description'], '함께 만들어요');
    expect(data['active'], isTrue);
    expect(data['createdBy'], 'owner');
    final expires = (data['expiresAt'] as Timestamp).toDate();
    expect(
      expires.isAfter(DateTime.now().add(const Duration(days: 6))),
      isTrue,
    );
    expect(
      expires.isBefore(DateTime.now().add(const Duration(days: 7))),
      isTrue,
    );
  });

  test('코드 조회는 대소문자·공백을 정리하고 무효 코드는 null', () async {
    final (db, groupId) = await withGroup();
    final code = await issueInvitation(db, uid: 'owner', groupId: groupId);

    final found = await findInvitation(db, '  ${code.toLowerCase()} ');
    expect(found?.groupId, groupId);
    expect(found?.groupName, '경희 메이커스');
    expect(found?.description, '함께 만들어요');

    expect(await findInvitation(db, 'ABCD2345'), isNull);
    expect(await findInvitation(db, 'short'), isNull);
    expect(await findInvitation(db, 'ABCD0123'), isNull);

    await db.doc('invitations/$code').update({'active': false});
    expect(await findInvitation(db, code), isNull);

    final expired = await issueInvitation(db, uid: 'owner', groupId: groupId);
    await db.doc('invitations/$expired').update({
      'expiresAt': Timestamp.fromDate(DateTime(2020)),
    });
    expect(await findInvitation(db, expired), isNull);
  });

  test('참여 요청은 승인 대기로 저장되고 홈에 모임 이름으로 보인다', () async {
    final (db, groupId) = await withGroup();
    final code = await issueInvitation(db, uid: 'owner', groupId: groupId);
    final found = (await findInvitation(db, code))!;

    expect(
      await myMembershipStatus(db, uid: 'newbie', groupId: groupId),
      isNull,
    );
    await requestJoin(
      db,
      uid: 'newbie',
      displayName: ' 새내기 ',
      invitation: found,
    );

    final membership = (await db.doc('memberships/${groupId}_newbie').get())
        .data()!;
    expect(membership.keys.toSet(), {
      'groupId',
      'userId',
      'displayName',
      'role',
      'status',
      'invitationId',
      'createdAt',
      'updatedAt',
    });
    expect(membership['displayName'], '새내기');
    expect(membership['role'], 'member');
    expect(membership['status'], 'pending');
    expect(membership['invitationId'], code);
    expect(
      await myMembershipStatus(db, uid: 'newbie', groupId: groupId),
      'pending',
    );
    expect(
      await myMembershipStatus(db, uid: 'owner', groupId: groupId),
      'approved',
    );

    final home = await FirestoreGroupsSource(
      db,
      'newbie',
    ).watchMyGroups().first;
    expect(home.single.pending, isTrue);
    expect(home.single.name, '경희 메이커스');
    expect(home.single.roleLabel, '승인 대기');
  });

  test('초대 코드가 사라지면 대기 카드는 기본 이름으로 보인다', () async {
    final (db, groupId) = await withGroup();
    await db.doc('memberships/${groupId}_newbie').set({
      'groupId': groupId,
      'userId': 'newbie',
      'role': 'member',
      'status': 'pending',
      'invitationId': 'GONE2345',
      'updatedAt': Timestamp.now(),
    });
    final home = await FirestoreGroupsSource(
      db,
      'newbie',
    ).watchMyGroups().first;
    expect(home.single.name, GroupSummary.pendingName);
  });

  testWidgets('임원진 모임 홈의 초대 공유는 발급한 코드를 보여준다', (tester) async {
    var issued = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeamixTheme(),
        home: GroupHome(
          groupName: '경희 메이커스',
          isOperator: true,
          onIssueInvite: () async {
            issued++;
            return 'ABCD2345';
          },
        ),
      ),
    );
    await tester.tap(find.text('초대 공유'));
    await tester.pumpAndSettle();

    expect(issued, 1);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.text('코드 복사'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
