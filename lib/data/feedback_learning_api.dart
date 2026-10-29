import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Server boundary for stages 1-2. Auth provider selection remains unchanged.
/// Existing synchronous demo GroupRepository is intentionally not implemented:
/// a network request must never masquerade as a synchronous fixture mutation.
class FeedbackLearningApi {
  FeedbackLearningApi({FirebaseAuth? auth, FirebaseFirestore? firestore,
    http.Client? client, Uri? functionsBase})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _client = client ?? http.Client(),
        _base = functionsBase ?? Uri.parse(
          'https://asia-northeast3-${(auth ?? FirebaseAuth.instance).app.options.projectId}.cloudfunctions.net/');
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final http.Client _client;
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
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      final e = body['error'] as Map<String, dynamic>;
      throw TeamixApiException(e['status'] as String? ?? 'UNKNOWN',
        e['message'] as String? ?? '요청에 실패했어요');
    }
    if (response.statusCode != 200) throw TeamixApiException('HTTP', '요청에 실패했어요');
    return Map<String, dynamic>.from(body['result'] as Map);
  }
  Future<Map<String, dynamic>> initializeProfile(String name, String termsVersion) =>
    call('initializeProfile', {'displayName': name, 'termsVersion': termsVersion, 'termsAgreed': true});
  Future<Map<String, dynamic>> setLearningConsent(bool agreed) => call('setLearningConsent', {'agreed': agreed});
  Future<Map<String, dynamic>> createGroup(String name, String description) => call('createGroup', {'name': name, 'description': description});
  Future<Map<String, dynamic>> previewInvite(String code) => call('previewInvite', {'inviteCode': code});
  Future<Map<String, dynamic>> requestJoin(String groupId, String code) => call('requestJoin', {'groupId': groupId, 'inviteCode': code});
  Future<Map<String, dynamic>> decideJoin(String groupId, String uid, bool approve) => call('decideJoin', {'groupId': groupId, 'uid': uid, 'approve': approve});
  Future<Map<String, dynamic>> listMyGroups() => call('listMyGroups', {});
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> settings) => call('createActivity', {'groupId': groupId, 'settings': settings});
  Future<Map<String, dynamic>> updateSettings(String groupId, String activityId, int expected, Map<String, dynamic> settings) => call('updateActivitySettings', {'groupId': groupId, 'activityId': activityId, 'expectedSettingsVersion': expected, 'settings': settings});
  Future<Map<String, dynamic>> submitApplication(String groupId, String activityId, Map<String, dynamic> answers) => call('submitApplication', {'groupId': groupId, 'activityId': activityId, 'answers': answers});
  Future<Map<String, dynamic>> withdrawApplication(String groupId, String activityId) => call('withdrawApplication', {'groupId': groupId, 'activityId': activityId});
  Future<Map<String, dynamic>> setPreference(String groupId, String activityId, String targetUid, {required bool confirmed}) => call('setPrivatePreference', {'groupId': groupId, 'activityId': activityId, 'targetUid': targetUid, 'confirmed': confirmed});
  Future<Map<String, dynamic>> withdrawPreference(String prefId) => call('withdrawPrivatePreference', {'prefId': prefId});
  Stream<QuerySnapshot<Map<String, dynamic>>> ownPreferences() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요해요');
    return _db.collection('privatePreferences').where('ownerUid', isEqualTo: uid).snapshots();
  }
  void dispose() => _client.close();
}

@immutable
class TeamixApiException implements Exception {
  const TeamixApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
