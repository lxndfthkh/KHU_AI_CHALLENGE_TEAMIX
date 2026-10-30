import 'package:cloud_firestore/cloud_firestore.dart';

/// Member-readable fields only; never reads matching settings or answers.
class ActivityRecord {
  const ActivityRecord({required this.id, required this.groupId,
    required this.title, required this.description, required this.status,
    required this.participantCount, required this.capacity,
    required this.targetTeamSize, required this.deadlineAt,
    this.themeColor, this.type, this.publishedVersion, this.endedAt,
    this.feedbackClosed = false});
  final String id, groupId, title, description, status;
  final String? themeColor, type;
  final int participantCount, capacity, targetTeamSize;
  final DateTime deadlineAt;
  /// Set once teams are published (publications/{id}_v{n}).
  final int? publishedVersion;
  /// Set by endActivity; feedback is collected for [feedbackDays] after it.
  final DateTime? endedAt;
  final bool feedbackClosed;
  static const feedbackDays = 7;
  bool get recruiting => status == 'recruiting';
  bool get published => publishedVersion != null;
  bool get feedbackOpen => status == 'ended' && !feedbackClosed;

  /// Days left to write feedback (0 on the last day), null when closed.
  int? feedbackDaysLeft(DateTime now) {
    final end = endedAt;
    if (!feedbackOpen || end == null) return null;
    final left = end.add(const Duration(days: feedbackDays)).difference(now);
    return left.isNegative ? 0 : left.inDays;
  }
  factory ActivityRecord.fromFirestore(String id, Map<String, dynamic> d) =>
    ActivityRecord(id: id, groupId: d['groupId'] as String,
      title: d['title'] as String, description: d['description'] as String,
      status: d['status'] as String, participantCount: d['participantCount'] as int,
      capacity: d['capacity'] as int, targetTeamSize: d['targetTeamSize'] as int,
      deadlineAt: (d['deadlineAt'] as Timestamp).toDate(),
      themeColor: d['themeColor'] as String?, type: d['type'] as String?,
      publishedVersion: (d['publishedVersion'] as num?)?.toInt(),
      endedAt: (d['endedAt'] as Timestamp?)?.toDate(),
      feedbackClosed: d['feedbackClosedAt'] != null);
  String get statusLabel => switch (status) {
    'recruiting' => '모집 중', 'closed' => '모집 마감',
    'active' => '활동 중', 'ended' => '활동 종료',
    'cancelled' => '활동 취소', _ => '상태 확인 필요',
  };
  String get typeLabel => activityTypeLabels[type] ?? '소모임';
}

/// Activity types, same keys as algorithm/learning/train.py TYPES.
const activityTypeLabels = {
  'study': '스터디', 'project': '프로젝트', 'social': '친목', 'other': '기타',
};

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
    // Ended ones stay listed while feedback is open; the list hides the rest.
    .where('status', whereIn: ['recruiting', 'closed', 'active', 'ended'])
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
