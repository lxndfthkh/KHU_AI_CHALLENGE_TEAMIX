import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamix/models/matching.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('assets/demo/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('input fixture round trip preserves all selected and private fields', () {
    final json = fixture('initial_20');
    final input = MatchingInput.fromJson(json);
    expect(input.toJson(), json);
    expect(input.participants, hasLength(20));
    expect(input.teams, hasLength(4));
    expect(input.privatePreferences, hasLength(7));
    final nested = input.participants.first.answers;
    (nested['time'] as List).clear();
    expect(input.participants.first.answers['time'], isNotEmpty);
    expect(jsonEncode(input.toJson()), isNotEmpty);
  });
  test('public fixture round trip and exact rational experience', () {
    final json = fixture('result_public');
    final result = MatchingResult.fromJson(json);
    expect(result.toJson(), json);
    expect(result.status, 'FEASIBLE');
    final ids = result.teams.expand((e) => e.participants).toList();
    expect(ids, hasLength(20));
    expect(ids.toSet(), hasLength(20));
    for (final team in result.teams) {
      expect(team.size, 5);
      expect(team.selfReportedExperience!.mean!.numerator, 15);
      expect(team.selfReportedExperience!.mean!.denominator, 5);
      expect(team.selfReportedExperience!.mean!.value, 3);
    }
  });
  test('error response needs no success-only metadata', () {
    final json = <String, dynamic>{'status': 'ERROR', 'messages': ['입력 오류'], 'teams': []};
    expect(MatchingResult.fromJson(json).toJson(), json);
  });
  test('public output drops unknown internal fields', () {
    final json = fixture('result_public');
    json['J_int'] = 123;
    json['private_preferences'] = ['secret'];
    (json['teams'] as List).first['V'] = 2;
    final output = MatchingResult.fromJson(json).toJson();
    expect(output.containsKey('J_int'), isFalse);
    expect(output.containsKey('private_preferences'), isFalse);
    expect((output['teams'] as List).first.containsKey('V'), isFalse);
  });
  test('optional capacities and withdrawn preferences', () {
    expect(MatchingTeam.fromJson({'id': 't'}).capacity, isNull);
    final json = <String, dynamic>{'source': 'a', 'target': 'b',
      'confirmed': true, 'withdrawn': true};
    expect(PrivatePreference.fromJson(json).toJson(), json);
    expect(const ExperienceMean(numerator: 0, denominator: 0).value, isNull);
  });
}
