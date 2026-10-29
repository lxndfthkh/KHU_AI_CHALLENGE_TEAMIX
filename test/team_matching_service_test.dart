import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teamix/models/matching.dart';
import 'package:teamix/services/team_matching_service.dart';

String fixture(String name) => File('assets/demo/$name.json').readAsStringSync();
MatchingInput input() => MatchingInput.fromJson(
    jsonDecode(fixture('initial_20')) as Map<String, dynamic>);
http.Response response(String body, [int status = 200]) => http.Response.bytes(
    utf8.encode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

class FixtureBundle extends CachingAssetBundle {
  String? requested;
  @override
  Future<ByteData> load(String key) async {
    requested = key;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(fixture('result_public'))));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('POST endpoint, timeout default, UTF-8 and complete request', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://example.invalid/solve');
      expect(request.method, 'POST');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(utf8.decode(request.bodyBytes)), input().toJson());
      return response(fixture('result_public'));
    });
    final service = HttpTeamMatchingService(
        serverUrl: 'http://example.invalid/solve', client: client);
    addTearDown(client.close);
    expect(service.timeout, const Duration(seconds: 30));
    expect((await service.match(input())).label, '추천 편성안');
  });
  test('default URL is localhost:8000/solve without contacting it', () {
    final service = HttpTeamMatchingService(client: MockClient((_) async => response('{}')));
    addTearDown(service.close);
    expect(service.endpoint.toString(), 'http://localhost:8000/solve');
  });
  test('HTTP error contains status but not response body', () async {
    final client = MockClient((_) async => response('private secret', 503));
    addTearDown(client.close);
    final service = HttpTeamMatchingService(client: client);
    await expectLater(service.match(input()), throwsA(isA<TeamMatchingServiceException>()
        .having((e) => e.statusCode, 'status', 503)
        .having((e) => e.toString(), 'safe message', isNot(contains('private secret')))));
  });
  test('invalid JSON and invalid public schema fail safely', () async {
    for (final body in ['not json', '[]', '{}', '{"status":3}']) {
      final client = MockClient((_) async => response(body));
      addTearDown(client.close);
      await expectLater(HttpTeamMatchingService(client: client).match(input()),
          throwsA(isA<TeamMatchingServiceException>()));
    }
  });
  test('server ERROR response remains a typed result', () async {
    final client = MockClient((_) async => response(
        jsonEncode({'status': 'ERROR', 'messages': ['입력 오류'], 'teams': []})));
    addTearDown(client.close);
    final result = await HttpTeamMatchingService(client: client).match(input());
    expect(result.status, 'ERROR');
    expect(result.messages, ['입력 오류']);
    expect(result.teams, isEmpty);
  });
  test('timeout is converted without network access', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    final service = HttpTeamMatchingService(client: client,
        timeout: const Duration(milliseconds: 1));
    await expectLater(service.match(input()), throwsA(isA<TeamMatchingServiceException>()));
    pending.complete(response(fixture('result_public')));
  });
  test('connection error is converted', () async {
    final client = MockClient((_) async => throw http.ClientException('secret'));
    addTearDown(client.close);
    await expectLater(HttpTeamMatchingService(client: client).match(input()),
        throwsA(isA<TeamMatchingServiceException>()));
  });
  test('demo loads designated asset through injectable bundle', () async {
    final bundle = FixtureBundle();
    final result = await DemoTeamMatchingService(bundle: bundle).match(input());
    expect(bundle.requested, 'assets/demo/result_public.json');
    expect(result.toJson(), jsonDecode(fixture('result_public')));
  });
  test('registered demo asset loads with default bundle', () async {
    final result = await DemoTeamMatchingService().match(input());
    expect(result.toJson(), jsonDecode(fixture('result_public')));
  });
}
