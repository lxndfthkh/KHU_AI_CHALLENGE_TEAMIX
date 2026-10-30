import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/formation_backend.dart';
import 'package:teamix/services/formation_api.dart';

/// draft() only reads Firestore; the HTTP client is never touched.
class _NoApi implements FormationApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test('초안이 없을 때 구독해도, 첫 AI 편성 결과가 들어오면 보인다', () async {
    final db = FakeFirebaseFirestore();
    final backend = ServerFormationBackend(db, _NoApi());
    final seen = <int?>[];
    final sub = backend.draft('g', 'a1').listen((d) => seen.add(d?.version));
    await pumpEventQueue();
    expect(seen, [null]);

    await db.doc('drafts/a1').set({
      'groupId': 'g',
      'activityId': 'a1',
      'version': 1,
      'teams': [
        {
          'teamId': 'team_1',
          'members': ['u1', 'u2'],
        },
      ],
    });
    await db.doc('drafts/other').set({
      'groupId': 'g',
      'activityId': 'a2',
      'version': 7,
      'teams': const [],
    });
    await pumpEventQueue();
    expect(seen.last, 1);
    await sub.cancel();
  });
}
