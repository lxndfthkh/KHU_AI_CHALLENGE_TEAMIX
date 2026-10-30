import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Stage 1-2 server commands on main's schema (docs/FIRESTORE.md). Does not replace demo UI.
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
  // Stage 1-2 server commands (functions/src/commands.js). Group creation, invitations, join requests
  // and approvals are app writes in main (firestore_group_writer.dart, firestore_invitations.dart,
  // firestore_join_requests.dart), so they are not here.
  /// activity: title, description, capacity, targetTeamSize, deadlineAt (ms), themeColor?,
  /// questions [{id, label, type: single|multiple|scale, options [{id, label}], required?, enabled?}],
  /// matching {method, questionCriteria {questionId: role|time|experience|interest}, priority?, requireCommonTime?}.
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> activity) =>
    call('createActivity', {...activity, 'groupId': groupId});
  /// answers keyed by question ID: option ID, list of option IDs, or 1-5.
  Future<Map<String, dynamic>> submitRegistration(String activityId, Map<String, dynamic> answers) =>
    call('submitRegistration', {'activityId': activityId, 'answers': answers});
  Future<Map<String, dynamic>> updateRegistration(String activityId, Map<String, dynamic> answers) =>
    call('updateRegistration', {'activityId': activityId, 'answers': answers});
  Future<Map<String, dynamic>> cancelRegistration(String activityId) =>
    call('cancelRegistration', {'activityId': activityId});
  /// Group-scoped and private: never shown to officers. At most two active.
  Future<Map<String, dynamic>> setPlacementPreference(String groupId, String targetUserId) =>
    call('setPlacementPreference', {'groupId': groupId, 'targetUserId': targetUserId, 'confirmed': true});
  Future<Map<String, dynamic>> revokePlacementPreference(String groupId, String targetUserId) =>
    call('revokePlacementPreference', {'groupId': groupId, 'targetUserId': targetUserId});
  // Stage 4 (functions/src/activity.js).
  /// Optional learning-use consent (편성학습_v3 12장). Applies to feedback written afterwards.
  Future<Map<String, dynamic>> setLearningConsent(bool agreed) => call('setLearningConsent', {'agreed': agreed});
  Stream<DocumentSnapshot<Map<String, dynamic>>> ownConsent() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요해요');
    return _db.collection('consents').doc(uid).snapshots();
  }
  Future<Map<String, dynamic>> startActivity(String activityId) => call('startActivity', {'activityId': activityId});
  Future<Map<String, dynamic>> endActivity(String activityId) => call('endActivity', {'activityId': activityId});
  /// scores: overall, schedule, roles, rejoin (1-5). No free text (편성학습_v4).
  /// The team is decided by the server from the version that was current when the activity ended.
  Future<Map<String, dynamic>> submitFeedback(String activityId, Map<String, int> scores) =>
    call('submitFeedback', {'activityId': activityId, 'scores': scores});
  Future<Map<String, dynamic>> closeFeedback(String activityId) => call('closeFeedback', {'activityId': activityId});
  // Stage 9 (functions/src/privacy.js).
  Future<Map<String, dynamic>> deleteFeedback(String activityId) => call('deleteFeedback', {'activityId': activityId});
  /// Blocked when you are the only officer of the group.
  Future<Map<String, dynamic>> leaveGroup(String groupId) => call('leaveGroup', {'groupId': groupId});
  /// Deletes personal data; published team records keep "삭제된 사용자". Blocked for a sole officer.
  Future<Map<String, dynamic>> deleteAccount() => call('deleteAccount', {'confirm': true});
  /// Own preferences only; firestore.rules allow the author to read them.
  Stream<QuerySnapshot<Map<String, dynamic>>> ownPreferences(String groupId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요해요');
    return _db.collection('placementPreferences').where('groupId', isEqualTo: groupId)
      .where('userId', isEqualTo: uid).where('active', isEqualTo: true).snapshots();
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
