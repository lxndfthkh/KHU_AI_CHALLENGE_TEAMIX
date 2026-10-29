import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/screens/group_card_palette.dart';

void main() {
  test('Joined groups repeat exactly four colors', () {
    expect(GroupCardPalette.joined.length, 4);
    for (var i = 0; i < 20; i++) {
      expect(GroupCardPalette.forGroup(i), same(GroupCardPalette.joined[i % 4]));
    }
  });
  test('Pending groups always use lavender regardless of index', () {
    for (var i = 0; i < 20; i++) {
      expect(GroupCardPalette.forGroup(i, isPending: true), same(GroupCardPalette.pending));
    }
    expect(GroupCardPalette.joined.contains(GroupCardPalette.pending), isFalse);
  });
}
