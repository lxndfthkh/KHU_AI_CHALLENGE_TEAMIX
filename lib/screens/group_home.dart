import 'package:flutter/material.dart';

import '../theme.dart';
import '../data/activity_backend.dart';
import '../data/demo_group_repository.dart';
import '../data/firestore_activities_source.dart';
import '../data/formation_backend.dart';
import '../widgets/invite_code_dialog.dart';
import 'activity_admin.dart';
import 'activity_feedback_flow.dart';
import 'create_activity_screen.dart';
import 'group_card_palette.dart';
import 'subgroup_detail_screen.dart';
import 'matching_settings_screen.dart';
import 'placement_preferences_screen.dart';

/// UI preview only: operator access here is not an authorization decision.
class GroupHome extends StatelessWidget {
  const GroupHome({
    super.key,
    this.groupName = '경희 메이커스',
    this.isOperator = false,
    this.palette = GroupCardPalette.defaultJoined,
    this.onIssueInvite,
    this.onDeactivateInvite,
    this.onOpenJoinRequests,
    this.onOpenMembers,
    this.groupId,
    this.themeColor,
    this.activitiesSource,
    this.activityBackend,
    this.formationBackend,
  });

  final String groupName;
  final String? groupId, themeColor;
  final ActivitiesSource? activitiesSource;

  /// Subgroup creation, registrations and my team; null in demo mode.
  final ActivityBackend? activityBackend;

  /// Formation server client for operators; null if not configured.
  final FormationBackend? formationBackend;
  final bool isOperator;

  ActivityAdmin? get _admin =>
      activitiesSource == null || activityBackend == null || groupId == null
      ? null
      : ActivityAdmin(
          source: activitiesSource!,
          backend: activityBackend!,
          formation: formationBackend,
          groupId: groupId!,
          palette: palette,
        );

