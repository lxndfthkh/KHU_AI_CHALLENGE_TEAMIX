import 'package:cloud_firestore/cloud_firestore.dart';

import 'feedback_learning_api.dart';

import 'firestore_invitations.dart' as invitations;
import 'firestore_join_requests.dart' as requests;
import 'firestore_join_requests.dart' show JoinRequest;

/// Operator actions on a group's Firestore data. The rules decide who may
/// actually run them; the UI only offers them to admins. Null in demo mode.
abstract interface class GroupAdmin {
  Future<String> issueInvitation(String groupId);

  /// Turns a code off before it expires (rules allow only `active: false`).
  Future<void> deactivateInvitation(String code);
  Stream<List<JoinRequest>> joinRequests(String groupId);
  Future<void> decideJoin(
    String groupId,
    String userId, {
    required bool approve,
  });

  /// Approved members of the group (admins may read every membership).
  Stream<List<GroupMember>> members(String groupId);
  Future<String?> ownerId(String groupId);

  /// The signed-in operator, so the member list can skip their own row.
  String get selfId;
  Future<void> setMemberRole(
    String groupId,
    String userId, {
    required bool admin,
  });
  Future<void> removeMember(String groupId, String userId);
}

/// An approved `memberships/{groupId}_{uid}`.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.admin,
  });

  final String userId;
  final String displayName;
  final bool admin;
}

class FirestoreGroupAdmin implements GroupAdmin {
  FirestoreGroupAdmin(this._db, this.uid, [FeedbackLearningApi? api])
    : _injectedApi = api;

  final FirebaseFirestore _db;
  final String uid;
  final FeedbackLearningApi? _injectedApi;

  /// Role changes and removals are server commands (functions/privacy.js).
  late final FeedbackLearningApi _api = _injectedApi ?? FeedbackLearningApi();

  @override
  String get selfId => uid;

  @override
  Stream<List<GroupMember>> members(String groupId) => _db
      .collection('memberships')
      .where('groupId', isEqualTo: groupId)
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (d.data()['userId'] is String)
              GroupMember(
                userId: d.data()['userId'] as String,
                displayName: d.data()['displayName'] as String? ?? '이름 없음',
                admin: d.data()['role'] == 'admin',
              ),
        ],
      );

  @override
  Future<String?> ownerId(String groupId) async =>
      (await _db.doc('groups/$groupId').get()).data()?['ownerId'] as String?;

  @override
  Future<void> setMemberRole(
    String groupId,
    String userId, {
    required bool admin,
  }) => _api.call('setMemberRole', {
    'groupId': groupId,
    'userId': userId,
    'role': admin ? 'admin' : 'member',
  });

  @override
  Future<void> removeMember(String groupId, String userId) =>
      _api.call('removeMember', {'groupId': groupId, 'userId': userId});

  @override
  Future<String> issueInvitation(String groupId) =>
      invitations.issueInvitation(_db, uid: uid, groupId: groupId);

  @override
  Future<void> deactivateInvitation(String code) =>
      _db.doc('invitations/$code').update({'active': false});

  @override
  Stream<List<JoinRequest>> joinRequests(String groupId) =>
      requests.watchJoinRequests(_db, groupId);

  @override
  Future<void> decideJoin(
    String groupId,
    String userId, {
    required bool approve,
  }) => requests.decideJoin(
    _db,
    groupId: groupId,
    userId: userId,
    approve: approve,
  );
}
