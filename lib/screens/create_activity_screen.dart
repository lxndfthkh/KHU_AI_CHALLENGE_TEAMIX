import 'package:flutter/material.dart';

import '../data/firestore_activities_source.dart';
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

class _TraitItemDraft {
  _TraitItemDraft(String text, {this.reverse = false})
    : text = TextEditingController(text: text);

  final TextEditingController text;
  bool reverse;
}

/// One personality axis on the form (matching.traits).
class _TraitAxisDraft {
  _TraitAxisDraft(this.id, String label, List<_TraitItemDraft> items)
    : label = TextEditingController(text: label),
      items = [...items];

  final String id;
  final TextEditingController label;
  final List<_TraitItemDraft> items;

  void dispose() {
    label.dispose();
    for (final i in items) {
      i.text.dispose();
    }
  }
}

const maxTraitAxes = 4;
const maxTraitItems = 3;

/// Starting template: three work-style axes, two items each, one reversed.
List<_TraitAxisDraft> _traitTemplate() => [
  _TraitAxisDraft('ext', '외향성', [
    _TraitItemDraft('새로운 사람과 금방 친해지는 편이다'),
    _TraitItemDraft('여럿보다 혼자 작업하는 게 편하다', reverse: true),
  ]),
  _TraitAxisDraft('lead', '주도성', [
    _TraitItemDraft('모임에서 먼저 방향을 제안하는 편이다'),
    _TraitItemDraft('정해진 역할을 따르는 게 편하다', reverse: true),
  ]),
  _TraitAxisDraft('plan', '계획성', [
    _TraitItemDraft('마감보다 미리 끝내두는 편이다'),
    _TraitItemDraft('계획 없이 바로 시작하는 편이다', reverse: true),
  ]),
];

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
  String? _type;
  bool _commonTime = false;
  bool _busy = false;
  bool _traitsOn = true;
  final List<_TraitAxisDraft> _axes = _traitTemplate();
  int _axisSerial = 0;

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
    for (final a in _axes) {
      a.dispose();
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
    final type = _type;
    if (type == null) {
      _toast('소모임 유형을 골라 주세요.');
      return null;
    }
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
    final traits = <TraitAxis>[];
    if (_traitsOn) {
      if (_axes.isEmpty || _axes.length > maxTraitAxes) {
        _toast('성향 축은 1~$maxTraitAxes개로 정해 주세요.');
        return null;
      }
      for (var a = 0; a < _axes.length; a++) {
        final axis = _axes[a];
        final label = axis.label.text.trim();
        if (label.isEmpty || label.length > 30) {
          _toast('성향 축 이름을 1~30자로 입력해 주세요.');
          return null;
        }
        if (axis.items.isEmpty || axis.items.length > maxTraitItems) {
          _toast('$label 축에는 문항을 1~$maxTraitItems개 넣어 주세요.');
          return null;
        }
        final items = <(String, bool)>[];
        for (var i = 0; i < axis.items.length; i++) {
          final text = axis.items[i].text.text.trim();
          if (text.isEmpty || text.length > 120) {
            _toast('$label 축의 문항을 1~120자로 입력해 주세요.');
            return null;
          }
          final id = 'tr${a + 1}${i + 1}';
          questions.add(ActivityQuestion(id: id, label: text, type: 'scale'));
          items.add((id, axis.items[i].reverse));
        }
        traits.add(TraitAxis(id: axis.id, label: label, items: items));
      }
    }
    if (criteria.isEmpty && traits.isEmpty) {
      _toast('편성에 쓸 질문을 하나 이상 골라 주세요.');
      return null;
    }
    final commonTime = _commonTime && criteria.containsKey('time');
    return NewActivity(
      title: title,
      type: type,
      description: _description.text,
      capacity: capacity,
      targetTeamSize: teamSize,
      deadline: _deadline,
      questions: questions,
      criteria: criteria,
      method: _method,
      requireCommonTime: commonTime,
      traits: traits,
    );
  }

  void _addAxis() => setState(() {
    _axisSerial++;
    var id = 'ax$_axisSerial';
    while (_axes.any((a) => a.id == id)) {
      _axisSerial++;
      id = 'ax$_axisSerial';
    }
    _axes.add(_TraitAxisDraft(id, '', [_TraitItemDraft('')]));
  });

  // Controllers are disposed after the frame that drops their fields, so the
  // old TextFields never touch a disposed controller while rebuilding.
  void _later(VoidCallback dispose) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => dispose());

  void _removeAxis(_TraitAxisDraft axis) {
    setState(() => _axes.remove(axis));
    _later(axis.dispose);
  }

  void _removeItem(_TraitAxisDraft axis, _TraitItemDraft item) {
    setState(() => axis.items.remove(item));
    _later(item.text.dispose);
  }

  void _resetTraits() {
    final old = [..._axes];
    setState(() {
      _axes
        ..clear()
        ..addAll(_traitTemplate());
    });
    _later(() {
      for (final a in old) {
        a.dispose();
      }
    });
  }

  Widget _axisEditor(int index, _TraitAxisDraft axis) => Padding(
    key: ObjectKey(axis),
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: teamixBackground,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('trait-label-${axis.id}'),
                    controller: axis.label,
                    decoration: InputDecoration(
                      labelText: '성향 축 ${index + 1}',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '축 삭제',
                  onPressed: () => _removeAxis(axis),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            for (final item in axis.items)
              Padding(
                key: ObjectKey(item),
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: item.text,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: '문항 (1 전혀 아니다 ~ 5 매우 그렇다)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('반대 문항'),
                      tooltip: '그렇다고 답할수록 이 성향이 낮은 문항',
                      selected: item.reverse,
                      onSelected: (v) => setState(() => item.reverse = v),
                    ),
                    IconButton(
                      tooltip: '문항 삭제',
                      onPressed: axis.items.length > 1
                          ? () => _removeItem(axis, item)
                          : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            if (axis.items.length < maxTraitItems)
              TextButton.icon(
                onPressed: () =>
                    setState(() => axis.items.add(_TraitItemDraft(''))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('문항 추가'),
              ),
          ],
        ),
      ),
    ),
  );

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
              const Text('유형 *', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final MapEntry(key: key, value: label)
                      in activityTypeLabels.entries)
                    ChoiceChip(
                      label: Text(label),
                      selected: _type == key,
                      onSelected: (_) => setState(() => _type = key),
                    ),
                ],
              ),
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
            _section('성향 분석 · AI가 팀마다 성향을 맞춰요', [
              SwitchListTile(
                key: const ValueKey('traits-switch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _traitsOn,
                title: const Text('성향 문항으로 팀 균형 맞추기'),
                subtitle: const Text(
                  '참가자가 1~5점으로 답하고, 축마다 점수를 모아 팀끼리 비교해요.',
                ),
                onChanged: (v) => setState(() => _traitsOn = v),
              ),
              if (_traitsOn) ...[
                for (var i = 0; i < _axes.length; i++)
                  _axisEditor(i, _axes[i]),
                Row(
                  children: [
                    if (_axes.length < maxTraitAxes)
                      TextButton.icon(
                        onPressed: _addAxis,
                        icon: const Icon(Icons.add),
                        label: const Text('성향 축 추가'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: _resetTraits,
                      child: const Text('기본 문항으로'),
                    ),
                  ],
                ),
                const Text(
                  '반대 문항은 점수를 뒤집어 계산해요(5점 → 1점). '
                  '편성 결과에는 팀 평균만 보여요.',
                  style: TextStyle(fontSize: 11, color: teamixMuted),
                ),
              ],
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
