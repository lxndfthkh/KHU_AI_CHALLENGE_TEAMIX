import 'package:cloud_firestore/cloud_firestore.dart';

/// Member-readable fields only; never reads matching settings or answers.
class ActivityRecord {
  const ActivityRecord({required this.id, required this.groupId,
    required this.title, required this.description, required this.status,
    required this.participantCount, required this.capacity,
    required this.targetTeamSize, required this.deadlineAt,
    this.themeColor, this.type, this.publishedVersion});
  final String id, groupId, title, description, status;
  final String? themeColor, type;
  final int participantCount, capacity, targetTeamSize;
  final DateTime deadlineAt;
  /// Set once teams are published (publications/{id}_v{n}).
  final int? publishedVersion;
  bool get recruiting => status == 'recruiting';
  bool get published => publishedVersion != null;
  factory ActivityRecord.fromFirestore(String id, Map<String, dynamic> d) =>
    ActivityRecord(id: id, groupId: d['groupId'] as String,
      title: d['title'] as String, description: d['description'] as String,
      status: d['status'] as String, participantCount: d['participantCount'] as int,
      capacity: d['capacity'] as int, targetTeamSize: d['targetTeamSize'] as int,
      deadlineAt: (d['deadlineAt'] as Timestamp).toDate(),
      themeColor: d['themeColor'] as String?, type: d['type'] as String?,
      publishedVersion: (d['publishedVersion'] as num?)?.toInt());
  String get statusLabel => switch (status) {
    'recruiting' => '모집 중', 'closed' => '모집 마감',
    'active' => '활동 중', 'ended' => '활동 종료',
    'cancelled' => '활동 취소', _ => '상태 확인 필요',
  };
  String get typeLabel => switch (type) {
    'study' => '스터디', 'project' => '프로젝트',
    'social' => '친목', _ => '소모임',
  };
}

abstract class ActivitiesSource {
  Stream<List<ActivityRecord>> watchActivities(String groupId);
  Stream<ActivityRecord?> watchActivity(String activityId);
}

class FirestoreActivitiesSource implements ActivitiesSource {
  FirestoreActivitiesSource(this._db);
  final FirebaseFirestore _db;
  @override
  Stream<List<ActivityRecord>> watchActivities(String groupId) => _db
    .collection('activities').where('groupId', isEqualTo: groupId)
    .where('status', whereIn: ['recruiting', 'closed', 'active'])
    .orderBy('createdAt', descending: true).snapshots().map((snapshot) => [
      for (final doc in snapshot.docs) ActivityRecord.fromFirestore(doc.id, doc.data()),
    ]);
  @override
  Stream<ActivityRecord?> watchActivity(String activityId) => _db
    .collection('activities').doc(activityId).snapshots().map((doc) {
      final data = doc.data();
      return data == null ? null : ActivityRecord.fromFirestore(doc.id, data);
    });
}
