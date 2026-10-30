import 'package:flutter/material.dart';

import '../theme.dart';
import '../data/demo_group_repository.dart';
import '../data/firestore_activities_source.dart';
import '../widgets/invite_code_dialog.dart';
import 'group_card_palette.dart';
import 'subgroup_detail_screen.dart';
import 'matching_settings_screen.dart';

/// UI preview only: operator access here is not an authorization decision.
class GroupHome extends StatelessWidget {
  const GroupHome({
    super.key,
    this.groupName = '경희 메이커스',
    this.isOperator = false,
    this.palette = GroupCardPalette.defaultJoined,
    this.onIssueInvite,
    this.onOpenJoinRequests,
    this.groupId,
    this.themeColor,
    this.activitiesSource,
  });

  final String groupName;
  final String? groupId, themeColor;
  final ActivitiesSource? activitiesSource;
  final bool isOperator;

  /// Same colors as this group's card on the groups home.
  final GroupCardPalette palette;

  /// Issues a real invite code; null keeps the demo notice.
  final Future<String> Function()? onIssueInvite;

  /// Opens the real join request list; null keeps the demo notice.
  final VoidCallback? onOpenJoinRequests;
  void _detail(BuildContext context, DemoSubgroup subgroup) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => SubgroupDetailScreen(
        groupName: groupName, subgroup: subgroup, isOperator: isOperator,
        palette: palette,
      ),
    ));
  }

  void _preview(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 기능은 준비 중이에요.')),
    );
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
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: const Text('소모임 평가하기'),
              onTap: () {
                Navigator.pop(sheet);
                _preview(context, '소모임 선택 및 평가');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('모임 나가기'),
              onTap: () {
                Navigator.pop(sheet);
                _preview(context, '모임 나가기');
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
                    icon: const Icon(
                      Icons.chevron_left,
                      size: 28,
                      color: ink,
                    ),
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
                          child: Icon(
                            Icons.more_horiz,
                            color: teamixPrimary,
                          ),
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
              if (isOperator) Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.north_east,
                      text: '초대 공유',
                      onTap: onIssueInvite == null
                          ? () => _preview(context, '초대 공유')
                          : () => showInviteCodeDialog(context, onIssueInvite!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.list,
                      text: '부원 관리',
                      onTap: () => _preview(context, '부원 관리'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.add,
                      text: '소모임 창설',
                      onTap: () => _preview(context, '소모임 창설'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isOperator) FilledButton.icon(
                onPressed: activitiesSource != null
                    ? () => _preview(context, '팀 편성')
                    : () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const MatchingSettingsScreen(),
                  ),
                ),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('팀 편성'),
              ),
              const SizedBox(height: 16),
              if (isOperator) Material(
                color: lilac,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onOpenJoinRequests ??
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
                    onPressed: () => _preview(context, '소모임 전체 목록'),
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
                  source: activitiesSource!, groupId: groupId!,
                  groupName: groupName, palette: palette,
                  themeColor: themeColor, isOperator: isOperator,
                )
              else for (final subgroup in DemoGroupRepository.subgroupsFor(groupName))
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
  const _Action({
    required this.icon,
    required this.text,
    required this.onTap,
  });

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
            Text(
              typeLabel,
              style: TextStyle(fontSize: 10, color: accent),
            ),
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
            if (onEdit != null) SizedBox.square(
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
  const _RealActivities({required this.source, required this.groupId,
    required this.groupName, required this.palette, required this.isOperator,
    this.themeColor});
  final ActivitiesSource source;
  final String groupId, groupName;
  final String? themeColor;
  final GroupCardPalette palette;
  final bool isOperator;
  @override
  State<_RealActivities> createState() => _RealActivitiesState();
}
class _RealActivitiesState extends State<_RealActivities> {
  late Stream<List<ActivityRecord>> stream;
  @override
  void initState() { super.initState(); stream = widget.source.watchActivities(widget.groupId); }
  @override
  void didUpdateWidget(covariant _RealActivities oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.groupId != widget.groupId) {
      stream = widget.source.watchActivities(widget.groupId);
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<List<ActivityRecord>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('소모임을 불러오지 못했어요. 잠시 후 다시 열어 주세요.');
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final activities = snapshot.data ?? const <ActivityRecord>[];
      if (activities.isEmpty) return const Padding(
        padding: EdgeInsets.all(24), child: Text('등록된 소모임이 없어요.'));
      return Column(children: [for (final activity in activities)
        Builder(builder: (context) {
          final palette = GroupCardPalette.fromTheme(activity.themeColor,
            fallback: GroupCardPalette.fromTheme(widget.themeColor, fallback: widget.palette));
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: _Activity(
            title: activity.title, questions: '신청 ${activity.participantCount} / ${activity.capacity}명',
            statusLabel: activity.statusLabel, typeLabel: activity.typeLabel,
            color: palette.background, accent: palette.accent, onEdit: null,
            onDetail: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => RealSubgroupDetailScreen(
                source: widget.source, activityId: activity.id, groupId: widget.groupId,
                groupName: widget.groupName, themeColor: widget.themeColor,
                palette: widget.palette, isOperator: widget.isOperator),
            )),
          ));
        }),
      ]);
    },
  );
}
