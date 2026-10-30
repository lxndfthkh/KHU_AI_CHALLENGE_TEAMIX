/// One card on the groups home, built from `memberships/{groupId}_{uid}`
/// plus, for approved members, `groups/{groupId}` and recruiting activities.
class GroupSummary {
  const GroupSummary({
    required this.groupId,
    required this.name,
    required this.role,
    required this.status,
    this.isOwner = false,
    this.themeColor,
    this.activityTitles = const <String>[],
  });

  /// Pending members can't read `groups/{id}` until approved.
  static const pendingName = '승인 대기 중인 모임';
  static const unknownName = '모임 정보를 불러오지 못했어요';

  factory GroupSummary.fromFirestore({
    required String uid,
    required Map<String, dynamic> membership,
    Map<String, dynamic>? group,
    List<String> activityTitles = const <String>[],
  }) {
    final status = membership['status'] as String? ?? '';
    final groupName = group?['name'];
    return GroupSummary(
      groupId: membership['groupId'] as String? ?? '',
      name: groupName is String && groupName.isNotEmpty
          ? groupName
          : status == 'pending'
          ? pendingName
          : unknownName,
      role: membership['role'] as String? ?? 'member',
      status: status,
      isOwner: group?['ownerId'] == uid,
      themeColor: group?['themeColor'] as String?,
      activityTitles: activityTitles,
    );
  }

  final String groupId;
  final String name;

  /// `admin | member`, the only authoritative role source.
  final String role;

  /// `approved | pending`; other statuses are not shown on the home.
  final String status;
  final bool isOwner;

  /// `mint | peach | lilac`; kept for screens that follow the group color.
  final String? themeColor;
  final List<String> activityTitles;

  bool get pending => status == 'pending';
  bool get isOperator => !pending && role == 'admin';

  String get roleLabel {
    if (pending) return '승인 대기';
    return role == 'admin' ? '임원진' : '참가원';
  }
}
