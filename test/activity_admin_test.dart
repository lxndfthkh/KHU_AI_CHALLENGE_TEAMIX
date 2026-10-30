import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/data/activity_backend.dart';
import 'package:teamix/data/firestore_activities_source.dart';
import 'package:teamix/data/group_admin.dart';
import 'package:teamix/models/activity.dart';
import 'package:teamix/screens/activity_admin.dart';
import 'package:teamix/screens/subgroup_detail_screen.dart';
import 'package:teamix/theme.dart';
import 'package:teamix/widgets/invite_code_dialog.dart';

final open = ActivityRecord(
  id: 'a1',
  groupId: 'g1',
  title: '해커톤',
  description: '소개',
  status: 'recruiting',
  participantCount: 2,
  capacity: 20,
  targetTeamSize: 4,
  deadlineAt: DateTime(2030, 1, 1, 23, 59),
  type: 'project',
);

Widget app(Widget home) => MaterialApp(theme: buildTeamixTheme(), home: home);

void main() {
  testWidgets('신청 현황: 신청자만 이름순으로, 답은 라벨로, 취소 인원 표시', (tester) async {
    await tester.pumpWidget(
      app(
        ApplicantsScreen(
          activity: open,
          applicants: Stream.value(const [
            Applicant(
              userId: 'u2',
              name: '하늘',
              submitted: true,
              answers: {'role': 'dev'},
            ),
            Applicant(
              userId: 'u1',
              name: '가람',
              submitted: true,
              answers: {'role': 'design'},
            ),
            Applicant(userId: 'u3', name: '나무', submitted: false),
          ]),
          questions: const [
            ActivityQuestion(
              id: 'role',
              label: '역할',
              type: 'single',
              options: [
                QuestionOption('dev', '개발'),
                QuestionOption('design', '디자인'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('신청 2 / 20명 · 취소 1명'), findsOneWidget);
    expect(find.text('역할 · 디자인'), findsOneWidget);
    expect(find.text('나무'), findsNothing);
    expect(
      tester.getTopLeft(find.text('가람')).dy,
      lessThan(tester.getTopLeft(find.text('하늘')).dy),
    );
  });

  test('초대 코드 끄기는 active만 false로 바꾼다', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('invitations/ABCD2345').set({'groupId': 'g1', 'active': true});
    await FirestoreGroupAdmin(db, 'owner').deactivateInvitation('ABCD2345');
    final d = (await db.doc('invitations/ABCD2345').get()).data()!;
    expect(d, {'groupId': 'g1', 'active': false});
  });

  testWidgets('초대 팝업의 이 코드 끄기는 발급한 코드를 넘긴다', (tester) async {
    String? off;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInviteCodeDialog(
                context,
                () async => 'ABCD2345',
                deactivate: (code) async => off = code,
              ),
              child: const Text('초대'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('초대'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 코드 끄기'));
    await tester.pumpAndSettle();
    expect(off, 'ABCD2345');
    expect(find.text('이 초대 코드를 껐어요. 더는 참여 요청에 쓸 수 없어요.'), findsOneWidget);
  });

  testWidgets('공개 뒤 신청 취소는 막히고 이유를 보여준다, 링크 공유 메뉴는 숨김', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        SubgroupDetailScreen(
          groupName: '경희 메이커스',
          activity: open,
          isOperator: false,
          registration: Stream.value(const Registration(status: 'submitted')),
          cancelBlockedReason: '팀이 공개돼 취소할 수 없어요.',
          showShareLink: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '신청 취소'),
    );
    expect(cancel.onPressed, isNull);
    expect(find.text('팀이 공개돼 취소할 수 없어요.'), findsOneWidget);
    expect(find.byTooltip('소모임 메뉴'), findsNothing);
  });
}
