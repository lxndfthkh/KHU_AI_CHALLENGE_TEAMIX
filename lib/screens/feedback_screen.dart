import 'package:flutter/material.dart';

import '../theme.dart';
import 'group_card_palette.dart';

/// Score keys submitFeedback requires (functions/src/activity.js SCORE_KEYS),
/// with the question shown for each.
const feedbackQuestions = {
  'overall': '전체적으로 만족했나요?',
  'schedule': '일정은 잘 맞았나요?',
  'roles': '역할 분담은 괜찮았나요?',
  'rejoin': '이 팀과 다시 하고 싶나요?',
};

/// Star-rating feedback after an activity ends (four 1-5 scores, no text).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.activityTitle,
    required this.teamName,
    required this.onSubmit,
    this.initialScores,
    this.initialConsent = false,
    this.palette = GroupCardPalette.defaultJoined,
  });

  final String activityTitle;
  final String teamName;

  /// scores and the learning-consent choice.
  final Future<void> Function(Map<String, int> scores, bool consent) onSubmit;

  /// Previous answers when editing before feedback closes.
  final Map<String, int>? initialScores;
  final bool initialConsent;
  final GroupCardPalette palette;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final Map<String, int> _scores = {...?widget.initialScores};
  late bool _consent = widget.initialConsent;
  bool _busy = false;

  Future<void> _submit() async {
    final missing = feedbackQuestions.keys.where((k) => _scores[k] == null);
    final messenger = ScaffoldMessenger.of(context);
    if (missing.isNotEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${feedbackQuestions[missing.first]}"에 별점을 주세요.'),
          ),
        );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(Map.of(_scores), _consent);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('후기를 보냈어요. 고마워요.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('후기를 보내지 못했어요. 후기 기간이 끝났을 수 있어요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stars(String key) => Row(
    children: [
      for (var v = 1; v <= 5; v++)
        IconButton(
          key: ValueKey('star-$key-$v'),
          tooltip: '$v점',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _scores[key] = v),
          icon: Icon(
            v <= (_scores[key] ?? 0)
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            color: const Color(0xFFBA7517),
            size: 30,
          ),
        ),
    ],
  );

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
        '후기',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              '${widget.teamName} 후기',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(
              widget.activityTitle,
              style: const TextStyle(fontSize: 12, color: teamixMuted),
            ),
            const SizedBox(height: 16),
            Material(
              color: widget.palette.background,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final MapEntry(key: key, value: question)
                        in feedbackQuestions.entries) ...[
                      Text(
                        question,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      _stars(key),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              key: const ValueKey('learning-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text(
                '더 나은 팀 편성을 위해 학습에 활용해도 좋아요 (선택)',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '이름과 응답 내용은 빠지고 팀 단위 점수만 쓰여요. 계정 정보에서 바꿀 수 있어요.',
                style: TextStyle(fontSize: 11),
              ),
            ),
            const Text(
              '개별 점수는 운영진도 볼 수 없어요. 3명 이상 응답한 팀의 평균만 공유돼요.',
              style: TextStyle(fontSize: 11, color: teamixMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '보내는 중…' : '후기 보내기'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// v7-style request shown once after an activity ends. True = write now.
Future<bool> showFeedbackRequestSheet(
  BuildContext context, {
  required String activityTitle,
  required int? daysLeft,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: teamixBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$activityTitle이(가) 끝났어요',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '팀 활동은 어땠나요? 별점 4번이면 끝나요.',
                style: TextStyle(fontSize: 13, color: teamixMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Text('후기 남기기'),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheet, false),
                child: const Text('나중에'),
              ),
              const SizedBox(height: 6),
              Text(
                daysLeft == null
                    ? '소모임 상세에서 언제든 쓸 수 있어요.'
                    : '소모임 상세에서 언제든 쓸 수 있어요 · D-$daysLeft',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: teamixMuted),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
