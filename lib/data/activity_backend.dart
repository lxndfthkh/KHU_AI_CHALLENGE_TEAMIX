import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity.dart';
import '../models/formation.dart';
import 'feedback_learning_api.dart';

/// Subgroup questions, registrations, teams, the activity lifecycle and
/// feedback, plus the account actions that touch learning data (activity
/// documents themselves come from ActivitiesSource). Reads go straight to
/// Firestore under the rules; writes go through the callable commands in
/// functions/ because the rules refuse them. Null in demo mode.
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

  /// Operator edit while recruiting; [patch] holds only changed fields
  /// (title, description, type, capacity, targetTeamSize, deadlineAt ms).
  Future<void> updateActivity(String activityId, Map<String, Object> patch);

  // Activity lifecycle (operators): published → active → ended → closed.
  Future<void> startActivity(String activityId);
  Future<void> endActivity(String activityId);
  Future<void> closeFeedback(String activityId);

  /// The caller's own star rating, null until submitted.
  Stream<Map<String, int>?> myFeedback(String groupId, String activityId);

  /// overall, schedule, roles, rejoin (1-5); no free text (편성학습_v4).
  Future<void> submitFeedback(String activityId, Map<String, int> scores);

  /// Team averages for teams with 3+ respondents (operators only).
  Stream<FeedbackSummary?> feedbackSummary(String activityId);

  /// Team IDs of a published version (publications, operators only).
  Future<List<String>> publishedTeamIds(String activityId, int version);

  /// Learning-use consent; applies to feedback written afterwards.
  Stream<bool> learningConsent();
  Future<void> setLearningConsent(bool agreed);
  Future<void> leaveGroup(String groupId);
  Future<void> deleteAccount();
}

/// `activities/{a}/feedbackSummary/current` from functions/src/activity.js.
class FeedbackSummary {
  const FeedbackSummary(this.teams);

  factory FeedbackSummary.fromFirestore(
    Map<String, dynamic> d,
  ) => FeedbackSummary({
    for (final e in ((d['teams'] as Map?) ?? const {}).entries)
      '${e.key}': (
        ((e.value as Map)['respondents'] as num).toInt(),
        {
          for (final s
              in (((e.value as Map)['averages'] as Map?) ?? const {}).entries)
            '${s.key}': (s.value as num).toDouble(),
        },
      ),
  });

  /// teamId -> (respondents, averages by score key).
  final Map<String, (int, Map<String, double>)> teams;
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

  @override
  Future<void> updateActivity(String activityId, Map<String, Object> patch) =>
      _api.call('updateActivity', {...patch, 'activityId': activityId});

  @override
  Future<void> startActivity(String activityId) =>
      _api.startActivity(activityId);

  @override
  Future<void> endActivity(String activityId) => _api.endActivity(activityId);

  @override
  Future<void> closeFeedback(String activityId) =>
      _api.closeFeedback(activityId);

  /// A query: the rules check membership through groupId and refuse a get
  /// of a feedback document that doesn't exist yet.
  @override
  Stream<Map<String, int>?> myFeedback(String groupId, String activityId) => _db
      .collection('feedback')
      .where('groupId', isEqualTo: groupId)
      .where('activityId', isEqualTo: activityId)
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((s) {
        if (s.docs.isEmpty) return null;
        final scores = s.docs.first.data()['scores'] as Map? ?? const {};
        return {
          for (final e in scores.entries) '${e.key}': (e.value as num).toInt(),
        };
      });

  @override
  Future<void> submitFeedback(String activityId, Map<String, int> scores) =>
      _api.submitFeedback(activityId, scores);

  @override
  Stream<FeedbackSummary?> feedbackSummary(String activityId) => _db
      .doc('activities/$activityId/feedbackSummary/current')
      .snapshots()
      .map((d) => d.exists ? FeedbackSummary.fromFirestore(d.data()!) : null);

  @override
  Future<List<String>> publishedTeamIds(String activityId, int version) async {
    final d = await _db.doc('publications/${activityId}_v$version').get();
    return [
      for (final t in (d.data()?['teams'] as List?) ?? const [])
        if (t is Map) '${t['teamId']}',
    ];
  }

  @override
  Stream<bool> learningConsent() => _db
      .doc('consents/$uid')
      .snapshots()
      .map((d) => (d.data()?['learning'] as Map?)?['agreed'] == true);

  @override
  Future<void> setLearningConsent(bool agreed) =>
      _api.setLearningConsent(agreed);

  @override
  Future<void> leaveGroup(String groupId) => _api.leaveGroup(groupId);

  @override
  Future<void> deleteAccount() => _api.deleteAccount();
}
