import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firestore_activities_source.dart';
import '../models/activity.dart';
import '../models/formation.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// Operator matching settings before publishing (팀편성흐름 v4 ①):
/// team count, priority order, method, common time, a required role per
/// team and whether learned correction applies. Questions themselves are
/// fixed when the subgroup is created.
class FormationSettingsScreen extends StatefulWidget {
  const FormationSettingsScreen({
    super.key,
    required this.activity,
    required this.settings,
    required this.learning,
    required this.onSave,
    this.questions = const [],
    this.palette = GroupCardPalette.defaultJoined,
  });

  final ActivityRecord activity;
  final Stream<FormationSettings?> settings;

  /// (applied, criterion -> up/down/same) from the formation server.
  final Future<(bool, Map<String, String>)> learning;
  final Future<FormationOutcome> Function(FormationSettingsPatch patch) onSave;

  /// For the role options of a required-role rule.
  final List<ActivityQuestion> questions;
  final GroupCardPalette palette;

  @override
  State<FormationSettingsScreen> createState() =>
      _FormationSettingsScreenState();
}

class _FormationSettingsScreenState extends State<FormationSettingsScreen> {
  late final StreamSubscription<FormationSettings?> _sub;
  bool _loaded = false, _busy = false;
  int _teams = 1;
  List<String> _priority = const [];
  String _method = 'balanced';
  bool _commonTime = false, _learningOn = true;
  String? _roleOption;
  int _roleMinimum = 1;
  Map<String, String> _directions = const {};

  List<QuestionOption> get _roleOptions => [
    for (final q in widget.questions)
      if (q.id == 'role' || q.label.contains('역할')) ...q.options,
  ];

  @override
  void initState() {
    super.initState();
    _sub = widget.settings.listen((s) {
      if (s == null || _loaded || !mounted) return;
      final a = widget.activity;
      final people = a.participantCount > 0 ? a.participantCount : a.capacity;
      setState(() {
        _loaded = true;
        _teams = s.teamIds.isNotEmpty
            ? s.teamIds.length
            : (people / a.targetTeamSize).ceil().clamp(1, 100);
        _priority = s.priority.isNotEmpty
            ? [...s.priority]
            : [...s.questionCriteria.values, 'size'];
        _method = s.method;
        _commonTime = s.requireCommonTime;
        _learningOn = s.learningEnabled;
        if (s.requiredRoles.isNotEmpty) {
          _roleOption = s.requiredRoles.first.$2;
          _roleMinimum = s.requiredRoles.first.$3;
        }
      });
    });
    widget.learning.then((l) {
      if (mounted) setState(() => _directions = l.$2);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _move(int i, int delta) => setState(() {
    final list = [..._priority];
    final item = list.removeAt(i);
    list.insert(i + delta, item);
    _priority = list;
  });

  Future<void> _save() async {
    setState(() => _busy = true);
    final outcome = await widget.onSave(
      FormationSettingsPatch(
        teamCount: _teams,
        participants: widget.activity.participantCount,
        priority: _priority,
        method: _method,
        requireCommonTime: _commonTime && _priority.contains('time'),
        learningEnabled: _learningOn,
        requiredRole: _roleOption == null ? null : (_roleOption!, _roleMinimum),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(outcome.message)));
    if (outcome.ok) Navigator.pop(context);
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: widget.palette.background,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _direction(String key) {
    final d = _learningOn ? _directions[key] : null;
    return switch (d) {
      'up' => const Text(
        '학습 ↑',
        style: TextStyle(fontSize: 11, color: Color(0xFF0F6E56)),
      ),
      'down' => const Text(
        '학습 ↓',
        style: TextStyle(fontSize: 11, color: Color(0xFF993C1D)),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final perTeam = a.participantCount <= 0
        ? null
        : (a.participantCount / _teams).ceil();
    return Scaffold(
      backgroundColor: teamixBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '돌아가기',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 28),
        ),
        centerTitle: true,
        title: const Text(
          '편성 설정',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _section('팀 수', [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '팀 줄이기',
                            onPressed: _teams > 1
                                ? () => setState(() => _teams--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_teams팀',
                            key: const ValueKey('team-count'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          IconButton(
                            tooltip: '팀 늘리기',
                            onPressed: _teams < 100
                                ? () => setState(() => _teams++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      Text(
                        perTeam == null
                            ? '정원은 신청 인원에 맞춰 팀마다 똑같이 나눠요.'
                            : '신청 ${a.participantCount}명 · 팀당 최대 $perTeam명',
                        style: const TextStyle(
                          fontSize: 11,
                          color: teamixMuted,
                        ),
                      ),
                    ]),
                    _section('우선순위 · 위에 있을수록 중요해요', [
                      for (var i = 0; i < _priority.length; i++)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${i + 1}  ${criterionLabels[_priority[i]] ?? _priority[i]}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            _direction(_priority[i]),
                            IconButton(
                              tooltip: '위로',
                              visualDensity: VisualDensity.compact,
                              onPressed: i == 0 ? null : () => _move(i, -1),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: '아래로',
                              visualDensity: VisualDensity.compact,
                              onPressed: i == _priority.length - 1
                                  ? null
                                  : () => _move(i, 1),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ],
                        ),
                    ]),
                    _section('편성 방식', [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'balanced',
                            label: Text('골고루 섞기'),
                          ),
                          ButtonSegment(
                            value: 'similar',
                            label: Text('비슷하게 모으기'),
                          ),
                        ],
                        selected: {_method},
                        onSelectionChanged: (v) =>
                            setState(() => _method = v.first),
                      ),
                    ]),
                    _section('필수 조건', [
                      if (_priority.contains('time'))
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _commonTime,
                          onChanged: (v) => setState(() => _commonTime = v),
                          title: const Text('팀마다 모두 가능한 시간이 있어야 해요'),
                        ),
                      if (_roleOptions.isNotEmpty) ...[
                        const Text(
                          '팀마다 꼭 있어야 하는 역할',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            ChoiceChip(
                              label: const Text('없음'),
                              selected: _roleOption == null,
                              onSelected: (_) =>
                                  setState(() => _roleOption = null),
                            ),
                            for (final o in _roleOptions)
                              ChoiceChip(
                                label: Text(o.label),
                                selected: _roleOption == o.id,
                                onSelected: (_) =>
                                    setState(() => _roleOption = o.id),
                              ),
                          ],
                        ),
                        if (_roleOption != null)
                          Row(
                            children: [
                              const Text('최소', style: TextStyle(fontSize: 12)),
                              IconButton(
                                tooltip: '줄이기',
                                onPressed: _roleMinimum > 1
                                    ? () => setState(() => _roleMinimum--)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text('$_roleMinimum명'),
                              IconButton(
                                tooltip: '늘리기',
                                onPressed: () => setState(() => _roleMinimum++),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                      ],
                    ]),
                    _section('학습 결과 반영', [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _learningOn,
                        onChanged: (v) => setState(() => _learningOn = v),
                        title: const Text('지난 후기로 기준 가중치를 보정해요'),
                      ),
                      const Text(
                        '↑↓는 지난 후기에서 만족도와 관련이 컸던 기준이에요. '
                        '보정해도 위에서 정한 우선순위 순서는 바뀌지 않아요.',
                        style: TextStyle(fontSize: 11, color: teamixMuted),
                      ),
                    ]),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? '저장하는 중…' : '설정 저장'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '팀을 공개한 뒤에는 설정을 바꿀 수 없어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: teamixMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
