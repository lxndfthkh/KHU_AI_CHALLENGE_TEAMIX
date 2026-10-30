import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Matches `^[A-HJ-NP-Z2-9]{8}$` in firestore.rules (no I, O, 0, 1).
const inviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const inviteCodeLength = 8;
const inviteValidity = Duration(days: 7);

String newInviteCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < inviteCodeLength; i++)
      inviteCodeAlphabet.codeUnitAt(r.nextInt(inviteCodeAlphabet.length)),
  ]);
}

/// What a code holder may see before joining (v7: 이름·소개).
class InvitationPreview {
  const InvitationPreview({
    required this.code,
    required this.groupId,
    required this.groupName,
    required this.description,
  });

  final String code;
  final String groupId;
  final String groupName;
  final String description;
}

/// Issues a 7-day code for a group the caller administers.
Future<String> issueInvitation(
  FirebaseFirestore db, {
  required String uid,
  required String groupId,
  Random? random,
}) async {
  final group = (await db.doc('groups/$groupId').get()).data();
  if (group == null) {
    throw StateError('group $groupId is not readable');
  }
  // A taken code fails as an update; retry with a fresh one.
  for (var attempt = 0; ; attempt++) {
    final code = newInviteCode(random);
    try {
      await db.doc('invitations/$code').set({
        'groupId': groupId,
        'groupName': group['name'],
        'description': group['description'],
        'active': true,
        // Slightly under 7 days so client clock drift can't exceed the rule.
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(inviteValidity - const Duration(minutes: 5)),
        ),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return code;
    } on FirebaseException {
      if (attempt >= 2) rethrow;
    }
  }
}

/// Null when the code is unknown, expired or switched off.
Future<InvitationPreview?> findInvitation(
  FirebaseFirestore db,
  String rawCode,
) async {
  final code = rawCode.trim().toUpperCase();
  if (!RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code)) return null;
  try {
    final data = (await db.doc('invitations/$code').get()).data();
    if (data == null ||
        data['active'] != true ||
        data['expiresAt'] is! Timestamp ||
        (data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
      return null;
    }
    return InvitationPreview(
      code: code,
      groupId: data['groupId'] as String,
      groupName: data['groupName'] as String? ?? '',
      description: data['description'] as String? ?? '',
    );
  } on FirebaseException {
    // The rules refuse missing, expired and inactive codes alike.
    return null;
  }
}

/// `approved | pending | rejected | left`, or null if never requested.
Future<String?> myMembershipStatus(
  FirebaseFirestore db, {
  required String uid,
  required String groupId,
}) async {
  final mine = await db
      .collection('memberships')
      .where('userId', isEqualTo: uid)
      .where('groupId', isEqualTo: groupId)
      .get();
  return mine.docs.isEmpty ? null : mine.docs.first.data()['status'] as String?;
}

/// Creates the caller's pending membership; an admin approves it later.
Future<void> requestJoin(
  FirebaseFirestore db, {
  required String uid,
  required String displayName,
  required InvitationPreview invitation,
}) {
  final name = displayName.trim();
  return db.doc('memberships/${invitation.groupId}_$uid').set({
    'groupId': invitation.groupId,
    'userId': uid,
    'displayName': name.isEmpty
        ? '팀믹스 사용자'
        : name.substring(0, name.length.clamp(0, 40)),
    'role': 'member',
    'status': 'pending',
    'invitationId': invitation.code,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
