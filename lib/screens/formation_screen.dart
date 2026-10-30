import 'dart:async';

import 'package:flutter/material.dart';

import '../data/formation_backend.dart';
import '../data/firestore_activities_source.dart';
import '../models/activity.dart';
import '../models/formation.dart';
import '../theme.dart';
import 'formation_settings_screen.dart';
import 'group_card_palette.dart';

/// `team_3` -> `3팀`.
String teamLabel(String teamId) {
  final n = RegExp(r'(\d+)$').firstMatch(teamId)?.group(1);
  return n == null ? teamId : '$n팀';
}

/// Operator team formation for one activity (팀편성흐름 v4 ①~④):
/// 신청 마감 → AI 편성 → 이동·검토 → 공개. The server re-checks every step.
class FormationScreen extends StatefulWidget {
  const FormationScreen({
    super.key,
    required this.groupId,
    required this.activity,
    required this.backend,
    this.questions = const [],
    this.palette = GroupCardPalette.defaultJoined,
  });

  final String groupId;
  final Stream<ActivityRecord?> activity;
  final FormationBackend backend;

  /// Used to turn option IDs in team summaries into labels.
  final List<ActivityQuestion> questions;
  final GroupCardPalette palette;

  @override
  State<FormationScreen> createState() => _FormationScreenState();
}

class _FormationScreenState extends State<FormationScreen> {
  late final Stream<FormationDraft?> _draft;
  late final StreamSubscription<ActivityRecord?> _activitySub;
  ActivityRecord? _activity;
  Map<String, String> _names = const {};
  List<String> _precheck = const [];
  bool _busy = false;

  /// Teams picked for a partial re-formation after publishing.
  final _scope = <String>{};

  late final Map<String, String> _labels = {
    for (final q in widget.questions)
      for (final o in q.options) '${q.id}:${o.id}': o.label,
  };

