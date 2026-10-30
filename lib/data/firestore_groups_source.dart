import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_summary.dart';
import 'firestore_activities_source.dart';

/// Reads the groups home in the order of docs/FIRESTORE.md:
/// own memberships first, then each approved group and its recruiting
/// activities. All queries match an index in firestore.indexes.json.
class FirestoreGroupsSource {
  FirestoreGroupsSource(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;
  late final ActivitiesSource activitiesSource = FirestoreActivitiesSource(_db);

  static const activityPreviewLimit = 2;

  Stream<List<GroupSummary>> watchMyGroups() => _db
      .collection('memberships')
      .where('userId', isEqualTo: uid)
      .where('status', whereIn: ['approved', 'pending'])
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .asyncMap(
        (snapshot) =>
            Future.wait(snapshot.docs.map((doc) => _summary(doc.data()))),
      );

  Future<GroupSummary> _summary(Map<String, dynamic> membership) async {
    final groupId = membership['groupId'];
    if (membership['status'] == 'pending') return _pendingSummary(membership);
    if (membership['status'] != 'approved' || groupId is! String) {
      return GroupSummary.fromFirestore(uid: uid, membership: membership,
        activitiesSource: activitiesSource);
    }
    try {
      final results = await Future.wait([
        _db.doc('groups/$groupId').get(),
        _db
            .collection('activities')
            .where('groupId', isEqualTo: groupId)
            .where('status', isEqualTo: 'recruiting')
            .orderBy('createdAt', descending: true)
            .limit(activityPreviewLimit)
            .get(),
      ]);
      final group = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final activities = results[1] as QuerySnapshot<Map<String, dynamic>>;
      return GroupSummary.fromFirestore(
        uid: uid,
        membership: membership,
        group: group.data(),
        activitiesSource: activitiesSource,
        activityTitles: [
          for (final doc in activities.docs)
            if (doc.data()['title'] case final String title) title,
        ],
      );
    } on FirebaseException {
      // One unreadable group (e.g. approval just revoked) shouldn't hide the rest.
      return GroupSummary.fromFirestore(uid: uid, membership: membership,
        activitiesSource: activitiesSource);
    }
  }

  /// Pending members can't read the group; the invite they used carries its
  /// name until the code expires.
  Future<GroupSummary> _pendingSummary(Map<String, dynamic> membership) async {
    final code = membership['invitationId'];
    Map<String, dynamic>? invitation;
    if (code is String) {
      try {
        invitation = (await _db.doc('invitations/$code').get()).data();
      } on FirebaseException {
        invitation = null;
      }
    }
    return GroupSummary.fromFirestore(
      uid: uid,
      membership: membership,
      group: invitation == null ? null : {'name': invitation['groupName']},
    );
  }
}
