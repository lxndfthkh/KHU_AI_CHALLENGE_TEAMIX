import 'package:cloud_firestore/cloud_firestore.dart';

/// The caller's own join request, `memberships/{groupId}_{uid}`.
class PendingJoin {
  const PendingJoin({
    required this.status,
    this.requestedAt,
    this.decidedAt,
    this.groupName,
    this.description,
  });

  /// `pending | approved | rejected | left`.
  final String status;
  final DateTime? requestedAt;

  /// When the operator decided; only meaningful once not pending.
  final DateTime? decidedAt;

  /// From the invite used to ask; null once that code expired or was off.
  final String? groupName, description;
}

abstract interface class PendingJoinSource {
  /// Follows the request live, so approval or rejection shows at once.
  Stream<PendingJoin?> watch(String groupId);
}

/// Rules let a user read their own membership, and a live invite by code.
class FirestorePendingJoins implements PendingJoinSource {
  FirestorePendingJoins(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  @override
  Stream<PendingJoin?> watch(String groupId) {
    Map<String, dynamic>? invite;
    var looked = false;
    return _db.doc('memberships/${groupId}_$uid').snapshots().asyncMap((
      doc,
    ) async {
      final data = doc.data();
      if (data == null) return null;
      if (!looked) {
        looked = true;
        invite = await _invite(data['invitationId']);
      }
      return PendingJoin(
        status: data['status'] as String? ?? '',
        requestedAt: (data['createdAt'] as Timestamp?)?.toDate(),
        decidedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        groupName: _text(invite?['groupName']),
        description: _text(invite?['description']),
      );
    });
  }

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  Future<Map<String, dynamic>?> _invite(Object? code) async {
    if (code is! String) return null;
    try {
      return (await _db.doc('invitations/$code').get()).data();
    } on FirebaseException {
      return null; // Expired or switched-off codes are unreadable.
    }
  }
}
