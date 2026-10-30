import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'feedback_learning_api.dart';

abstract class ActivityRegistrationApi {
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> questions(String activityId);
  Stream<Map<String, dynamic>?> ownRegistration(String groupId, String activityId);
  Future<void> submit(String activityId, Map<String, dynamic> answers, {required bool editing});
  Future<void> cancel(String activityId);
  void dispose();
}

class FirebaseActivityRegistration implements ActivityRegistrationApi {
  FirebaseActivityRegistration({FeedbackLearningApi? api, FirebaseFirestore? db, FirebaseAuth? auth})
      : _api = api ?? FeedbackLearningApi(auth: auth, firestore: db), _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance, _ownsApi = api == null;
  final FeedbackLearningApi _api;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final bool _ownsApi;
  @override
  Future<Map<String, dynamic>> createActivity(String groupId, Map<String, dynamic> data) => _api.createActivity(groupId, data);
  @override
  Future<List<Map<String, dynamic>>> questions(String activityId) async {
    final docs = await _db.collection('activities').doc(activityId).collection('questions').get();
    final result = [for (final d in docs.docs) if (d.data()['enabled'] == true) {'id': d.id, ...d.data()}];
    result.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return result;
  }
  @override
  Stream<Map<String, dynamic>?> ownRegistration(String groupId, String activityId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream.error(StateError('로그인이 필요해요'));
    }
    return _db.collection('registrations').where('groupId', isEqualTo: groupId)
      .where('activityId', isEqualTo: activityId).where('userId', isEqualTo: uid)
      .snapshots().map((s) => s.docs.isEmpty ? null : s.docs.first.data());
  }
  @override
  Future<void> submit(String activityId, Map<String, dynamic> answers, {required bool editing}) async {
    if (editing) {
      await _api.updateRegistration(activityId, answers);
    } else {
      await _api.submitRegistration(activityId, answers);
    }
  }
  @override
  Future<void> cancel(String activityId) async {
    await _api.cancelRegistration(activityId);
  }
  @override
  void dispose() {
    if (_ownsApi) {
      _api.dispose();
    }
  }
}

String activityError(Object error) {
  if (error is TeamixApiException) {
    switch (error.code.toUpperCase().replaceAll('-', '_')) {
      case 'RESOURCE_EXHAUSTED': return '모집 인원이 다 찼어요.';
      case 'FAILED_PRECONDITION': return '모집이 마감됐거나 지금은 신청을 변경할 수 없어요. 팀 공개 후 취소는 임원진에게 요청해 주세요.';
      case 'PERMISSION_DENIED': return '이 작업을 할 권한이 없어요. 모임 가입 상태를 확인해 주세요.';
      case 'UNAUTHENTICATED': return '다시 로그인해 주세요.';
      case 'INVALID_ARGUMENT': return '입력한 내용과 질문 선택지를 확인해 주세요.';
      case 'NOT_FOUND': return '모임 또는 소모임을 찾을 수 없어요.';
      default: return '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
  }
  if (error is TimeoutException) {
    return '응답이 늦어지고 있어요. 신청 상태를 확인한 뒤 다시 시도해 주세요.';
  }
  return '연결하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

abstract class ActivityRegistrationProvider {
  ActivityRegistrationApi newRegistrationApi();
}
