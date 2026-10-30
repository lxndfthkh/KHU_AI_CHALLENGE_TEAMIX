import 'package:cloud_firestore/cloud_firestore.dart';

/// Creates `users/{uid}` once, with only the fields the rules allow.
Future<void> ensureUserProfile(
  FirebaseFirestore db,
  String uid,
  String displayName,
) async {
  final ref = db.doc('users/$uid');
  if ((await ref.get()).exists) return;
  final name = displayName.trim();
  await ref.set({
    'displayName': name.isEmpty
        ? '팀믹스 사용자'
        : name.substring(0, name.length.clamp(0, 40)),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
