import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/firestore_group_writer.dart';
import 'package:teamix/data/firestore_groups_source.dart';

void main() {
  test('모임과 생성자 운영진 멤버십을 규칙이 요구하는 모양으로 만든다', () async {
    final db = FakeFirebaseFirestore();
    final id = await createGroupInFirestore(
      db,
      uid: 'me',
      displayName: '  수환  ',
      name: ' 경희 메이커스 ',
      description: ' 함께 만들어요 ',
      categories: ['프로젝트', '보드게임'],
    );

    expect(id, isNot(contains('_')));
    final group = (await db.doc('groups/$id').get()).data()!;
    expect(group.keys.toSet(), {
      'name',
      'description',
      'categories',
      'ownerId',
      'themeColor',
      'status',
      'createdAt',
      'updatedAt',
    });
    expect(group['name'], '경희 메이커스');
    expect(group['description'], '함께 만들어요');
    expect(group['categories'], ['프로젝트', '보드게임']);
    expect(group['ownerId'], 'me');
    expect(group['themeColor'], 'mint');
    expect(group['status'], 'active');

    final membership = (await db.doc('memberships/${id}_me').get()).data()!;
    expect(membership.keys.toSet(), {
      'groupId',
      'userId',
      'displayName',
      'role',
      'status',
      'createdAt',
      'updatedAt',
    });
    expect(membership['groupId'], id);
    expect(membership['userId'], 'me');
    expect(membership['displayName'], '수환');
    expect(membership['role'], 'admin');
    expect(membership['status'], 'approved');
  });

  test('만든 모임은 바로 내 모임 홈에 대표자로 나타난다', () async {
    final db = FakeFirebaseFirestore();
    await createGroupInFirestore(
      db,
      uid: 'me',
      displayName: '',
      name: '새 모임',
      description: '소개',
    );

    final groups = await FirestoreGroupsSource(db, 'me').watchMyGroups().first;
    expect(groups, hasLength(1));
    expect(groups.single.name, '새 모임');
    expect(groups.single.roleLabel, '대표자');
    expect(groups.single.isOperator, isTrue);
  });
}
