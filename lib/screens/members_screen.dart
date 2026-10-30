import 'package:flutter/material.dart';

import '../data/group_admin.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// Operator member management: approved members with their role, and
/// make admin / remove admin / remove from group (functions setMemberRole,
/// removeMember). The owner and the operator themself have no actions.
class MembersScreen extends StatefulWidget {
  const MembersScreen({
    super.key,
    required this.groupName,
    required this.members,
    required this.ownerId,
    required this.selfId,
    required this.onSetRole,
    required this.onRemove,
    this.palette = GroupCardPalette.defaultJoined,
  });

  final String groupName;
  final Stream<List<GroupMember>> members;
  final Future<String?> ownerId;
  final String selfId;
  final Future<void> Function(GroupMember member, bool admin) onSetRole;
  final Future<void> Function(GroupMember member) onRemove;
  final GroupCardPalette palette;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  String? _owner;
  final _working = <String>{};

  @override
  void initState() {
    super.initState();
    widget.ownerId.then((id) {
      if (mounted) setState(() => _owner = id);
    }, onError: (_) {});
  }

  Future<void> _act(
    GroupMember m,
    Future<void> Function() action,
    String done,
  ) async {
    setState(() => _working.add(m.userId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('처리하지 못했어요. 대표자는 바꾸거나 내보낼 수 없어요.')),
      );
    } finally {
      if (mounted) setState(() => _working.remove(m.userId));
    }
  }

  Future<void> _remove(GroupMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${m.displayName}님을 내보낼까요?'),
        content: const Text(
          '공개 전 소모임 신청은 취소되고, 공개된 팀 기록은 남아요. '
          '다시 들어오려면 새 초대가 필요해요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text(
              '내보내기',
              style: TextStyle(color: teamixAddForeground),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _act(m, () => widget.onRemove(m), '${m.displayName}님을 내보냈어요.');
  }

  String _roleLabel(GroupMember m) => m.userId == _owner
      ? '대표자'
      : m.admin
      ? '운영진'
      : '부원';

  Widget _row(GroupMember m) {
    final locked = m.userId == _owner || m.userId == widget.selfId;
    final working = _working.contains(m.userId);
    return Material(
      color: m.admin ? widget.palette.background : teamixActionBackground,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m.userId == widget.selfId
                    ? '${m.displayName} (나)'
                    : m.displayName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: teamixBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _roleLabel(m),
                style: TextStyle(fontSize: 11, color: widget.palette.accent),
              ),
            ),
            if (locked)
              const SizedBox(width: 48)
            else
              PopupMenuButton<String>(
                key: ValueKey('member-menu-${m.userId}'),
                tooltip: '${m.displayName} 관리',
                enabled: !working,
                onSelected: (v) => switch (v) {
                  'promote' => _act(
                    m,
                    () => widget.onSetRole(m, true),
                    '${m.displayName}님을 운영진으로 지정했어요.',
                  ),
                  'demote' => _act(
                    m,
                    () => widget.onSetRole(m, false),
                    '${m.displayName}님의 운영진을 해제했어요.',
                  ),
                  _ => _remove(m),
                },
                itemBuilder: (_) => [
                  if (m.admin)
                    const PopupMenuItem(value: 'demote', child: Text('운영진 해제'))
                  else
                    const PopupMenuItem(
                      value: 'promote',
                      child: Text('운영진으로 지정'),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      '모임에서 내보내기',
                      style: TextStyle(color: teamixAddForeground),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '모임 홈으로 돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      centerTitle: true,
      title: const Text(
        '부원 관리',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<List<GroupMember>>(
          stream: widget.members,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('부원 목록을 불러오지 못했어요.'));
            }
            final members = snapshot.data;
            if (members == null) {
              return const Center(child: CircularProgressIndicator());
            }
            // Owner first, then admins, then members, each by name.
            final sorted = [...members]
              ..sort((a, b) {
                int rank(GroupMember m) => m.userId == _owner
                    ? 0
                    : m.admin
                    ? 1
                    : 2;
                final r = rank(a).compareTo(rank(b));
                return r != 0 ? r : a.displayName.compareTo(b.displayName);
              });
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: sorted.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => i == 0
                  ? Text(
                      '${widget.groupName} · ${members.length}명 · '
                      '운영진 ${members.where((m) => m.admin).length}명',
                      style: const TextStyle(fontSize: 12, color: teamixMuted),
                    )
                  : _row(sorted[i - 1]),
            );
          },
        ),
      ),
    ),
  );
}
