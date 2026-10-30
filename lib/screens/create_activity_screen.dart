import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// One matching criterion offered on the form, in priority order.
class _CriterionDraft {
  _CriterionDraft(this.key, this.label, this.type, List<String> options)
    : options = TextEditingController(text: options.join(', '));

  final String key;
  final String label;
  final String type;
  final TextEditingController options;
  bool enabled = true;
}

/// Operator form for createActivity (v7 소모임 창설). Questions picked here are
/// locked after the first registration, so the screen says so up front.
class CreateActivityScreen extends StatefulWidget {
  const CreateActivityScreen({
    super.key,
    required this.groupName,
    required this.onCreate,
    this.palette = GroupCardPalette.defaultJoined,
    this.now,
  });

  final String groupName;
  final Future<void> Function(NewActivity activity) onCreate;
  final GroupCardPalette palette;

  /// Injectable clock for tests.
  final DateTime Function()? now;

  @override
  State<CreateActivityScreen> createState() => _CreateActivityScreenState();
}

class _CreateActivityScreenState extends State<CreateActivityScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _capacity = TextEditingController(text: '20');
  final _teamSize = TextEditingController(text: '4');
  late DateTime _deadline;
  String _method = 'balanced';
  bool _commonTime = false;
  bool _busy = false;

  final _criteria = [
    _CriterionDraft('role', '희망 역할', 'single', ['기획', '개발', '디자인', '운영']),
    _CriterionDraft('time', '가능 시간', 'multiple', [
      '평일 낮',
      '평일 저녁',
      '주말 낮',
      '주말 저녁',
    ]),
    _CriterionDraft('experience', '경험 수준 (1~5)', 'scale', const []),
    _CriterionDraft('interest', '관심 분야', 'multiple', ['웹', '앱', 'AI', '콘텐츠']),
  ];

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final week = _now.add(const Duration(days: 7));
    _deadline = DateTime(week.year, week.month, week.day, 23, 59);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _capacity, _teamSize]) {
      c.dispose();
    }
    for (final c in _criteria) {
      c.options.dispose();
    }
    super.dispose();
  }

  // Replace, don't queue: each fix should show its own message right away.
  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDeadline() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: _now,
      lastDate: _now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (!mounted) return;
    setState(() {
      _deadline = DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? 23,
        time?.minute ?? 59,
      );
    });
  }

  /// Returns the payload, or null after telling the operator what to fix.
  NewActivity? _build() {
    final title = _title.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    final teamSize = int.tryParse(_teamSize.text.trim());
    if (title.isEmpty || title.length > 120) {
      _toast('소모임 이름을 1~120자로 입력해 주세요.');
      return null;
    }
    if (_description.text.trim().length > 5000) {
      _toast('소개는 5,000자까지 입력할 수 있어요.');
      return null;
    }
    if (capacity == null || capacity < 1 || capacity > 500) {
      _toast('모집 정원은 1~500명으로 입력해 주세요.');
      return null;
    }
    if (teamSize == null ||
        teamSize < 1 ||
        teamSize > 50 ||
        teamSize > capacity) {
      _toast('팀당 인원은 1~50명, 모집 정원 이하로 입력해 주세요.');
      return null;
    }
    if (!_deadline.isAfter(_now)) {
      _toast('신청 마감은 지금 이후로 정해 주세요.');
      return null;
    }
    final questions = <ActivityQuestion>[];
    final criteria = <String, String>{};
    for (final c in _criteria.where((c) => c.enabled)) {
      final labels = [
        for (final o in c.options.text.split(','))
          if (o.trim().isNotEmpty) o.trim(),
      ];
      if (c.type != 'scale') {
        if (labels.isEmpty || labels.length > 30) {
          _toast('${c.label} 선택지는 쉼표로 구분해 1~30개 입력해 주세요.');
          return null;
        }
        if (labels.any((l) => l.length > 60) ||
            labels.toSet().length != labels.length) {
          _toast('${c.label} 선택지는 60자 이하, 중복 없이 입력해 주세요.');
          return null;
        }
      }
      questions.add(
        ActivityQuestion(
          id: c.key,
          label: c.label.replaceAll(' (1~5)', ''),
          type: c.type,
          options: [
            for (var i = 0; i < labels.length; i++)
              QuestionOption('o${i + 1}', labels[i]),
          ],
        ),
      );
      criteria[c.key] = c.key;
    }
    if (questions.isEmpty) {
      _toast('편성에 쓸 질문을 하나 이상 골라 주세요.');
      return null;
    }
    final commonTime = _commonTime && criteria.containsKey('time');
    return NewActivity(
      title: title,
      description: _description.text,
      capacity: capacity,
      targetTeamSize: teamSize,
      deadline: _deadline,
      questions: questions,
      criteria: criteria,
      method: _method,
      requireCommonTime: commonTime,
    );
  }

  Future<void> _submit() async {
    final activity = _build();
    if (activity == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onCreate(activity);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) _toast('소모임을 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Material, not a decorated Container, so the list tiles' ink shows.
  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: widget.palette.background,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: widget.palette.accent,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c, {
    bool number = false,
    int lines = 1,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: key,
      controller: c,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: teamixBackground,
        isDense: true,
      ),
    ),
  );

  String get _deadlineText =>
      '${_deadline.month}월 ${_deadline.day}일 '
      '${_deadline.hour.toString().padLeft(2, '0')}:'
      '${_deadline.minute.toString().padLeft(2, '0')}';

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
        '소모임 창설',
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
              widget.groupName,
              style: const TextStyle(fontSize: 12, color: teamixMuted),
            ),
            const SizedBox(height: 12),
            _section('기본 정보', [
              _field('소모임 이름 *', _title, key: const ValueKey('activity-title')),
              _field('소개', _description, lines: 3),
            ]),
            _section('모집 설정', [
              Row(
                children: [
                  Expanded(
                    child: _field(
                      '모집 정원',
                      _capacity,
                      number: true,
                      key: const ValueKey('activity-capacity'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      '팀당 인원',
                      _teamSize,
                      number: true,
                      key: const ValueKey('activity-team-size'),
                    ),
                  ),
                ],
              ),
              Material(
                color: teamixBackground,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  title: const Text('신청 마감'),
                  trailing: Text(_deadlineText),
                  onTap: _pickDeadline,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '팀 수는 신청을 마감할 때 신청 인원 ÷ 팀당 인원으로 정해져요.',
                style: TextStyle(fontSize: 11, color: teamixMuted),
              ),
            ]),
            _section('편성 질문 · 위에서부터 우선순위', [
              for (final c in _criteria) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: c.enabled,
                  title: Text(c.label),
                  onChanged: (v) => setState(() => c.enabled = v ?? false),
                ),
                if (c.enabled && c.type != 'scale')
                  _field('선택지 (쉼표로 구분)', c.options),
              ],
              const Text(
                '첫 신청이 들어오면 질문은 바꿀 수 없어요.',
                style: TextStyle(fontSize: 11, color: teamixMuted),
              ),
            ]),
            _section('편성 방식', [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'balanced', label: Text('골고루 섞기')),
                  ButtonSegment(value: 'similar', label: Text('비슷하게 모으기')),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _commonTime,
                title: const Text('팀마다 모두 가능한 시간이 꼭 있어야 해요'),
                onChanged: _criteria.firstWhere((c) => c.key == 'time').enabled
                    ? (v) => setState(() => _commonTime = v)
                    : null,
              ),
            ]),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '만드는 중…' : '소모임 만들기'),
            ),
          ],
        ),
      ),
    ),
  );
}
