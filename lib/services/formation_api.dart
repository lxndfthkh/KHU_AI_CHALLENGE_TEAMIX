import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../data/feedback_learning_api.dart';

/// Authenticated server_v3 API. Unlike demo /solve, never sends a raw roster.
/// Read expected versions from /precheck before mutating; roster is an opaque token.
/// Handle {status: STALE} explicitly.
class FormationApi {
  FormationApi({required Uri baseUrl, FirebaseAuth? auth, http.Client? client})
      : _base = baseUrl, _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(), _ownsClient = client == null {
    if (!baseUrl.hasAuthority || !['http', 'https'].contains(baseUrl.scheme)) {
      throw ArgumentError('HTTP(S) API 주소가 필요합니다');
    }
    if (!baseUrl.path.endsWith('/')) throw ArgumentError('주소는 /로 끝나야 합니다');
  }
  final Uri _base;
  final FirebaseAuth _auth;
  final http.Client _client;
  final bool _ownsClient;
  // Same names as main's server command list (docs/FIRESTORE.md).
  static const _routes = {'precheck', 'closeRecruitment', 'updateMatchingSettings',
    'generateDraft', 'moveMember', 'discardDraft', 'publishTeams'};
  Future<Map<String, dynamic>> request(String route, {
    required String groupId, required String activityId,
    Map<String, Object>? expected, Map<String, dynamic> options = const {},
  }) async {
    if (!_routes.contains(route)) throw ArgumentError('지원하지 않는 작업입니다');
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요해요');
    final token = await user.getIdToken();
    final response = await _client.post(_base.resolve(route), headers: {
      'Content-Type': 'application/json', 'Authorization': 'Bearer $token',
    }, body: jsonEncode({...options, 'groupId': groupId, 'activityId': activityId,
      'expected': ?expected,
    })).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Never expose raw response bodies, which may contain private details.
      throw TeamixApiException('HTTP_${response.statusCode}', '편성 요청에 실패했어요');
    }
    try { return Map<String, dynamic>.from(jsonDecode(response.body) as Map); }
    catch (_) { throw const TeamixApiException('FORMAT', '편성 응답 형식이 올바르지 않아요'); }
  }
  void dispose() { if (_ownsClient) _client.close(); }
}
