import 'package:flutter/material.dart';
import '../data/demo_group_repository.dart';
import '../models/activity.dart';
import '../theme.dart';
import 'group_card_palette.dart';
import 'matching_settings_screen.dart';

/// UI branching only. Server/rules must enforce actual permissions.
class SubgroupDetailScreen extends StatelessWidget {
  const SubgroupDetailScreen({
    super.key,
    required this.groupName,
    required this.subgroup,
    required this.isOperator,
    this.palette = GroupCardPalette.defaultJoined,
    this.registration,
    this.onApply,
    this.onManageFormation,
    this.myTeam,
  });

  final String groupName;
  final DemoSubgroup subgroup;
  final bool isOperator;

  /// The caller's own registration; null keeps the demo notice.
  final Stream<Registration?>? registration;

  /// Opens the survey (new or edit); null when not recruiting.
  final void Function(Registration? current)? onApply;

  /// Opens the real formation screen; null keeps the demo matching screen.
  final VoidCallback? onManageFormation;

  /// The participant's published team, if any.
  final Widget? myTeam;

  /// The parent group's color from the groups home.
  final GroupCardPalette palette;

  void _pending(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 기능은 준비 중이에요.')),
    );
  }

  Widget _applyButton(String label, VoidCallback? onPressed) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: teamixAddBackground,
      foregroundColor: teamixAddForeground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    onPressed: onPressed,
    child: Text(label),
  );

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
                child: Text('소모임 메뉴',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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

  String get _statusLabel => switch (subgroup.status) {
        'recruiting' => '모집 중',
        'closed' => '모집 마감',
        'active' => '활동 중',
        'ended' => '활동 종료',
        _ => '상태 확인 필요',
      };

  Widget _info(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: palette.accent)),
          const SizedBox(height: 7),
          Text(value, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final deadline = subgroup.deadline;
    final time = '${deadline.hour.toString().padLeft(2, '0')}:'
        '${deadline.minute.toString().padLeft(2, '0')}';
    final capacities = (subgroup.matchingSettings['teamCapacities'] as List)
        .cast<int>();
    final teamCount = subgroup.matchingSettings['teamCount'] as int;
    final teamLabel = capacities.isNotEmpty && capacities.toSet().length == 1
        ? '$teamCount팀 · 팀당 ${capacities.first}명'
        : '$teamCount팀';
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
          TextSpan(children: [
            TextSpan(text: 'teamix', style: TextStyle(color: ink)),
            TextSpan(text: '.', style: TextStyle(color: teamixLogoAccent)),
          ]),
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900,
              letterSpacing: -1),
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
              Row(children: [
                Expanded(child: Text('$groupName · 프로젝트',
                    style: TextStyle(fontSize: 11, color: palette.accent))),
                Material(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text(_statusLabel,
                        style: TextStyle(fontSize: 11, color: palette.accent)),
                  ),
                ),
              ]),
              const SizedBox(height: 15),
              Text(subgroup.title, style: const TextStyle(
                  fontSize: 24, height: 1.4, letterSpacing: -.8,
                  fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 10),
              Text(subgroup.description, style: const TextStyle(
                  fontSize: 13, height: 1.8, color: teamixActionForeground)),
              const SizedBox(height: 22),
              Material(
                color: palette.background,
                borderRadius: BorderRadius.circular(21),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(19),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _info('신청 인원',
                          '${subgroup.applicationCount} / ${subgroup.recruitmentCapacity}명')),
                      Expanded(child: _info('팀 구성', teamLabel)),
                    ]),
                    const SizedBox(height: 22),
                    _info('신청 마감', '${deadline.month}월 ${deadline.day}일 · $time'),
                  ]),
                ),
              ),
              ?myTeam,
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
                        Row(children: [
                          const Expanded(child: Text('운영진 관리',
                              style: TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: teamixPurpleAccent))),
                          Text(_statusLabel, style: const TextStyle(
                              fontSize: 12, color: teamixPurpleAccent)),
                        ]),
                        const SizedBox(height: 10),
                        const Text('신청 현황을 확인하고 모집 마감 후 팀을 편성해요.',
                            style: TextStyle(fontSize: 12, height: 1.8,
                                color: teamixActionForeground)),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton(
                            onPressed: () => _pending(context, '신청 현황'),
                            child: Text('신청 현황 · ${subgroup.applicationCount}명'),
                          ),
                          OutlinedButton(
                            onPressed: onManageFormation ??
                                () => Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const MatchingSettingsScreen(),
                                      ),
                                    ),
                            child: const Text('팀 편성 관리 →'),
                          ),
                        ]),
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (registration == null)
                  _applyButton(
                    '참가 신청하기',
                    () => _pending(context, '참가 신청'),
                  )
                else
                  StreamBuilder<Registration?>(
                    stream: registration,
                    builder: (context, snapshot) {
                      final current = snapshot.data;
                      final submitted = current?.submitted ?? false;
                      return _applyButton(
                        onApply == null
                            ? (submitted ? '신청 완료 · 모집 마감' : '모집이 마감됐어요')
                            : submitted
                            ? '신청 완료 · 응답 수정하기'
                            : '참가 신청하기',
                        onApply == null ? null : () => onApply!(current),
                      );
                    },
                  ),
                const SizedBox(height: 9),
                Text(
                  isOperator
                      ? '운영진도 신청하면 팀 편성에 참여할 수 있어요.'
                      : '설문을 제출하면 참가 신청이 완료돼요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: teamixMuted),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
