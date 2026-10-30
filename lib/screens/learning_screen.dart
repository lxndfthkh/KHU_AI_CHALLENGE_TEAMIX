import 'package:flutter/material.dart';

import '../data/formation_backend.dart';
import '../data/learning_admin.dart';
import '../models/formation.dart';
import '../theme.dart';

const _criteria = {
  'time': '시간',
  'role': '역할',
  'experience': '경험',
  'interest': '관심사',
  'size': '인원',
};

const _statusLabels = {
  'candidate': '검증 통과 · 적용할 수 있어요',
  'not_better_than_baselines': '기존 방식보다 낫지 않아 모델을 저장하지 않았어요',
  'insufficient_data': '데이터가 부족해요 (후기가 충분한 팀 30개, 종료된 소모임 5개 필요)',
  'failed_reformation_check': '재편성 확인에 실패해 모델을 저장하지 않았어요',
};

/// Service admin: train correction factors from closed feedback, then apply
/// them to formation or go back to default weights (every b = 1).
class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key, required this.admin, this.formation});

  final LearningAdmin admin;

  /// Re-forms the chosen subgroup's draft after each demo button so its
  /// teams follow the weights in use; null hides the demo buttons.
  final FormationBackend? formation;

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  LearningStatus? _status;
  String? _error;
  String? _working;
  CompareTarget? _target;
  FormationCompare? _compare;

  @override
  void initState() {
    super.initState();
    _load(widget.admin.status);
  }

  Future<void> _load(Future<LearningStatus> Function() fetch) async {
    try {
      final s = await fetch();
      if (mounted) {
        setState(() {
          _status = s;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '학습 정보를 불러오지 못했어요.');
    }
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _working = label);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('$label에 실패했어요.')));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _train() => _run('학습', () => _load(widget.admin.train));

  /// The demo subgroup from algorithm/demo_compare.py when it exists.
  CompareTarget? _demoTarget(LearningStatus s) =>
      _target ??
      s.targets.where((t) => t.activityId == 'mock_compare_act').firstOrNull ??
      s.targets.firstOrNull;

  /// Re-forms [target] with whatever weights are now in use.
  Future<void> _reform(CompareTarget target) async {
    final outcome = await widget.formation!.generate(
      target.groupId,
      target.activityId,
      republish: false,
    );
    if (!outcome.ok) throw StateError(outcome.message);
  }

  /// 학습 전으로: default weights, then the subgroup is formed again.
  Future<void> _before(CompareTarget target) => _run('학습 전으로', () async {
    await widget.admin.reset();
    await _reform(target);
    await _load(widget.admin.status);
  });

  /// 학습하기: train, apply a passing model, then form the subgroup again.
  Future<void> _learn(CompareTarget target) => _run('학습하기', () async {
    final trained = await widget.admin.train();
    final run = trained.latest;
    if (run?.status != 'candidate' || run?.modelId == null) {
      await _load(() async => trained);
      throw StateError('no candidate');
    }
    await widget.admin.apply(run!.modelId!);
    await _reform(target);
    await _load(widget.admin.status);
  });

  Widget _demo(LearningStatus s) {
    final target = _demoTarget(s);
    final busy = _working != null;
    return _card(
      color: butter,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('시연 · 학습 전후로 편성 바꾸기'),
          Text(
            target == null
                ? '신청이 마감된 소모임이 없어요.'
                : '${target.title}을(를) 지금 값으로 다시 편성해요.',
            style: const TextStyle(fontSize: 12, color: teamixMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || target == null
                      ? null
                      : () => _before(target),
                  child: Text(_working == '학습 전으로' ? '되돌리는 중…' : '학습 전으로'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy || target == null
                      ? null
                      : () => _learn(target),
                  child: Text(_working == '학습하기' ? '학습 중… 몇 분 걸려요' : '학습하기'),
                ),
              ),
            ],
          ),
          if (target != null) ...[const SizedBox(height: 12), _draft(target)],
        ],
      ),
    );
  }

  /// The subgroup's saved draft, teams ordered by their first member.
  Widget _draft(CompareTarget target) => FutureBuilder<Map<String, String>>(
    future: _names[target.groupId] ??= widget.formation!.memberNames(
      target.groupId,
    ),
    builder: (context, names) => StreamBuilder<FormationDraft?>(
      stream: _drafts[target.activityId] ??= widget.formation!.draft(
        target.groupId,
        target.activityId,
      ),
      builder: (context, snapshot) {
        final draft = snapshot.data;
        if (draft == null || draft.teams.isEmpty) {
          return const Text(
            '아직 편성 결과가 없어요. 버튼을 누르면 편성돼요.',
            style: TextStyle(fontSize: 12, color: teamixMuted),
          );
        }
        String name(String uid) => names.data?[uid] ?? uid;
        final teams = [
          for (final t in draft.teams)
            if (t.members.isNotEmpty) [...t.members]..sort(),
        ]..sort((a, b) => a.first.compareTo(b.first));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재 편성 · ${_status?.activeModelId == null ? '기본값' : '학습 보정'}',
              key: const ValueKey('demo-draft-mode'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            for (final (i, t) in teams.indexed)
              Text(
                '팀 ${i + 1} · ${t.map(name).join(', ')}',
                style: const TextStyle(fontSize: 12, color: ink),
              ),
          ],
        );
      },
    ),
  );

  final _names = <String, Future<Map<String, String>>>{};
  final _drafts = <String, Stream<FormationDraft?>>{};

  Future<void> _runCompare(CompareTarget target) => _run('비교', () async {
    final result = await widget.admin.compare(target);
    if (mounted) setState(() => _compare = result);
  });

  Future<void> _apply(String modelId) => _run('적용', () async {
    await widget.admin.apply(modelId);
    await _load(widget.admin.status);
  });

  Future<void> _reset() => _run('되돌리기', () async {
    await widget.admin.reset();
    await _load(widget.admin.status);
  });

  Widget _card(Widget child, {Color color = teamixActionBackground}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    ),
  );

  /// One bar per value, scaled to [max]; [mark] draws the 1.0 line for b.
  Widget _bars(Map<String, double> values, double max, {double? mark}) =>
      Column(
        children: [
          for (final e in values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(e.key, style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Stack(
                        children: [
                          Container(
                            height: 14,
                            width: box.maxWidth * (e.value / max).clamp(0, 1),
                            decoration: BoxDecoration(
                              color: teamixPrimary,
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          if (mark != null)
                            Positioned(
                              left: box.maxWidth * mark / max,
                              child: Container(
                                width: 2,
                                height: 14,
                                color: ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      e.value.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Map<String, double> _named(Map<String, double> b) => {
    for (final k in _criteria.keys)
      if (b.containsKey(k)) _criteria[k]!: b[k]!,
  };

  Widget _current(LearningStatus s) => _card(
    color: s.activeModelId == null ? teamixActionBackground : lilac,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('지금 편성에 쓰는 값'),
        if (s.activeModelId == null)
          const Text(
            '기본값 · 모든 기준 1.0배',
            style: TextStyle(fontSize: 13, color: teamixMuted),
          )
        else ...[
          Text(
            '학습 모델 적용 중 · ${s.activeModelId}',
            style: const TextStyle(fontSize: 12, color: teamixMuted),
          ),
          const SizedBox(height: 8),
          _bars(_named(s.activeB), 2, mark: 1),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _working == null ? _reset : null,
            child: const Text('기본값으로 되돌리기'),
          ),
        ],
      ],
    ),
  );

  Widget _latest(LearningStatus s) {
    final run = s.latest;
    if (run == null) {
      return _card(
        const Text('아직 학습한 적이 없어요.', style: TextStyle(color: teamixMuted)),
      );
    }
    final applicable =
        run.modelId != null &&
        const {'candidate', 'approved', 'retired'}.contains(run.modelStatus);
    final rmse = {
      if (run.rmse['model'] != null) '학습 모델': run.rmse['model']!,
      if (run.rmse['baseline_mean'] != null) '평균값': run.rmse['baseline_mean']!,
      if (run.rmse['baseline_weighted_loss'] != null)
        '기존 가중치': run.rmse['baseline_weighted_loss']!,
    };
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('최근 학습 결과'),
          Text(
            _statusLabels[run.status] ?? run.status,
            key: const ValueKey('learning-status'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            '학습 데이터 ${run.rowCount}팀 · 소모임 ${run.activityCount}개'
            '${run.trainedAt == null ? '' : ' · ${_date(run.trainedAt!)}'}',
            style: const TextStyle(fontSize: 12, color: teamixMuted),
          ),
          if (rmse.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '예측 오차 (작을수록 정확)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            _bars(rmse, rmse.values.reduce((a, b) => a > b ? a : b)),
          ],
          if (run.b.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '기준별 보정값 (1.0 = 기본, 클수록 더 중요하게)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            _bars(_named(run.b), 2, mark: 1),
          ],
          if (run.modelStatus == 'active')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '이 보정값을 편성에 쓰고 있어요.',
                style: TextStyle(fontSize: 12, color: teamixMuted),
              ),
            )
          else if (applicable)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton(
                onPressed: _working == null ? () => _apply(run.modelId!) : null,
                child: const Text('이 보정값 적용'),
              ),
            ),
        ],
      ),
    );
  }

  /// Teams side by side; a learned team not formed by default is highlighted.
  Widget _teams(String title, List<CompareTeam> teams, {Set<String>? same}) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final (i, t) in teams.indexed)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: same == null || same.contains(t.members.join())
                      ? teamixBackground
                      : butter,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '팀 ${i + 1} · ${t.members.join(', ')}',
                      style: const TextStyle(fontSize: 11, color: ink),
                    ),
                    Text(
                      t.commonTimes.isEmpty
                          ? '전원 공통 시간 없음'
                          : '공통 시간 ${t.commonTimes.join(', ')}',
                      style: const TextStyle(fontSize: 10, color: teamixMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _comparison(LearningStatus s) {
    final c = _compare;
    final target = _target ?? s.targets.firstOrNull;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('편성 비교 · 기본값 vs 학습 보정'),
          const Text(
            '같은 신청자를 기본값과 최근 학습 결과로 각각 편성해 봐요. 저장되지는 않아요.',
            style: TextStyle(fontSize: 12, color: teamixMuted),
          ),
          const SizedBox(height: 8),
          if (s.targets.isEmpty)
            const Text(
              '신청이 마감된 소모임이 없어요.',
              style: TextStyle(fontSize: 12, color: teamixMuted),
            )
          else ...[
            DropdownButton<CompareTarget>(
              key: const ValueKey('compare-target'),
              isExpanded: true,
              value: target,
              items: [
                for (final t in s.targets)
                  DropdownMenuItem(
                    value: t,
                    child: Text(
                      t.groupName.isEmpty
                          ? t.title
                          : '${t.groupName} · ${t.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (t) => setState(() {
                _target = t;
                _compare = null;
              }),
            ),
            OutlinedButton(
              onPressed: _working == null && target != null
                  ? () => _runCompare(target)
                  : null,
              child: Text(_working == '비교' ? '편성하는 중…' : '두 방식으로 편성해 보기'),
            ),
          ],
          if (c != null) ...[
            const SizedBox(height: 12),
            if (c.b.isNotEmpty)
              Text(
                '학습 보정: ${[for (final e in c.b.entries)
                  if (_criteria[e.key] != null) '${_criteria[e.key]} ${e.value.toStringAsFixed(2)}배'].join(' · ')}',
                style: const TextStyle(fontSize: 11, color: teamixMuted),
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _teams('기본값', c.before),
                const SizedBox(width: 10),
                _teams(
                  '학습 보정 후',
                  c.after,
                  same: {for (final t in c.before) t.members.join()},
                ),
              ],
            ),
            Text(
              '노란 팀은 학습 보정으로 새로 묶인 팀이에요 · '
              '${c.after.where((t) => !{for (final b in c.before) b.members.join()}.contains(t.members.join())).length}팀 바뀜',
              key: const ValueKey('compare-changed'),
              style: const TextStyle(fontSize: 11, color: teamixMuted),
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.month}월 ${d.day}일 ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = _status;
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
          '학습 관리',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: s == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Text(_error!),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    const Text(
                      '종료된 소모임의 별점 후기로 어떤 편성 기준이 만족도에 영향을 줬는지 배워요. '
                      '적용하기 전까지 편성은 기본값을 써요.',
                      style: TextStyle(fontSize: 12, color: teamixMuted),
                    ),
                    const SizedBox(height: 12),
                    if (widget.formation != null) _demo(s),
                    _current(s),
                    FilledButton.icon(
                      onPressed: _working == null ? _train : null,
                      icon: const Icon(Icons.auto_graph),
                      label: Text(
                        _working == '학습' ? '학습 중… 몇 분 걸릴 수 있어요' : '후기로 학습하기',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _latest(s),
                    _comparison(s),
                  ],
                ),
        ),
      ),
    );
  }
}
