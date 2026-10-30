import 'package:flutter/material.dart';

import '../data/activity_backend.dart';
import '../data/firestore_activities_source.dart';
import '../theme.dart';
import 'feedback_screen.dart';
import 'formation_screen.dart' show teamLabel;
import 'group_card_palette.dart';

/// Opens the star-rating form for the caller's team, prefilled when editing.
Future<void> openFeedback(
  BuildContext context,
  ActivityBackend backend,
  String groupId,
  ActivityRecord activity,
  GroupCardPalette palette,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final team = await backend.myTeam(groupId, activity.id).first;
  if (team == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('팀에 배정된 참가자만 후기를 쓸 수 있어요.')),
    );
    return;
  }
  final previous = await backend.myFeedback(groupId, activity.id).first;
  final consent = await backend.learningConsent().first.catchError(
    (_) => false,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => FeedbackScreen(
        activityTitle: activity.title,
        teamName: teamLabel(team.teamId),
        initialScores: previous,
        initialConsent: consent,
        palette: palette,
        onSubmit: (scores, agreed) async {
          // Consent is copied onto feedback at write time, so set it first.
          if (agreed != consent) await backend.setLearningConsent(agreed);
          await backend.submitFeedback(activity.id, scores);
        },
      ),
    ),
  );
}

/// Activities already offered the one-time request in this app session.
final _prompted = <String>{};

/// Shows the feedback request sheet once per activity when the caller was on
/// a team of an ended activity and hasn't written feedback yet.
Future<void> maybePromptFeedback(
  BuildContext context,
  ActivityBackend backend,
  String groupId,
  ActivityRecord activity,
  GroupCardPalette palette,
) async {
  if (!activity.feedbackOpen || !_prompted.add(activity.id)) return;
  try {
    final team = await backend.myTeam(groupId, activity.id).first;
    if (team == null) return;
    final done = await backend.myFeedback(groupId, activity.id).first;
    if (done != null || !context.mounted) return;
  } catch (_) {
    return;
  }
  final write = await showFeedbackRequestSheet(
    context,
    activityTitle: activity.title,
    daysLeft: activity.feedbackDaysLeft(DateTime.now()),
  );
  if (write && context.mounted) {
    await openFeedback(context, backend, groupId, activity, palette);
  }
}

/// Participant entry point on the subgroup detail once the activity ended.
class FeedbackAction extends StatefulWidget {
  const FeedbackAction({
    super.key,
    required this.backend,
    required this.groupId,
    required this.activity,
    required this.palette,
  });

  final ActivityBackend backend;
  final String groupId;
  final ActivityRecord activity;
  final GroupCardPalette palette;

  @override
  State<FeedbackAction> createState() => _FeedbackActionState();
}

class _FeedbackActionState extends State<FeedbackAction> {
  late final Stream<Map<String, int>?> _mine = widget.backend.myFeedback(
    widget.groupId,
    widget.activity.id,
  );

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    if (a.status != 'ended') return const SizedBox.shrink();
    return StreamBuilder<Map<String, int>?>(
      stream: _mine,
      builder: (context, snapshot) {
        final written = snapshot.data != null;
        final days = a.feedbackDaysLeft(DateTime.now());
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: a.feedbackOpen
              ? OutlinedButton.icon(
                  key: const ValueKey('feedback-action'),
                  onPressed: () => openFeedback(
                    context,
                    widget.backend,
                    widget.groupId,
                    a,
                    widget.palette,
                  ),
                  icon: const Icon(Icons.star_border_rounded),
                  label: Text(
                    written
                        ? '후기 수정하기'
                        : days == null
                        ? '후기 남기기'
                        : '후기 남기기 · D-$days',
                  ),
                )
              : Text(
                  written ? '후기를 보냈어요. 마감됐어요.' : '후기가 마감됐어요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: teamixMuted),
                ),
        );
      },
    );
  }
}

/// Operator panel: 모집 → 편성 → 활동 → 후기, one action per stage.
class ActivityLifecyclePanel extends StatefulWidget {
  const ActivityLifecyclePanel({
    super.key,
    required this.backend,
    required this.activity,
    required this.palette,
  });

  final ActivityBackend backend;
  final ActivityRecord activity;
  final GroupCardPalette palette;

  @override
  State<ActivityLifecyclePanel> createState() => _ActivityLifecyclePanelState();
}

class _ActivityLifecyclePanelState extends State<ActivityLifecyclePanel> {
  bool _busy = false;

  static const _stages = ['모집', '편성', '활동', '후기'];

  int get _stage => switch (widget.activity.status) {
    'recruiting' => 0,
    'closed' => 1,
    'active' => 2,
    _ => 3,
  };

  Future<void> _run(
    String confirm,
    String body,
    Future<void> Function() action,
    String done,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(confirm),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('처리하지 못했어요. 상태를 확인해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final Widget? action = switch (a.status) {
      'closed' when a.published => FilledButton(
        onPressed: _busy
            ? null
            : () => _run(
                '활동을 시작할까요?',
                '공개된 팀으로 활동을 시작해요. 시작 후에는 팀을 다시 편성하지 않는 게 좋아요.',
                () => widget.backend.startActivity(a.id),
                '활동을 시작했어요.',
              ),
        child: const Text('활동 시작하기'),
      ),
      'active' => FilledButton(
        onPressed: _busy
            ? null
            : () => _run(
                '활동을 종료할까요?',
                '종료하면 팀원들에게 후기 요청이 가고, 7일 뒤 후기가 자동으로 마감돼요.',
                () => widget.backend.endActivity(a.id),
                '활동을 종료했어요. 후기를 받기 시작해요.',
              ),
        child: const Text('활동 종료하기'),
      ),
      'ended' when a.feedbackOpen => OutlinedButton(
        onPressed: _busy
            ? null
            : () => _run(
                '후기를 마감할까요?',
                '마감하면 더 이상 후기를 받지 않아요. 마감하지 않아도 종료 7일 뒤 자동으로 마감돼요.',
                () => widget.backend.closeFeedback(a.id),
                '후기를 마감했어요.',
              ),
        child: const Text('후기 마감하기'),
      ),
      _ => null,
    };
    final note = switch (a.status) {
      'recruiting' => '신청을 받고 있어요. 팀 편성 관리에서 마감할 수 있어요.',
      'closed' when !a.published => '팀을 편성하고 공개하면 활동을 시작할 수 있어요.',
      'closed' => '팀이 공개됐어요. 활동을 시작해 주세요.',
      'active' => '활동 중이에요. 끝나면 종료해서 후기를 받아요.',
      _ => a.feedbackOpen ? '후기를 받는 중이에요.' : '후기가 마감됐어요.',
    };
    return Container(
      key: const ValueKey('activity-lifecycle'),
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lilac,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '활동 단계',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: teamixPurpleAccent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < _stages.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: i == _stage
                          ? teamixPurpleAccent
                          : teamixBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _stages[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: i == _stage
                            ? teamixBackground
                            : teamixPurpleAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(
              fontSize: 12,
              color: teamixRequestForeground,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }
}
