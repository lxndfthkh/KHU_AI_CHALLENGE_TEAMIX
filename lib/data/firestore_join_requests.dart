import 'package:cloud_firestore/cloud_firestore.dart';

/// A pending `memberships/{groupId}_{uid}` shown to the group's admins.
class JoinRequest {
  const JoinRequest({
    required this.userId,
    required this.displayName,
    this.requestedAt,
  });

  final String userId;
  final String displayName;
  final DateTime? requestedAt;
}

/// Oldest first; matches the (groupId, status, createdAt) index.
Stream<List<JoinRequest>> watchJoinRequests(
  FirebaseFirestore db,
  String groupId,
) => db
    .collection('memberships')
    .where('groupId', isEqualTo: groupId)
    .where('status', isEqualTo: 'pending')
    .orderBy('createdAt')
    .snapshots()
    .map(
      (snapshot) => [
        for (final doc in snapshot.docs)
          JoinRequest(
            userId: doc.data()['userId'] as String? ?? '',
            displayName: doc.data()['displayName'] as String? ?? '이름 없음',
            requestedAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
          ),
      ],
    );

/// approveJoin / rejectJoin: only status and updatedAt change (see rules).
Future<void> decideJoin(
  FirebaseFirestore db, {
  required String groupId,
  required String userId,
  required bool approve,
}) => db.doc('memberships/${groupId}_$userId').update({
  'status': approve ? 'approved' : 'rejected',
  'updatedAt': FieldValue.serverTimestamp(),
});
