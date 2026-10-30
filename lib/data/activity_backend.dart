import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity.dart';
import '../models/formation.dart';
import 'feedback_learning_api.dart';

/// Subgroup questions, registrations and teams for the group home screens
/// (activity documents themselves come from ActivitiesSource). Reads go
/// straight to Firestore under the rules; writes go through the callable
/// commands in functions/ because the rules refuse them. Null in demo mode.
abstract interface class ActivityBackend {
  /// The caller's published team (`teamViews/{a}_{uid}`), null before.
  Stream<MyTeam?> myTeam(String groupId, String activityId);
  Future<List<ActivityQuestion>> questions(String activityId);
  Stream<Registration?> myRegistration(String groupId, String activityId);
  Future<String> createActivity(String groupId, NewActivity activity);
  Future<void> submitRegistration(
    String activityId,
    Map<String, Object> answers,
  );
  Future<void> updateRegistration(
    String activityId,
    Map<String, Object> answers,
  );
  Future<void> cancelRegistration(String activityId);
}

class FirebaseActivityBackend implements ActivityBackend {
  FirebaseActivityBackend(this._db, this.uid, [FeedbackLearningApi? api])
    : _injectedApi = api;

  final FirebaseFirestore _db;
  final String uid;
  final FeedbackLearningApi? _injectedApi;

  /// Created on the first write so reads work without the callable client.
  late final FeedbackLearningApi _api = _injectedApi ?? FeedbackLearningApi();

  /// A query for the same reason as [myRegistration]; groupId and activityId
  /// let the rules check membership and participation.
  @override
  Stream<MyTeam?> myTeam(String groupId, String activityId) => _db
      .collection('teamViews')
      .where('groupId', isEqualTo: groupId)
      .where('activityId', isEqualTo: activityId)
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) =>
            s.docs.isEmpty ? null : MyTeam.fromFirestore(s.docs.first.data()),
      );

  @override
  Future<List<ActivityQuestion>> questions(String activityId) async {
    final s = await _db.collection('activities/$activityId/questions').get();
    final list = [
      for (final d in s.docs)
        if (d.data()['enabled'] != false)
          ActivityQuestion.fromFirestore(d.id, d.data()),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// A query, not a get: reading a missing registration by ID is refused by
  /// the rules, while an empty query result is allowed.
  @override
  Stream<Registration?> myRegistration(String groupId, String activityId) => _db
      .collection('registrations')
      .where('groupId', isEqualTo: groupId)
      .where('activityId', isEqualTo: activityId)
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) => s.docs.isEmpty
            ? null
            : Registration.fromFirestore(s.docs.first.data()),
      );

  @override
  Future<String> createActivity(String groupId, NewActivity activity) async {
    final result = await _api.createActivity(groupId, activity.toJson());
    return result['activityId'] as String;
  }

  @override
  Future<void> submitRegistration(
    String activityId,
    Map<String, Object> answers,
  ) => _api.submitRegistration(activityId, answers);

  @override
  Future<void> updateRegistration(
    String activityId,
    Map<String, Object> answers,
  ) => _api.updateRegistration(activityId, answers);

  @override
  Future<void> cancelRegistration(String activityId) =>
      _api.cancelRegistration(activityId);
}
