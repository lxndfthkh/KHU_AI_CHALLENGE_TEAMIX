import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/main.dart';

void main() {
  testWidgets('Makers opens operator home and returns to groups', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('경희 메이커스'));
    await tester.pumpAndSettle();
    expect(find.text('운영진'), findsOneWidget);
    expect(find.text('가입 요청 관리'), findsOneWidget);
    expect(find.text('부원 관리'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNWidgets(2));
    expect(find.text('활동 후기'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('내 모임으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('내 모임'), findsOneWidget);
  });
}
