import 'package:flutter/material.dart';

import '../data/activity_backend.dart';
import '../data/group_admin.dart';
import '../models/group_summary.dart';
import '../theme.dart';
import 'group_card_palette.dart';
import 'group_home.dart';
import 'join_requests_screen.dart';

class MyGroupsHome extends StatelessWidget {
  const MyGroupsHome({
    super.key,
    required this.groups,
    required this.onCreateGroup,
    required this.onJoinGroup,
    required this.onSignOut,
    this.loadFailed = false,
    this.demoMode = false,
    this.busy = false,
    this.onToggleDemoGroups,
    this.groupAdmin,
    this.activityBackend,
  });

  /// `null` while the first snapshot is loading.
  final List<GroupSummary>? groups;
  final bool loadFailed;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;
  final Future<void> Function() onSignOut;
  final bool demoMode;
  final bool busy;
  final VoidCallback? onToggleDemoGroups;

  /// Issues an invite code for a group ID; null in demo mode.
  /// Firestore operator actions (invites, join requests); null in demo mode.
  final GroupAdmin? groupAdmin;

  /// Firestore subgroups and registrations; null in demo mode.
  final ActivityBackend? activityBackend;

  void _add(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: teamixBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(27)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '새로운 모임과 함께해요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('모임 만들기'),
                subtitle: const Text('우리 동아리의 새로운 공간을 만들어요.'),
                onTap: busy
                    ? null
                    : () {
                        Navigator.pop(sheet);
                        onCreateGroup();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.login_outlined),
                title: const Text('모임 참가하기'),
                subtitle: const Text('초대 코드로 참여를 요청해요.'),
                onTap: busy
                    ? null
                    : () {
                        Navigator.pop(sheet);
                        onJoinGroup();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _account(BuildContext context) {
    final empty = groups?.isEmpty ?? true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: teamixBackground,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '계정 정보',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                demoMode
                    ? '디자인 시연 모드 · 실제 계정에 연결되지 않았어요.'
                    : '내 모임, 모임 만들기, 초대 코드 참여, 가입 승인은 Firestore에 연결돼 있어요.',
                style: const TextStyle(color: teamixMuted),
              ),
              if (demoMode && onToggleDemoGroups != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(empty ? '예시 모임 3개 보기' : '빈 화면 보기'),
                  onTap: busy
                      ? null
                      : () {
                          Navigator.pop(sheet);
                          onToggleDemoGroups!();
                        },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('로그아웃'),
                onTap: busy
                    ? null
                    : () async {
                        Navigator.pop(sheet);
                        await onSignOut();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circle(
    IconData icon,
    String label,
    Color background,
    Color foreground,
    VoidCallback tap,
  ) => SizedBox.square(
    dimension: 36,
    child: Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : tap,
        child: Tooltip(
          message: label,
          child: Icon(icon, size: 23, color: foreground),
        ),
      ),
    ),
  );

  void _openGroup(
    BuildContext context,
    GroupSummary group,
    GroupCardPalette palette,
  ) {
    final admin = group.isOperator ? groupAdmin : null;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (home) => GroupHome(
          groupName: group.name,
          isOperator: group.isOperator,
          palette: palette,
          groupId: activityBackend == null ? null : group.groupId,
          activityBackend: activityBackend,
          onIssueInvite: admin == null
              ? null
              : () => admin.issueInvitation(group.groupId),
          onOpenJoinRequests: admin == null
              ? null
              : () => Navigator.of(home).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => JoinRequestsScreen(
                      groupName: group.name,
                      requests: admin.joinRequests(group.groupId),
                      onDecide: (request, approve) => admin.decideJoin(
                        group.groupId,
                        request.userId,
                        approve: approve,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, GroupSummary group, int joinedIndex) {
    final palette = GroupCardPalette.forGroup(
      joinedIndex,
      isPending: group.pending,
    );

    return _GroupCard(
      name: group.name,
      color: palette.background,
      accent: palette.accent,
      activities: group.activityTitles,
      roleLabel: group.roleLabel,
      pending: group.pending,
      onTap: group.pending || busy ? null : () => _openGroup(context, group, palette),
    );
  }

  List<Widget> _groupList(BuildContext context) {
    final entries = groups;
    if (loadFailed) {
      return [
        const _LoadMessage(
          key: ValueKey('groups-load-failed'),
          text: '내 모임을 불러오지 못했어요.\n잠시 후 다시 열어 주세요.',
        ),
      ];
    }
    if (entries == null) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (entries.isEmpty) return const [_EmptyGroups()];
    return [
      for (var i = 0; i < entries.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        _card(
          context,
          entries[i],
          // Pending groups don't advance the joined-color rotation.
          entries.take(i).where((g) => !g.pending).length,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Row(
                  children: [
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'teamix',
                            style: TextStyle(color: ink),
                          ),
                          TextSpan(
                            text: '.',
                            style: TextStyle(color: teamixLogoAccent),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const Spacer(),
                    _circle(
                      Icons.add,
                      '모임 추가',
                      teamixAddBackground,
                      teamixAddForeground,
                      () => _add(context),
                    ),
                    const SizedBox(width: 12),
                    _circle(
                      Icons.person_outline,
                      '계정 정보',
                      teamixAccountBackground,
                      teamixPrimary,
                      () => _account(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '내 모임',
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 12),
                ..._groupList(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.name,
    required this.color,
    required this.accent,
    required this.activities,
    required this.roleLabel,
    this.pending = false,
    this.onTap,
  });

  final String name;
  final Color color, accent;
  final List<String> activities;
  final String roleLabel;
  final bool pending;
  final VoidCallback? onTap;

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: teamixBackground.withAlpha(200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: accent)),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: teamixCardBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 11, 17, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: teamixBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    pending ? Icons.schedule : Icons.filter_vintage_outlined,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                _badge(roleLabel),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: teamixBackground.withAlpha(170),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending ? '승인 기다리는 소모임' : '진행 중인 소모임',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (activities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '등록된 소모임이 없어요.',
                        style: TextStyle(fontSize: 11, color: accent),
                      ),
                    ),
                  for (final activity in activities.take(2))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              activity,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _badge(pending ? '승인 대기' : '참가 모집 중'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                pending ? '승인을 기다리는 중' : '모임 들어가기 ↗',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LoadMessage extends StatelessWidget {
  const _LoadMessage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      color: teamixEmptyBackground,
      border: Border.all(color: teamixEmptyBorder),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        height: 1.7,
        color: teamixEmptyTitle,
      ),
    ),
  );
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      color: teamixEmptyBackground,
      border: Border.all(color: teamixEmptyBorder),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: teamixEmptyIconBackground,
            borderRadius: BorderRadius.circular(21),
          ),
          child: const Icon(
            Icons.filter_vintage_outlined,
            color: teamixEmptyIcon,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '아직 함께하는 모임이 없어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: teamixEmptyTitle,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '오른쪽 위 ＋를 눌러\n모임을 만들거나 초대 코드로 참여해보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.9, color: teamixEmptyBody),
        ),
      ],
    ),
  );
}
