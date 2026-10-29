import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/main.dart';
import 'package:teamix/onboarding.dart';

void main() {
  testWidgets('앱이 시작 화면을 그린다', (tester) async {
    await tester.pumpWidget(const TeamixApp());
    expect(find.text('teamix.'), findsWidgets);
  });

  testWidgets('Launches directly into groups home', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('내 모임'), findsOneWidget);
    expect(find.text('경희 메이커스'), findsOneWidget);
    expect(find.text('주말 산책 모임'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('참여 요청한 모임'), 150);
    expect(find.text('참여 요청한 모임'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plus opens create and join menu', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('모임 만들기'), findsOneWidget);
    expect(find.text('모임 참가하기'), findsOneWidget);
  });

  testWidgets('Empty home is available without authentication', (tester) async {
    await tester.pumpWidget(const MyApp(showEmpty: true));
    expect(find.text('아직 함께하는 모임이 없어요'), findsOneWidget);
    expect(find.text('경희 메이커스'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}