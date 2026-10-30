import 'package:flutter/material.dart';

import '../data/firestore_notifications.dart';
import '../theme.dart';

/// What each notification type says; names fall back when unreadable.
({IconData icon, String title, String? body}) describeNotification(
  AppNotification n,
) {
  final activity = n.activityTitle ?? '소모임';
  final group = n.groupName ?? '모임';
  return switch (n.type) {
    'teamPublished' => (
      icon: Icons.groups_outlined,
      title: '$activity 팀이 공개됐어요',
      body: '누구와 한 팀이 됐는지 확인해 보세요.',
    ),
    'teamChanged' => (
      icon: Icons.swap_horiz,
      title: '$activity 내 팀이 바뀌었어요',
      body: '바뀐 팀원을 확인해 보세요.',
    ),
    'feedbackRequested' => (
      icon: Icons.rate_review_outlined,
      title: '$activity 활동이 끝났어요',
      body: '후기를 남기면 다음 팀 편성에 반영돼요.',
    ),
    'joinApproved' => (
      icon: Icons.check_circle_outline,
      title: '$group에 가입됐어요',
      body: null,
    ),
    'joinRejected' => (
      icon: Icons.block,
      title: '$group 참여가 승인되지 않았어요',
      body: null,
    ),
    _ => (icon: Icons.notifications_none, title: '새 알림', body: null),
  };
}

/// The signed-in user's notifications, newest first. Opening one marks it
/// read and, when [onOpenGroup] can show that group, goes there.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.source,
    this.onOpenGroup,
  });

  final NotificationSource source;

  /// Opens the group home; returns false when the user can't open it now.
  final bool Function(BuildContext context, String groupId)? onOpenGroup;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<List<AppNotification>> _items = widget.source.watch();
  bool _busy = false;

  Future<void> _markRead(Iterable<String> ids) async {
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.source.markRead(ids);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('읽음으로 표시하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(AppNotification n) {
    if (n.unread) _markRead([n.id]);
    final open = widget.onOpenGroup;
    if (open != null && !open(context, n.groupId)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('지금은 이 모임을 열 수 없어요.')));
    }
  }

  static String _when(DateTime? at) {
    if (at == null) return '방금';
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return '방금';
    if (gap.inHours < 1) return '${gap.inMinutes}분 전';
    if (gap.inDays < 1) return '${gap.inHours}시간 전';
    if (gap.inDays < 7) return '${gap.inDays}일 전';
    return '${at.month}월 ${at.day}일';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppNotification>>(
    stream: _items,
    builder: (context, snapshot) {
      final items = snapshot.data;
      final unread = [
        for (final n in items ?? const <AppNotification>[])
          if (n.unread) n.id,
      ];
      return Scaffold(
        backgroundColor: teamixBackground,
        appBar: AppBar(
          leading: IconButton(
            tooltip: '내 모임으로 돌아가기',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          title: const Text(
            '알림',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: unread.isEmpty || _busy
                  ? null
                  : () => _markRead(unread),
              child: const Text('모두 읽음'),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: snapshot.hasError
                ? const _Message('알림을 불러오지 못했어요.\n잠시 후 다시 열어 주세요.')
                : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const _Message('아직 받은 알림이 없어요.\n팀이 공개되거나 활동이 끝나면 여기서 알려 드려요.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _tile(items[i]),
                  ),
          ),
        ),
      );
    },
  );

  Widget _tile(AppNotification n) {
    final d = describeNotification(n);
    return Material(
      key: ValueKey('notification-${n.id}'),
      color: n.unread ? lilac : teamixBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: teamixCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: n.unread ? teamixBackground : teamixActionBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(d.icon, size: 19, color: teamixPurpleAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: n.unread
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    if (d.body != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        d.body!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: teamixActionForeground,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [?n.groupName, _when(n.createdAt)].join(' · '),
                      style: const TextStyle(fontSize: 11, color: teamixMuted),
                    ),
                  ],
                ),
              ),
              if (n.unread)
                Container(
                  key: ValueKey('unread-${n.id}'),
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5, left: 8),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: teamixAddForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home header bell with the unread count; owns its subscription so
/// rebuilding the home doesn't resubscribe.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.source,
    required this.onTap,
  });

  final NotificationSource source;
  final VoidCallback? onTap;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late Stream<List<AppNotification>> _items = widget.source.watch();

  @override
  void didUpdateWidget(NotificationBell old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) _items = widget.source.watch();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppNotification>>(
    stream: _items,
    builder: (context, snapshot) {
      final count = (snapshot.data ?? const []).where((n) => n.unread).length;
      return Badge(
        key: const ValueKey('notification-bell'),
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        backgroundColor: teamixAddForeground,
        child: SizedBox.square(
          dimension: 36,
          child: Material(
            color: teamixActionBackground,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onTap,
              child: Tooltip(
                message: count > 0 ? '알림 $count개' : '알림',
                child: const Icon(
                  Icons.notifications_none,
                  size: 23,
                  color: teamixActionForeground,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, height: 1.6, color: teamixMuted),
    ),
  );
}
