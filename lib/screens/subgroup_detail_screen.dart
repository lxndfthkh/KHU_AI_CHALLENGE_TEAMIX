import 'package:flutter/material.dart';

import '../data/demo_group_repository.dart';
import '../data/firestore_activities_source.dart';
import '../theme.dart';
import '../data/activity_registration.dart';
import 'registration_action.dart';
import 'group_card_palette.dart';
import 'matching_settings_screen.dart';

/// UI branching only. Server/rules must enforce actual permissions.
class SubgroupDetailScreen extends StatelessWidget {
  const SubgroupDetailScreen({
    super.key,
    required this.groupName,
    this.subgroup,
    this.activity,
    this.registrationFactory,
    required this.isOperator,
    this.palette = GroupCardPalette.defaultJoined,
  });

  final String groupName;
  final DemoSubgroup? subgroup;
  final ActivityRecord? activity;
  final ActivityRegistrationApi Function()? registrationFactory;
  final bool isOperator;

  /// The parent group's color from the groups home.
  final GroupCardPalette palette;

  void _pending(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$feature 기능은 준비 중이에요.')));
  }

  void _more(BuildContext context) {
    final items = isOperator
        ? const ['소모임 정보 수정', '모집 마감하기', '활동 종료하기']
        : const ['소모임 링크 공유'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: teamixBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Material(
          color: teamixBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '소모임 메뉴',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              for (final item in items)
                ListTile(
                  title: Text(item),
                  onTap: () {
                    Navigator.pop(sheet);
                    _pending(context, item);
                  },
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusLabel => switch (activity?.status ?? subgroup!.status) {
    'recruiting' => '모집 중',
    'closed' => '모집 마감',
    'active' => '활동 중',
    'ended' => '활동 종료',
    'cancelled' => '활동 취소',
    _ => '상태 확인 필요',
  };

  Widget _info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: palette.accent)),
      const SizedBox(height: 7),
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final deadline = activity?.deadlineAt ?? subgroup!.deadline;
    final time =
        '${deadline.hour.toString().padLeft(2, '0')}:'
        '${deadline.minute.toString().padLeft(2, '0')}';
    final String teamLabel;
    if (activity != null) {
      teamLabel = '팀당 목표 ${activity!.targetTeamSize}명';
    } else {
      final capacities = (subgroup!.matchingSettings['teamCapacities'] as List)
          .cast<int>();
      final teamCount = subgroup!.matchingSettings['teamCount'] as int;
      teamLabel = capacities.isNotEmpty && capacities.toSet().length == 1
          ? '$teamCount팀 · 팀당 ${capacities.first}명'
          : '$teamCount팀';
    }
    final participantCount =
        activity?.participantCount ?? subgroup!.applicationCount;
    final capacity = activity?.capacity ?? subgroup!.recruitmentCapacity;
    return Scaffold(
      backgroundColor: teamixBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '모임 홈으로 돌아가기',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 28),
        ),
        centerTitle: true,
        title: const Text.rich(
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
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Material(
              color: teamixAccountBackground,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: '소모임 메뉴',
                onPressed: () => _more(context),
                icon: const Icon(Icons.more_horiz, color: teamixPrimary),
              ),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 25, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$groupName · ${activity?.typeLabel ?? '프로젝트'}',
                      style: TextStyle(fontSize: 11, color: palette.accent),
                    ),
                  ),
                  Material(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(fontSize: 11, color: palette.accent),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                activity?.title ?? subgroup!.title,
                style: const TextStyle(
                  fontSize: 24,
                  height: 1.4,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                activity?.description ?? subgroup!.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: teamixActionForeground,
                ),
              ),
              const SizedBox(height: 22),
              Material(
                color: palette.background,
                borderRadius: BorderRadius.circular(21),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(19),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _info(
                              '신청 인원',
                              '$participantCount / $capacity명',
                            ),
                          ),
                          Expanded(child: _info('팀 구성', teamLabel)),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _info(
                        '신청 마감',
                        '${deadline.month}월 ${deadline.day}일 · $time',
                      ),
                    ],
                  ),
                ),
              ),
              if (isOperator) ...[
                const SizedBox(height: 22),
                Material(
                  key: const ValueKey('subgroup-operator-panel'),
                  color: lilac,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '운영진 관리',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: teamixPurpleAccent,
                                ),
                              ),
                            ),
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: teamixPurpleAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '신청 현황을 확인하고 모집 마감 후 팀을 편성해요.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.8,
                            color: teamixActionForeground,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => _pending(context, '신청 현황'),
                              child: Text('신청 현황 · $participantCount명'),
                            ),
                            OutlinedButton(
                              onPressed: activity != null
                                  ? () => _pending(context, '팀 편성 관리')
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const MatchingSettingsScreen(),
                                      ),
                                    ),
                              child: const Text('팀 편성 관리 →'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: teamixBackground,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 15, 20, 20),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activity != null && registrationFactory != null)
                    RegistrationAction(factory: registrationFactory!, activity: activity!)
                  else FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: teamixAddBackground,
                      foregroundColor: teamixAddForeground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () => _pending(context, '참가 신청'),
                    child: const Text('참가 신청하기'),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    isOperator
                        ? '운영진도 신청하면 팀 편성에 참여할 수 있어요.'
                        : '설문을 제출하면 참가 신청이 완료돼요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: teamixMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns a stable detail subscription. No matching settings are requested.
class RealSubgroupDetailScreen extends StatefulWidget {
  const RealSubgroupDetailScreen({
    super.key,
    required this.source,
    this.registrationFactory,
    required this.activityId,
    required this.groupId,
    required this.groupName,
    required this.isOperator,
    required this.palette,
    this.themeColor,
  });
  final ActivitiesSource source;
  final ActivityRegistrationApi Function()? registrationFactory;
  final String activityId, groupId, groupName;
  final String? themeColor;
  final bool isOperator;
  final GroupCardPalette palette;
  @override
  State<RealSubgroupDetailScreen> createState() =>
      _RealSubgroupDetailScreenState();
}

class _RealSubgroupDetailScreenState extends State<RealSubgroupDetailScreen> {
  late Stream<ActivityRecord?> stream;
  @override
  void initState() {
    super.initState();
    stream = widget.source.watchActivity(widget.activityId);
  }

  @override
  void didUpdateWidget(covariant RealSubgroupDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.activityId != widget.activityId) {
      stream = widget.source.watchActivity(widget.activityId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ActivityRecord?>(
    stream: stream,
    builder: (context, snapshot) {
      String? message;
      if (snapshot.hasError) {
        message = '소모임을 불러오지 못했어요. 잠시 후 다시 열어 주세요.';
      }
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('소모임 상세')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final activity = snapshot.data;
      if (message == null &&
          (activity == null || activity.groupId != widget.groupId)) {
        message = '소모임이 없거나 더 이상 확인할 수 없어요.';
      }
      if (message != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('소모임 상세')),
          body: Center(child: Text(message)),
        );
      }
      return SubgroupDetailScreen(
        groupName: widget.groupName,
        activity: activity,
        registrationFactory: widget.registrationFactory,
        isOperator: widget.isOperator,
        palette: GroupCardPalette.fromTheme(
          activity!.themeColor,
          fallback: GroupCardPalette.fromTheme(
            widget.themeColor,
            fallback: widget.palette,
          ),
        ),
      );
    },
  );
}
