import 'package:flutter/material.dart';

import '../data/activity_backend.dart';
import '../theme.dart';
import 'feedback_screen.dart';
import 'formation_screen.dart' show teamLabel;
import 'group_card_palette.dart';

const _shortLabels = {
  'overall': '전체',
  'schedule': '일정',
  'roles': '역할',
  'rejoin': '재참여',
};

/// Operator view of team averages; teams under 3 respondents are absent
/// from the summary, so individual ratings can't be inferred.
class FeedbackSummaryScreen extends StatefulWidget {
  const FeedbackSummaryScreen({
    super.key,
    required this.activityTitle,
    required this.summary,
    required this.teamIds,
    this.feedbackOpen = true,
    this.onClose,
    this.palette = GroupCardPalette.defaultJoined,
  });

  final String activityTitle;
  final Stream<FeedbackSummary?> summary;

  /// All teams of the published version, so hidden teams can be named.
  final List<String> teamIds;
  final bool feedbackOpen;

  /// closeFeedback; null when already closed.
  final Future<void> Function()? onClose;
  final GroupCardPalette palette;

  @override
  State<FeedbackSummaryScreen> createState() => _FeedbackSummaryScreenState();
}

class _FeedbackSummaryScreenState extends State<FeedbackSummaryScreen> {
  bool _busy = false;

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('후기를 마감할까요?'),
        content: const Text('마감하면 더 이상 후기를 받지 않고, 모인 후기가 학습 데이터로 정리돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('마감하기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onClose!();
      messenger.showSnackBar(const SnackBar(content: Text('후기를 마감했어요.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('마감하지 못했어요.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      centerTitle: true,
      title: const Text(
        '후기 요약',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<FeedbackSummary?>(
          stream: widget.summary,
          builder: (context, snapshot) {
            final teams = snapshot.data?.teams ?? const {};
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  widget.activityTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                Text(
                  widget.feedbackOpen ? '후기를 받는 중이에요' : '후기가 마감됐어요',
                  style: const TextStyle(fontSize: 12, color: teamixMuted),
                ),
                const SizedBox(height: 14),
                for (final teamId in widget.teamIds)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: teams.containsKey(teamId)
                          ? widget.palette.background
                          : teamixActionBackground,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: teams[teamId] == null
                        ? Text(
                            '${teamLabel(teamId)} · 3명 이상 응답하면 보여요',
                            style: const TextStyle(
                              fontSize: 12,
                              color: teamixMuted,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${teamLabel(teamId)} · 응답 ${teams[teamId]!.$1}명',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final key in feedbackQuestions.keys)
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 52,
                                      child: Text(
                                        _shortLabels[key]!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: widget.palette.accent,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      (teams[teamId]!.$2[key] ?? 0)
                                          .toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                  ),
                const Text(
                  '개별 점수는 보이지 않아요. 3명 미만이 응답한 팀은 평균도 숨겨요.',
                  style: TextStyle(fontSize: 11, color: teamixMuted),
                ),
                if (widget.feedbackOpen && widget.onClose != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy ? null : _close,
                    child: const Text('후기 마감하기'),
                  ),
                  const Text(
                    '마감하지 않아도 종료 7일 뒤 자동으로 마감돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: teamixMuted),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