  Future<void> _pickForFormation(BuildContext context) async {
    final admin = _admin;
    if (admin == null) return _preview(context, '팀 편성');
    final open = [
      for (final a in await activitiesSource!.watchActivities(groupId!).first)
        if (a.status == 'recruiting' || a.status == 'closed') a,
    ];
    if (!context.mounted) return;
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('편성할 소모임이 없어요. 소모임을 먼저 만들어 주세요.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<ActivityRecord>(
      context: context,
      backgroundColor: teamixBackground,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '어느 소모임을 편성할까요?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final a in open)
              ListTile(
                title: Text(a.title),
                subtitle: Text('${a.statusLabel} · 신청 ${a.participantCount}명'),
                onTap: () => Navigator.pop(sheet, a),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) {
      await admin.formationFor(context, picked);
    }
  }

  void _openAll(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: teamixBackground,
          appBar: AppBar(
            leading: IconButton(
              tooltip: '모임 홈으로 돌아가기',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.chevron_left, size: 28),
            ),
            centerTitle: true,
            title: const Text(
              '소모임 전체',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _RealActivities(
                    source: activitiesSource!,
                    groupId: groupId!,
                    groupName: groupName,
                    palette: palette,
                    themeColor: themeColor,
                    isOperator: isOperator,
                    activityBackend: activityBackend,
                    formationBackend: formationBackend,
                    showAll: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _createActivity(BuildContext context, ActivityBackend backend) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CreateActivityScreen(
          groupName: groupName,
          palette: palette,
          onCreate: (activity) => backend.createActivity(groupId!, activity),
        ),
      ),
    );
  }

  /// Same colors as this group's card on the groups home.
  final GroupCardPalette palette;

  /// Issues a real invite code; null keeps the demo notice.
  final Future<String> Function()? onIssueInvite;

  /// Turns an issued code off from the invite popup.
  final Future<void> Function(String code)? onDeactivateInvite;

  /// Opens the real join request list; null keeps the demo notice.
  final VoidCallback? onOpenJoinRequests;

  /// Opens the real member management; null keeps the demo notice.
  final VoidCallback? onOpenMembers;
  void _detail(BuildContext context, DemoSubgroup subgroup) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SubgroupDetailScreen(
          groupName: groupName,
          subgroup: subgroup,
          isOperator: isOperator,
          palette: palette,
        ),
      ),
    );
  }

  void _preview(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$feature 기능은 준비 중이에요.')));
  }

  Future<void> _leave(BuildContext context, ActivityBackend backend) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('$groupName에서 나갈까요?'),
        content: const Text(
          '공개 전 소모임 신청은 취소되고, 공개된 팀 기록은 남아요. '
          '다시 들어오려면 초대 코드가 필요해요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await backend.leaveGroup(groupId!);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('$groupName에서 나왔어요.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('나가지 못했어요. 혼자 남은 운영진은 나갈 수 없어요.')),
      );
    }
  }

  void _more(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: teamixBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Real feedback lives on each ended subgroup, so only the demo
            // keeps this entry.
            if (activityBackend == null)
              ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: const Text('소모임 평가하기'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (activityBackend == null) {
                    _preview(context, '소모임 선택 및 평가');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('활동이 끝난 소모임의 상세에서 후기를 남길 수 있어요.'),
                      ),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('모임 나가기'),
              onTap: () {
                Navigator.pop(sheet);
                if (activityBackend == null || groupId == null) {
                  _preview(context, '모임 나가기');
                } else {
                  _leave(context, activityBackend!);
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: '내 모임으로 돌아가기',
                    icon: const Icon(Icons.chevron_left, size: 28, color: ink),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text.rich(
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
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 36,
                    child: Material(
                      color: teamixAccountBackground,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _more(context),
                        child: const Tooltip(
                          message: '모임 메뉴',
                          child: Icon(Icons.more_horiz, color: teamixPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              Row(
                children: [
                  Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.filter_vintage_outlined,
                      size: 29,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupName,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: palette.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isOperator ? '운영진' : '부원',
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              if (isOperator)
                Row(
                  children: [
                    Expanded(
                      child: _Action(
                        icon: Icons.north_east,
                        text: '초대 공유',
                        onTap: onIssueInvite == null
                            ? () => _preview(context, '초대 공유')
                            : () => showInviteCodeDialog(
                                context,
                                onIssueInvite!,
                                deactivate: onDeactivateInvite,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Action(
                        icon: Icons.list,
                        text: '부원 관리',
                        onTap:
                            onOpenMembers ?? () => _preview(context, '부원 관리'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Action(
                        icon: Icons.add,
                        text: '소모임 창설',
                        onTap: activityBackend == null || groupId == null
                            ? () => _preview(context, '소모임 창설')
                            : () => _createActivity(context, activityBackend!),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              if (isOperator)
                FilledButton.icon(
                  onPressed: activitiesSource != null
                      ? () => _pickForFormation(context)
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const MatchingSettingsScreen(),
                          ),
                        ),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('팀 편성'),
                ),
              const SizedBox(height: 16),
              if (isOperator)
                Material(
                  color: lilac,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap:
                        onOpenJoinRequests ??
                        () => _preview(context, '가입 요청 관리'),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Text(
                            '가입 요청 관리',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: teamixRequestForeground,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '확인하기 ›',
                            style: TextStyle(
                              fontSize: 10,
                              color: teamixRequestForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (activityBackend != null && groupId != null) ...[
                if (isOperator) const SizedBox(height: 8),
                Material(
                  key: const ValueKey('placement-preferences-entry'),
                  color: teamixActionBackground,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PlacementPreferencesScreen(
                          groupName: groupName,
                          groupId: groupId!,
                          backend: activityBackend!,
                        ),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 15,
                            color: teamixActionForeground,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '다른 팀이면 좋겠는 사람 · 비공개',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: teamixActionForeground,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '설정하기 ›',
                            style: TextStyle(
                              fontSize: 10,
                              color: teamixActionForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '진행 중인 소모임',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: activitiesSource == null || groupId == null
                        ? () => _preview(context, '소모임 전체 목록')
                        : () => _openAll(context),
                    child: const Text(
                      '전체 보기 ›',
                      style: TextStyle(fontSize: 10, color: teamixMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (activitiesSource != null)
                _RealActivities(
                  source: activitiesSource!,
                  groupId: groupId!,
                  groupName: groupName,
                  palette: palette,
                  themeColor: themeColor,
                  isOperator: isOperator,
                  activityBackend: activityBackend,
                  formationBackend: formationBackend,
                )
              else
                for (final subgroup in DemoGroupRepository.subgroupsFor(
                  groupName,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _Activity(
                      title: subgroup.title,
                      questions: '희망 역할 · 가능 시간 · 경험 수준',
                      color: palette.background,
                      accent: palette.accent,
                      onDetail: () => _detail(context, subgroup),
                      onEdit: isOperator
                          ? () => _preview(context, '소모임 내용·상태 수정')
                          : null,
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: teamixActionBackground,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: teamixActionForeground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  color: teamixActionForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity({
    required this.title,
    required this.questions,
    required this.color,
    required this.accent,
    required this.onDetail,
    required this.onEdit,
    this.statusLabel = '참가 모집 중',
    this.typeLabel = '프로젝트',
  });

  final String title, questions;
  final String statusLabel, typeLabel;
  final Color color, accent;
  final VoidCallback onDetail;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(21),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(typeLabel, style: TextStyle(fontSize: 10, color: accent)),
            const Spacer(),
            Container(
              height: 22,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: teamixBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 9, color: accent),
              ),
            ),
            const SizedBox(width: 6),
            if (onEdit != null)
              SizedBox.square(
                dimension: 22,
                child: Material(
                  color: teamixBackground.withAlpha(180),
                  shape: CircleBorder(
                    side: BorderSide(color: accent.withAlpha(45)),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEdit,
                    child: Tooltip(
                      message: '소모임 관리 및 수정',
                      child: Icon(
                        Icons.settings_outlined,
                        size: 13,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
            color: ink,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: Text(
                questions,
                style: TextStyle(fontSize: 10, color: accent),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onDetail,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  '소모임 상세보기 ↗',
                  style: TextStyle(fontSize: 9, color: accent),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RealActivities extends StatefulWidget {
  const _RealActivities({
    required this.source,
    required this.groupId,
    required this.groupName,
    required this.palette,
    required this.isOperator,
    this.themeColor,
    this.activityBackend,
    this.formationBackend,
    this.showAll = false,
  });
  final ActivitiesSource source;
  final String groupId, groupName;

  /// Lists ended subgroups whose feedback closed too (전체 보기).
  final bool showAll;
  final String? themeColor;
  final GroupCardPalette palette;
  final bool isOperator;
  final ActivityBackend? activityBackend;
  final FormationBackend? formationBackend;
  @override
  State<_RealActivities> createState() => _RealActivitiesState();
}

class _RealActivitiesState extends State<_RealActivities> {
  late Stream<List<ActivityRecord>> stream;
  @override
  void initState() {
    super.initState();
    stream = widget.source.watchActivities(widget.groupId);
  }

  @override
  void didUpdateWidget(covariant _RealActivities oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.groupId != widget.groupId) {
      stream = widget.source.watchActivities(widget.groupId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ActivityRecord>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('소모임을 불러오지 못했어요. 잠시 후 다시 열어 주세요.');
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      // Ended activities stay only while feedback is open.
      final activities = [
        for (final a in snapshot.data ?? const <ActivityRecord>[])
          if (widget.showAll || a.status != 'ended' || a.feedbackOpen) a,
      ];
      final backend = widget.activityBackend;
      final admin = backend == null || !widget.isOperator
          ? null
          : ActivityAdmin(
              source: widget.source,
              backend: backend,
              formation: widget.formationBackend,
              groupId: widget.groupId,
              palette: widget.palette,
            );
      if (backend != null && !widget.showAll) {
        for (final a in activities.where((a) => a.feedbackOpen)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            maybePromptFeedback(
              context,
              backend,
              widget.groupId,
              a,
              widget.palette,
            );
          });
        }
      }
      if (activities.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('등록된 소모임이 없어요.'),
        );
      }
      return Column(
        children: [
          for (final activity in activities)
            Builder(
              builder: (context) {
                // Subgroups share their group's card color.
                final palette = widget.palette;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _Activity(
                    title: activity.title,
                    questions:
                        '신청 ${activity.participantCount} / ${activity.capacity}명',
                    statusLabel: activity.feedbackOpen
                        ? '후기 · D-${activity.feedbackDaysLeft(DateTime.now()) ?? 0}'
                        : activity.statusLabel,
                    typeLabel: activity.typeLabel,
                    color: palette.background,
                    accent: palette.accent,
                    onEdit: admin == null
                        ? null
                        : () => admin.showMenu(
                            context,
                            activity,
                            onOpenDetail: () => _openDetail(context, activity),
                          ),
                    onDetail: () => _openDetail(context, activity),
                  ),
                );
              },
            ),
        ],
      );
    },
  );

  void _openDetail(BuildContext context, ActivityRecord activity) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RealSubgroupDetailScreen(
            source: widget.source,
            activityId: activity.id,
            groupId: widget.groupId,
            groupName: widget.groupName,
            themeColor: widget.themeColor,
            palette: widget.palette,
            isOperator: widget.isOperator,
            activityBackend: widget.activityBackend,
            formationBackend: widget.formationBackend,
          ),
        ),
      );
}
