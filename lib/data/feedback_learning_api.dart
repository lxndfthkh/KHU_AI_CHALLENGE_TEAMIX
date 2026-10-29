import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Canonical main schema. This asynchronous boundary does not replace demo UI.
class FeedbackLearningApi {
  FeedbackLearningApi({FirebaseAuth? auth, FirebaseFirestore? firestore,
    http.Client? client, Uri? functionsBase})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _client = client ?? http.Client(), _ownsClient = client == null,
        _base = functionsBase ?? Uri.parse(
          'https://asia-northeast3-${(auth ?? FirebaseAuth.instance).app.options.projectId}.cloudfunctions.net/');
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _base;
  Stream<User?> get authChanges => _auth.authStateChanges();
  Future<void> signOut() => _auth.signOut();
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요해요');
    final token = await user.getIdToken();
    final response = await _client.post(_base.resolve(name),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'data': data})).timeout(const Duration(seconds: 30));
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const TeamixApiException('FORMAT', '서버 응답 형식이 올바르지 않아요');
    }
    if (body['error'] is Map) {
      final e = Map<String, dynamic>.from(body['error'] as Map);
      throw TeamixApiException(e['status'] as String? ?? 'UNKNOWN',
        e['message'] as String? ?? '요청에 실패했어요');
    }
    final result = body['result'] ?? body['data'];
    if (response.statusCode != 200 || result is! Map) {
      throw const TeamixApiException('HTTP', '요청에 실패했어요');
    }
    return Map<String, dynamic>.from(result);
  }
  Future<Map<String, dynamic>> initializeProfile(String nickname, String termsVersion) =>
    call('initializeProfile', {'nickname': nickname, 'termsVersion': termsVersion, 'termsAgreed': true});
  Future<Map<String, dynamic>> setLearningConsent(bool agreed) => call('setLearningConsent', {'agreed': agreed});
  Future<Map<String, dynamic>> createGroup(String name, String description) => call('createGroup', {'name': name, 'description': description});
  Future<Map<String, dynamic>> previewInvite(String code) => call('previewInvite', {'inviteCode': code.trim().toUpperCase()});
  Future<Map<String, dynamic>> requestJoin(String groupId, String code) => call('requestJoin', {'groupId': groupId, 'inviteCode': code.trim().toUpperCase()});
  Future<Map<String, dynamic>> decideJoin(String groupId, String uid, bool approve) => call('decideJoin', {'groupId': groupId, 'uid': uid, 'approve': approve});
  Future<Map<String, dynamic>> listMyGroups() => call('listMyGroups', {});
  /// activity contains title/description/goal/recruitmentCapacity/deadline,
  /// questions and matchingSettings, exactly as in main's activity model.
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> activity) => call('createActivity', {...activity, 'groupId': groupId});
  Future<Map<String, dynamic>> updateSettings(String groupId, String activityId, int expected, Map<String, dynamic> activity) => call('updateActivitySettings', {...activity, 'groupId': groupId, 'activityId': activityId, 'expectedSettingsVersion': expected});
  /// Raw answers, e.g. role: '개발', time: ['수 저녁'], experience: 3.
  Future<Map<String, dynamic>> submitApplication(String groupId, String activityId, Map<String, dynamic> answers) => call('submitApplication', {'groupId': groupId, 'activityId': activityId, 'answers': answers});
  Future<Map<String, dynamic>> withdrawApplication(String groupId, String activityId) => call('withdrawApplication', {'groupId': groupId, 'activityId': activityId});
  /// Preferences are group-scoped, not activity-scoped.
  Future<Map<String, dynamic>> setPreference(String groupId, String targetUid, {required bool confirmed}) => call('setPrivatePreference', {'groupId': groupId, 'targetUid': targetUid, 'confirmed': confirmed});
  Future<Map<String, dynamic>> withdrawPreference(String groupId, String targetUid) => call('withdrawPrivatePreference', {'groupId': groupId, 'targetUid': targetUid});
  Stream<DocumentSnapshot<Map<String, dynamic>>> ownPreferences(String groupId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요해요');
    return _db.collection('privatePreferences').doc(uid).collection('groups').doc(groupId).snapshots();
  }
  void dispose() { if (_ownsClient) _client.close(); }
}

@immutable
class TeamixApiException implements Exception {
  const TeamixApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