  @override
  void initState() {
    super.initState();
    _activitySub = widget.activity.listen((a) {
      if (!mounted || a == null) return;
      final first = _activity == null;
      setState(() => _activity = a);
      if (first) {
        _draft = widget.backend.draft(a.id);
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _activitySub.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final a = _activity;
    if (a == null) return;
    try {
      final names = await widget.backend.memberNames(widget.groupId);
      final problems = await widget.backend.precheck(widget.groupId, a.id);
      if (mounted) {
        setState(() {
          _names = names;
          _precheck = problems;
        });
      }
    } catch (_) {
      if (mounted) _toast('편성 서버에 연결하지 못했어요.');
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<FormationOutcome> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(outcome.message);
    await _refresh();
  }

  String _name(String uid) => _names[uid] ?? '참가자';
  String _label(String question, String option) =>
      _labels['$question:$option'] ?? option;

  Future<void> _chooseTeam(FormationDraft draft, String uid) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: teamixBackground,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '${_name(uid)}님을 어느 팀으로 옮길까요?',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final t in draft.teams)
              ListTile(
                title: Text('${teamLabel(t.teamId)} · ${t.members.length}명'),
                enabled: !t.members.contains(uid),
                onTap: () => Navigator.pop(sheet, t.teamId),
              ),
            ListTile(
              title: const Text('미배정으로 빼기'),
              onTap: () => Navigator.pop(sheet, ''),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final a = _activity!;
    await _run(
      () => widget.backend.move(
        widget.groupId,
        a.id,
        uid,
        choice.isEmpty ? null : choice,
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color ?? widget.palette.background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );

  Widget _step(String title, String body, {Widget? action}) => _card(
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
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(fontSize: 12, height: 1.6)),
        if (action != null) ...[const SizedBox(height: 10), action],
      ],
    ),
  );

  Widget _problems(String title, List<String> items) => _card(
    color: teamixAddBackground,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: teamixAddForeground,
          ),
        ),
        for (final p in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('· $p', style: const TextStyle(fontSize: 12)),
          ),
      ],
    ),
  );

  void _openSettings(ActivityRecord a) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FormationSettingsScreen(
              activity: a,
              settings: widget.backend.settings(a.id),
              learning: widget.backend.learning(widget.groupId, a.id),
              questions: widget.questions,
              palette: widget.palette,
              onSave: (patch) =>
                  widget.backend.saveSettings(widget.groupId, a.id, patch),
            ),
          ),
        )
        .then((_) => _refresh());
  }

  Widget _team(
    FormationDraft draft,
    TeamDraft team, {
    bool selectable = false,
  }) {
    final s = team.summary;
    final facts = [
      if (s.commonTimes.isNotEmpty)
        '공통 시간 ${s.commonTimes.map((t) => _label('time', t)).join(', ')}',
      if (s.roleCounts.values.any((n) => n > 0))
        '역할 ${[for (final e in s.roleCounts.entries)
          if (e.value > 0) '${_label('role', e.key)} ${e.value}'].join(' · ')}',
      if (s.experienceMean != null)
        '경험 평균 ${s.experienceMean!.toStringAsFixed(1)}',
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${teamLabel(team.teamId)} · ${team.members.length}명',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              if (selectable)
                FilterChip(
                  key: ValueKey('scope-${team.teamId}'),
                  label: Text(_scope.contains(team.teamId) ? '선택됨' : '선택'),
                  selected: _scope.contains(team.teamId),
                  onSelected: (on) => setState(
                    () => on
                        ? _scope.add(team.teamId)
                        : _scope.remove(team.teamId),
                  ),
                ),
            ],
          ),
          for (final f in facts)
            Text(
              f,
              style: TextStyle(fontSize: 11, color: widget.palette.accent),
            ),
          const SizedBox(height: 6),
          if (team.members.isEmpty)
            const Text(
              '아직 팀원이 없어요.',
              style: TextStyle(fontSize: 12, color: teamixMuted),
            ),
          for (final uid in team.members) _memberRow(draft, uid, inTeam: true),
        ],
      ),
    );
  }

  Widget _memberRow(FormationDraft draft, String uid, {bool inTeam = false}) {
    final locked = draft.locked.contains(uid);
    return Row(
      children: [
        if (locked)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.push_pin_outlined, size: 14, color: teamixMuted),
          ),
        Expanded(child: Text(_name(uid), style: const TextStyle(fontSize: 13))),
        // Pinned members keep their team in AI re-formation (v4 ③ 고정/해제).
        if (inTeam)
          TextButton(
            key: ValueKey('lock-$uid'),
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.backend.setLocked(
                      widget.groupId,
                      _activity!.id,
                      uid,
                      locked: !locked,
                    ),
                  ),
            child: Text(locked ? '고정 해제' : '고정'),
          ),
        TextButton(
          onPressed: _busy ? null : () => _chooseTeam(draft, uid),
          child: const Text('옮기기'),
        ),
      ],
    );
  }

  List<Widget> _body(ActivityRecord a, FormationDraft? draft) {
    if (a.recruiting) {
      return [
        _step(
          '1. 신청 마감',
          '지금 ${a.participantCount}명이 신청했어요. 마감하면 더 신청할 수 없고, '
              '팀 수는 신청 인원 ÷ 팀당 ${a.targetTeamSize}명으로 정해져요.',
          action: FilledButton(
            onPressed: _busy || a.participantCount == 0
                ? null
                : () => _run(
                    () => widget.backend.closeRecruitment(widget.groupId, a.id),
                  ),
            child: const Text('신청 마감하고 편성 시작'),
          ),
        ),
      ];
    }
    final hasDraft = draft?.usable ?? false;
    return [
      if (!a.published)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _openSettings(a),
            icon: const Icon(Icons.tune),
            label: const Text('편성 설정 · 팀 수, 우선순위, 필수 조건'),
          ),
        ),
      if (_precheck.isNotEmpty) _problems('편성 전에 확인할 것', _precheck),
      _step(
        a.published ? '다시 편성하기' : '2. AI 편성',
        a.published
            ? '공개된 팀을 최대한 유지하면서 바뀐 신청을 반영해요.'
            : '응답과 우선순위를 바탕으로 추천 편성안을 만들어요. 결과는 바로 공개되지 않아요.',
        action: OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.backend.generate(
                    widget.groupId,
                    a.id,
                    republish: a.published,
                  ),
                ),
          child: Text(
            _busy
                ? '처리 중…'
                : a.published
                ? '기존 팀 유지하며 다시 편성'
                : hasDraft
                ? 'AI로 다시 편성하기'
                : 'AI로 편성하기',
          ),
        ),
      ),
      if (hasDraft) ...[
        if (!draft!.valid && draft.conflicts.isNotEmpty)
          _problems('공개 전에 해결해야 해요', draft.conflicts),
        for (final t in draft.teams) _team(draft, t, selectable: a.published),
        if (a.published) ...[
          OutlinedButton(
            onPressed: _busy || _scope.isEmpty
                ? null
                : () => _run(
                    () => widget.backend.generatePartial(widget.groupId, a.id, [
                      for (final t in draft.teams)
                        if (_scope.contains(t.teamId)) t.teamId,
                    ]),
                  ),
            child: Text(
              _scope.isEmpty
                  ? '다시 편성할 팀을 골라 주세요'
                  : '선택한 팀만 다시 편성 (${_scope.length})',
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (draft.unassigned.isNotEmpty)
          _card(
            color: lilac,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '미배정 · ${draft.unassigned.length}명',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final uid in draft.unassigned) _memberRow(draft, uid),
              ],
            ),
          ),
        FilledButton(
          onPressed: _busy || !draft.valid
              ? null
              : () => _run(() => widget.backend.publish(widget.groupId, a.id)),
          child: Text(a.published ? '바뀐 팀 다시 공개하기' : '팀 공개하기'),
        ),
        const SizedBox(height: 6),
        const Text(
          '공개하면 참가자마다 자기 팀만 보여요. 처음 공개는 전원에게, '
          '다시 공개할 때는 팀이 바뀐 사람에게만 알림이 가요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: teamixMuted),
        ),
        if (a.published)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.backend.discardDraft(widget.groupId, a.id),
                  ),
            child: const Text('수정 초안 버리기 · 공개된 팀은 그대로'),
          ),
      ] else if (a.published)
        _step('공개된 팀', '팀이 공개돼 있어요. 바꾸려면 다시 편성해 주세요.'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = _activity;
    return Scaffold(
      backgroundColor: teamixBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '소모임으로 돌아가기',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 28),
        ),
        centerTitle: true,
        title: const Text(
          '팀 편성',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: StreamBuilder<FormationDraft?>(
                  stream: _draft,
                  builder: (context, snapshot) => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      Text(
                        '${a.title} · ${a.statusLabel}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._body(a, snapshot.data),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
