import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_invitations.dart' as invitations;
import 'firestore_join_requests.dart' as requests;
import 'firestore_join_requests.dart' show JoinRequest;

/// Operator actions on a group's Firestore data. The rules decide who may
/// actually run them; the UI only offers them to admins. Null in demo mode.
abstract interface class GroupAdmin {
  Future<String> issueInvitation(String groupId);
  Stream<List<JoinRequest>> joinRequests(String groupId);
  Future<void> decideJoin(
    String groupId,
    String userId, {
    required bool approve,
  });
}

class FirestoreGroupAdmin implements GroupAdmin {
  FirestoreGroupAdmin(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  @override
  Future<String> issueInvitation(String groupId) =>
      invitations.issueInvitation(_db, uid: uid, groupId: groupId);

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
