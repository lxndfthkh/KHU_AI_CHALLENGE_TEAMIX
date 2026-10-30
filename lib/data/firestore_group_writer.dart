import 'package:cloud_firestore/cloud_firestore.dart';

/// Field limits enforced by firestore.rules (validNewGroup).
const groupNameMaxLength = 40;
const groupDescriptionMaxLength = 100;
const groupCategoryMaxLength = 20;
const groupCategoryMaxCount = 2;
const groupThemeColors = ['mint', 'peach', 'lilac'];

/// Creates the group and the creator's approved admin membership in one
/// batch; the rules only accept the two together. Returns the new group ID.
Future<String> createGroupInFirestore(
  FirebaseFirestore db, {
  required String uid,
  required String displayName,
  required String name,
  required String description,
  List<String> categories = const <String>[],
  String themeColor = 'mint',
}) async {
  final group = db.collection('groups').doc();
  final creator = displayName.trim();
  final batch = db.batch()
    ..set(group, {
      'name': name.trim(),
      'description': description.trim(),
      'categories': categories,
      'ownerId': uid,
      'themeColor': themeColor,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    })
    ..set(db.doc('memberships/${group.id}_$uid'), {
      'groupId': group.id,
      'userId': uid,
      'displayName': creator.isEmpty
          ? '팀믹스 사용자'
          : creator.substring(0, creator.length.clamp(0, 40)),
      'role': 'admin',
      'status': 'approved',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  await batch.commit();
  return group.id;
}
