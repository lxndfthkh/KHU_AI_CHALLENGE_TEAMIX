import 'package:cloud_firestore/cloud_firestore.dart';

/// One `notifications/{id}` row (firestore.schema.json). Servers write them:
/// the formation server on publish (teamPublished, teamChanged) and
/// endActivity (feedbackRequested). joinApproved/joinRejected are in the
/// schema but nothing writes them yet.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.groupId,
    this.activityId,
    this.createdAt,
    this.readAt,
    this.groupName,
    this.activityTitle,
  });

  final String id;
  final String type;
  final String groupId;
  final String? activityId;
  final DateTime? createdAt;
  final DateTime? readAt;

  /// Looked up for display; null when the reader can no longer see them.
  final String? groupName, activityTitle;

  bool get unread => readAt == null;
}

abstract interface class NotificationSource {
  /// Newest first, live.
  Stream<List<AppNotification>> watch();

  /// Rules allow the owner to set only `readAt`, to the server time.
  Future<void> markRead(Iterable<String> ids);
}

class FirestoreNotifications implements NotificationSource {
  FirestoreNotifications(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  static const limit = 50;

  /// Group and activity names rarely change; read each once.
  final _names = <String, Future<String?>>{};

  @override
  Stream<List<AppNotification>> watch() => _db
      .collection('notifications')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .asyncMap(
        (snapshot) => Future.wait(
          snapshot.docs.map((doc) async {
            final d = doc.data();
            final groupId = d['groupId'] as String? ?? '';
            final activityId = d['activityId'] as String?;
            return AppNotification(
              id: doc.id,
              type: d['type'] as String? ?? '',
              groupId: groupId,
              activityId: activityId,
              createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
              readAt: (d['readAt'] as Timestamp?)?.toDate(),
              groupName: groupId.isEmpty
                  ? null
                  : await _name('groups/$groupId', 'name'),
              activityTitle: activityId == null
                  ? null
                  : await _name('activities/$activityId', 'title'),
            );
          }),
        ),
      );

  Future<String?> _name(String path, String field) => _names[path] ??= _db
      .doc(path)
      .get()
      .then((d) => d.data()?[field] as String?)
      .catchError((_) => null); // e.g. left the group since

  @override
  Future<void> markRead(Iterable<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_db.doc('notifications/$id'), {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
