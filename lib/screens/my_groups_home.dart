import 'package:flutter/material.dart';

import '../data/demo_group_repository.dart';
import '../data/group_repository.dart';
import '../theme.dart';
import 'group_home.dart';

class MyGroupsHome extends StatelessWidget {
  const MyGroupsHome({
    super.key,
    required this.repository,
    required this.onCreateGroup,
    required this.onJoinGroup,
    required this.onSignOut,
    this.demoMode = false,
    this.busy = false,
    this.onToggleDemoGroups,
  });

  final GroupRepository repository;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;
  final Future<void> Function() onSignOut;
  final bool demoMode;
  final bool busy;
  final VoidCallback? onToggleDemoGroups;

  void _notice(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

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
    final empty = repository.memberships.isEmpty;

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
                    : '인증만 실제 연결 · 모임 정보는 메모리 시연 데이터예요.',
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

  String _statusLabel(String status) {
    switch (status) {
      case 'owner':
        return '대표자';
      case 'member':
        return '부원';
      case 'pending':
        return '승인 대기';
      default:
        return '상태 확인 필요';
    }
  }

  void _openGroup(BuildContext context, String name, String status) {
    // 기존 GroupHome은 경희 메이커스 운영진용 하드코딩 시연 화면이다.
    // 실제 권한 검증은 아니며, 다른 모임/부원에게 잘못 연결하지 않는다.
    if (status == 'owner') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GroupHome(groupName: name)),
      );
      return;
    }

    _notice(context, '모임 상세는 아직 연결되지 않은 시연 화면이에요.');
  }

  Widget _card(BuildContext context, MapEntry<String, String> entry) {
    final name = entry.key;
    final status = entry.value;
    final pending = status == 'pending';
    final walking = name == '주말 산책 모임';

    final background = pending ? lilac : walking ? butter : mint;
    final accent = pending
        ? teamixPurpleAccent
        : walking
        ? teamixPeachAccent
        : teamixPrimary;

    final activities =
        DemoGroupRepository.exampleActivities[name] ?? const <String>[];

    return _GroupCard(
      name: name,
      color: background,
      accent: accent,
      activities: activities,
      roleLabel: _statusLabel(status),
      pending: pending,
      onTap: pending || busy
          ? null
          : () => _openGroup(context, name, status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = repository.memberships.entries.toList();

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
                if (entries.isEmpty)
                  const _EmptyGroups()
                else
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _card(context, entries[i]),
                  ],
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
          style: TextStyle(
            fontSize: 12,
            height: 1.9,
            color: teamixEmptyBody,
          ),
        ),
      ],
    ),
  );
}
