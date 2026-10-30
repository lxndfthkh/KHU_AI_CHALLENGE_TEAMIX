import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/activity_backend.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/models/formation.dart';
import 'package:teamix/screens/activity_feedback_flow.dart';
import 'package:teamix/screens/group_card_palette.dart';
import 'package:teamix/screens/placement_preferences_screen.dart';
import 'package:teamix/theme.dart';

/// In-memory preferences plus what openFeedback needs.
class PrefBackend extends Fake implements ActivityBackend {
  PrefBackend({this.peers = const [], this.mates = const []});

  final List<GroupPeer> peers, mates;
  final chosen = <String>{};
  final _changes = StreamController<Set<String>>.broadcast();
  final sentScores = <Map<String, int>>[];

  @override
  Stream<Set<String>> myPlacementPreferences(String groupId) async* {
    yield {...chosen};
    yield* _changes.stream;
  }

  @override
  Future<List<GroupPeer>> groupPeers(String groupId) async => peers;

  @override
  Future<List<GroupPeer>> teammates(String groupId, String activityId) async =>
      mates;

  @override
  Future<void> setPlacementPreference(String groupId, String target) async {
    chosen.add(target);
    _changes.add({...chosen});
  }

  @override
  Future<void> revokePlacementPreference(String groupId, String target) async {
    chosen.remove(target);
    _changes.add({...chosen});
  }

  // openFeedback
  @override
  Stream<MyTeam?> myTeam(String groupId, String activityId) =>
      Stream.value(const MyTeam(teamId: 'team_1', members: []));
  @override
  Stream<Map<String, int>?> myFeedback(String groupId, String activityId) =>
      Stream.value(null);
  @override
  Stream<bool> learningConsent() => Stream.value(false);
  @override
  Future<void> submitFeedback(String activityId, Map<String, int> s) async =>
      sentScores.add(s);
}

const peers = [
  GroupPeer('u1', '김하나'),
  GroupPeer('u2', '이둘'),
  GroupPeer('u3', '박셋'),
];

final ended = ActivityRecord(
  id: 'a1',
  groupId: 'g',
  title: '가을 소풍',
  description: '',
  status: 'ended',
  participantCount: 4,
  capacity: 10,
  targetTeamSize: 4,
  deadlineAt: DateTime(2026, 10, 1),
  publishedVersion: 1,
  endedAt: DateTime.now(),
);

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  group('Firestore 읽기', () {
    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      Future<void> member(String uid, String status) =>
          db.doc('memberships/g_$uid').set({
            'groupId': 'g',
            'userId': uid,
            'displayName': '이름$uid',
            'status': status,
          });
      await member('me', 'approved');
      await member('u1', 'approved');
      await member('u2', 'pending');
      Future<void> pref(String target, bool active, [String g = 'g']) =>
          db.doc('placementPreferences/${g}_me_$target').set({
            'groupId': g,
            'userId': 'me',
            'targetUserId': target,
            'active': active,
          });
      await pref('u1', true);
      await pref('u3', false);
      await pref('u9', true, 'other');
      await db.doc('teamViews/a1_me').set({
        'groupId': 'g',
        'activityId': 'a1',
        'userId': 'me',
        'members': [
          {'uid': 'me', 'displayName': '나'},
          {'uid': 'u1', 'displayName': '이름u1'},
        ],
      });
      return db;
    }

    test('내 활성 선호만, 승인된 다른 멤버만, 같은 팀원만', () async {
      final b = FirebaseActivityBackend(await seeded(), 'me');
      expect(await b.myPlacementPreferences('g').first, {'u1'});
      expect((await b.groupPeers('g')).map((p) => p.userId), ['u1']);
      expect((await b.teammates('g', 'a1')).map((p) => p.name), ['이름u1']);
      expect(await b.teammates('g', 'none'), isEmpty);
    });
  });

  testWidgets('설정 화면: 비공개 안내, 고르기·확인, 2명 제한, 해제', (tester) async {
    final b = PrefBackend(peers: peers);
    await tester.pumpWidget(
      app(
        PlacementPreferencesScreen(
          groupName: '주말 산책 모임',
          groupId: 'g',
          backend: b,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('누구에게도 보이지 않아요'), findsOneWidget);
    expect(find.text('지정한 사람 0/2'), findsOneWidget);

    Future<void> pick(String uid) async {
      await tester.tap(find.text('사람 고르기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('peer-$uid')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('비공개로 저장'));
      await tester.pumpAndSettle();
    }

    await pick('u1');
    await pick('u2');
    expect(b.chosen, {'u1', 'u2'});
    expect(find.text('지정한 사람 2/2'), findsOneWidget);
    expect(find.text('김하나'), findsOneWidget);
    expect(find.text('최대 2명까지 지정할 수 있어요'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('preference-u1')),
        matching: find.text('해제'),
      ),
    );
    await tester.pumpAndSettle();
    expect(b.chosen, {'u2'});
    expect(find.text('사람 고르기'), findsOneWidget);
  });

  testWidgets('확인 창에서 취소하면 저장하지 않는다', (tester) async {
    final b = PrefBackend(peers: peers);
    await tester.pumpWidget(
      app(PlacementPreferencesScreen(groupName: 'g', groupId: 'g', backend: b)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('사람 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('peer-u3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(b.chosen, isEmpty);
  });

  Future<void> writeFeedback(
    WidgetTester tester,
    PrefBackend b,
    int rejoin,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFeedback(
                context,
                b,
                'g',
                ended,
                GroupCardPalette.defaultJoined,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    for (final k in ['overall', 'schedule', 'roles']) {
      await tester.tap(find.byKey(ValueKey('star-$k-4')));
    }
    await tester.tap(find.byKey(ValueKey('star-rejoin-$rejoin')));
    await tester.pump();
    final send = find.widgetWithText(FilledButton, '후기 보내기');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
  }

  testWidgets('후기에서 다시 하고 싶지 않다고 하면 팀원 중에서 비공개로 고를 수 있다', (tester) async {
    final b = PrefBackend(
      mates: const [GroupPeer('u1', '김하나'), GroupPeer('u2', '이둘')],
    );
    await writeFeedback(tester, b, 2);

    expect(b.sentScores.single['rejoin'], 2);
    expect(
      find.byKey(const ValueKey('teammate-preference-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mate-u2')));
    await tester.pump();
    await tester.tap(find.text('비공개로 저장'));
    await tester.pumpAndSettle();
    expect(b.chosen, {'u2'});
  });

  testWidgets('다시 하고 싶다고 하면 묻지 않는다', (tester) async {
    final b = PrefBackend(mates: const [GroupPeer('u1', '김하나')]);
    await writeFeedback(tester, b, 5);
    expect(b.sentScores.single['rejoin'], 5);
    expect(
      find.byKey(const ValueKey('teammate-preference-sheet')),
      findsNothing,
    );
  });

  testWidgets('이미 2명을 지정했으면 묻지 않는다', (tester) async {
    final b = PrefBackend(mates: const [GroupPeer('u1', '김하나')])
      ..chosen.addAll({'x', 'y'});
    await writeFeedback(tester, b, 1);
    expect(
      find.byKey(const ValueKey('teammate-preference-sheet')),
      findsNothing,
    );
  });
}
