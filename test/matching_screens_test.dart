import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/screens/matching_settings_screen.dart';
import 'package:teamix/services/team_matching_service.dart';
import 'package:teamix/theme.dart';

void main() {
  testWidgets('Demo 설정에서 실행하면 추천 편성안 카드 4개를 표시한다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTeamixTheme(),
      home: MatchingSettingsScreen(service: DemoTeamMatchingService()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('응답 현황 20/20'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('matching-start')));
    await tester.pumpAndSettle();
    expect(find.text('추천 편성안'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('matching-team-card-$i')), findsOneWidget);
    }
    expect(find.text('봄이'), findsOneWidget);
    expect(find.textContaining('member_'), findsNothing);
    expect(find.textContaining('public_losses'), findsNothing);
    expect(find.textContaining('private_preferences'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
