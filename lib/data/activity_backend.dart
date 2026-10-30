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

  /// Everyone who signed up (operators only), with display names.
  Stream<List<Applicant>> applicants(String groupId, String activityId);

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


  /// Learning-use consent; applies to feedback written afterwards.
  Stream<bool> learningConsent();
  Future<void> setLearningConsent(bool agreed);
  Future<void> leaveGroup(String groupId);
  Future<void> deleteAccount();

  // 비공개 배치 선호 (편성알고리즘 v3 7장): group-wide, read only by the
  // author, never shown to operators; used by the next team formation.

  /// Members the caller would rather not be teamed with in this group.
  Stream<Set<String>> myPlacementPreferences(String groupId);

  /// Approved members other than the caller, to choose from.
  Future<List<GroupPeer>> groupPeers(String groupId);

  /// The caller's published teammates, for the after-feedback prompt.
  Future<List<GroupPeer>> teammates(String groupId, String activityId);

  Future<void> setPlacementPreference(String groupId, String targetUserId);
  Future<void> revokePlacementPreference(String groupId, String targetUserId);
}

/// Another member of the caller's group, as the caller may see them.
class GroupPeer {
  const GroupPeer(this.userId, this.name);

  final String userId;
  final String name;
}

/// One `registrations/{a}_{uid}` as an operator sees it.
class Applicant {
  const Applicant({
    required this.userId,
    required this.name,
    required this.submitted,
    this.answers = const {},
  });

  final String userId;
  final String name;

  /// false when the registration was cancelled.
  final bool submitted;
  final Map<String, Object?> answers;
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

  /// groupId and activityId equality let the rules prove the admin read.
  @override
  Stream<List<Applicant>> applicants(String groupId, String activityId) {
    Map<String, String>? names;
    return _db
        .collection('registrations')
        .where('groupId', isEqualTo: groupId)
        .where('activityId', isEqualTo: activityId)
        .snapshots()
        .asyncMap((s) async {
          names ??= {
            for (final d in (await _db
                    .collection('memberships')
                    .where('groupId', isEqualTo: groupId)
                    .get())
                .docs)
              '${d.data()['userId']}':
                  d.data()['displayName'] as String? ?? '이름 없음',
          };
          return [
            for (final d in s.docs)
              Applicant(
                userId: '${d.data()['userId']}',
                name: names!['${d.data()['userId']}'] ?? '이름 없음',
                submitted: d.data()['status'] == 'submitted',
                answers: Map<String, Object?>.from(
                  d.data()['answers'] as Map? ?? const {},
                ),
              ),
          ];
        });
  }

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

  @override
  Stream<Set<String>> myPlacementPreferences(String groupId) => _db
      .collection('placementPreferences')
      .where('groupId', isEqualTo: groupId)
      .where('userId', isEqualTo: uid)
      .where('active', isEqualTo: true)
      .snapshots()
      .map(
        (s) => {
          for (final d in s.docs)
            if (d.data()['targetUserId'] case final String t) t,
        },
      );

  /// Rules let approved members list approved memberships only.
  @override
  Future<List<GroupPeer>> groupPeers(String groupId) async {
    final s = await _db
        .collection('memberships')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'approved')
        .get();
    return [
      for (final d in s.docs)
        if (d.data()['userId'] case final String id when id != uid)
          GroupPeer(id, d.data()['displayName'] as String? ?? '이름 없음'),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// From the caller's own teamView, the same query as [myTeam].
  @override
  Future<List<GroupPeer>> teammates(String groupId, String activityId) async {
    final s = await _db
        .collection('teamViews')
        .where('groupId', isEqualTo: groupId)
        .where('activityId', isEqualTo: activityId)
        .where('userId', isEqualTo: uid)
        .get();
    if (s.docs.isEmpty) return const [];
    return [
      for (final m in (s.docs.first.data()['members'] as List?) ?? const [])
        if (m is Map && m['uid'] is String && m['uid'] != uid)
          GroupPeer(m['uid'] as String, m['displayName'] as String? ?? '팀원'),
    ];
  }

  @override
  Future<void> setPlacementPreference(String groupId, String targetUserId) =>
      _api.setPlacementPreference(groupId, targetUserId);

  @override
  Future<void> revokePlacementPreference(
    String groupId,
    String targetUserId,
  ) => _api.revokePlacementPreference(groupId, targetUserId);
}
