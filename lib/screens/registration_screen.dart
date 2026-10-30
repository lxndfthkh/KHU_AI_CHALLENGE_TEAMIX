import 'package:flutter/material.dart';

import '../data/firestore_activities_source.dart';
import '../models/activity.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// Survey for submitRegistration: one answer per question, keyed by its ID
/// (option ID, list of option IDs, or 1-5). Prefilled when editing.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.activity,
    required this.questions,
    required this.onSubmit,
    this.initialAnswers = const {},
    this.palette = GroupCardPalette.defaultJoined,
  });

  final ActivityRecord activity;
  final List<ActivityQuestion> questions;
  final Future<void> Function(Map<String, Object> answers) onSubmit;
  final Map<String, Object?> initialAnswers;
  final GroupCardPalette palette;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _single = <String, String>{};
  final _multiple = <String, Set<String>>{};
  final _scale = <String, int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final q in widget.questions) {
      final v = widget.initialAnswers[q.id];
      if (q.type == 'single' && v is String) _single[q.id] = v;
      if (q.type == 'multiple' && v is List) {
        _multiple[q.id] = {for (final x in v) x.toString()};
      }
      if (q.type == 'scale' && v is num) _scale[q.id] = v.toInt();
    }
  }

  Object? _answer(ActivityQuestion q) => switch (q.type) {
    'single' => _single[q.id],
    'multiple' =>
      (_multiple[q.id]?.isEmpty ?? true)
          ? null
          // Keep the questions' option order, not tap order.
          : [
              for (final o in q.options)
                if (_multiple[q.id]!.contains(o.id)) o.id,
            ],
    _ => _scale[q.id],
  };

  Future<void> _submit() async {
    final answers = <String, Object>{};
    for (final q in widget.questions) {
      final a = _answer(q);
      if (a == null) {
        if (q.required) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('"${q.label}"에 답해 주세요.')));
          return;
        }
        continue;
      }
      answers[q.id] = a;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSubmit(answers);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('참가 신청을 완료했어요.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('신청하지 못했어요. 마감됐거나 정원이 찼을 수 있어요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _question(ActivityQuestion q) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: widget.palette.background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.required ? '${q.label} *' : q.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        if (q.type == 'multiple')
          const Text(
            '여러 개 고를 수 있어요',
            style: TextStyle(fontSize: 11, color: teamixMuted),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: switch (q.type) {
            'single' => [
              for (final o in q.options)
                ChoiceChip(
                  label: Text(o.label),
                  selected: _single[q.id] == o.id,
                  onSelected: (_) => setState(() => _single[q.id] = o.id),
                ),
            ],
            'multiple' => [
              for (final o in q.options)
                FilterChip(
                  label: Text(o.label),
                  selected: _multiple[q.id]?.contains(o.id) ?? false,
                  onSelected: (on) => setState(() {
                    final set = _multiple.putIfAbsent(q.id, () => <String>{});
                    on ? set.add(o.id) : set.remove(o.id);
                  }),
                ),
            ],
            _ => [
              for (var v = 1; v <= 5; v++)
                ChoiceChip(
                  label: Text('$v'),
                  selected: _scale[q.id] == v,
                  onSelected: (_) => setState(() => _scale[q.id] = v),
                ),
            ],
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '소모임으로 돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      centerTitle: true,
      title: const Text(
        '참가 신청',
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
              widget.activity.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '응답은 팀 편성에만 쓰이고 다른 참가자에게 공개되지 않아요.',
              style: TextStyle(fontSize: 12, color: teamixMuted),
            ),
            const SizedBox(height: 16),
            for (final q in widget.questions) _question(q),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '보내는 중…' : '신청하기'),
            ),
          ],
        ),
      ),
    ),
  );
}
