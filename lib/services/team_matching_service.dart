import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/matching.dart';

abstract class TeamMatchingService {
  Future<MatchingResult> match(MatchingInput input);
}

class TeamMatchingServiceException implements Exception {
  const TeamMatchingServiceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'TeamMatchingServiceException: $message';
}

MatchingResult _decode(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return MatchingResult.fromJson(json);
  } catch (_) {
    // Do not include response bodies or participant/private data in errors.
    throw const TeamMatchingServiceException('공개 편성 응답 형식이 올바르지 않습니다.');
  }
}

class HttpTeamMatchingService implements TeamMatchingService {
  HttpTeamMatchingService({String serverUrl = 'http://localhost:8000/solve',
    this.timeout = const Duration(seconds: 30), http.Client? client})
      : endpoint = Uri.parse(serverUrl),
        _client = client ?? http.Client(), _ownsClient = client == null {
    if (!endpoint.hasAuthority || !['http', 'https'].contains(endpoint.scheme)) {
      throw ArgumentError.value(serverUrl, 'serverUrl', 'HTTP(S) 주소가 필요합니다.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', '양수여야 합니다.');
    }
  }
  final Uri endpoint;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  @override
  Future<MatchingResult> match(MatchingInput input) async {
    final http.Response response;
    try {
      response = await _client.post(endpoint,
        headers: {'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json'},
        body: jsonEncode(input.toJson()),
      ).timeout(timeout);
    } on TimeoutException {
      throw const TeamMatchingServiceException('편성 요청 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const TeamMatchingServiceException('편성 서버에 연결할 수 없습니다.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TeamMatchingServiceException('편성 서버 요청에 실패했습니다.',
        statusCode: response.statusCode);
    }
    try {
      return _decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TeamMatchingServiceException('응답 문자 인코딩이 올바르지 않습니다.');
    }
  }
  // An injected client remains owned by its caller.
  void close() {
    if (_ownsClient) _client.close();
  }
}

class DemoTeamMatchingService implements TeamMatchingService {
  DemoTeamMatchingService({AssetBundle? bundle,
    this.assetPath = 'assets/demo/result_public.json'}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  final String assetPath;
  @override
  Future<MatchingResult> match(MatchingInput input) async {
    // Canned fixture, not a solver: the result intentionally ignores the input.
    return _decode(await _bundle.loadString(assetPath));
  }
}
