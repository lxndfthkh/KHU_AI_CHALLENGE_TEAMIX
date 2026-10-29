import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/matching.dart';
import '../services/team_matching_service.dart';
import '../theme.dart';
import 'matching_running_screen.dart';

class MatchingSettingsScreen extends StatefulWidget {
  const MatchingSettingsScreen({super.key, this.service});
  final TeamMatchingService? service;
  @override
  State<MatchingSettingsScreen> createState() => _MatchingSettingsScreenState();
}

class _MatchingSettingsScreenState extends State<MatchingSettingsScreen> {
  static const _labels = {
    'time': '가능 시간', 'role': '희망 역할',
    'experience': '경험 수준', 'interest': '관심 분야', 'size': '팀 인원',
  };
  final _capacity = TextEditingController();
  MatchingInput? _source;
  String? _loadError;
  late final TeamMatchingService _service;
  int _teamCount = 4;
  String _method = 'balanced';
  bool _requireCommonTime = false;
  final Set<String> _selected = {};
  final List<String> _priority = [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HttpTeamMatchingService();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString('assets/demo/initial_20.json');
      final input = MatchingInput.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _source = input;
        _loadError = null;
        _teamCount = input.teams.length;
        _method = input.method;
        _selected.addAll(input.selectedQuestions);
        _priority.addAll(input.priority);
        _requireCommonTime = input.requireCommonTime;
        _capacity.text = (input.participants.length / _teamCount).ceil().toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = '시연 참가자 정보를 불러오지 못했어요.');
    }
  }

  @override
  void dispose() {
    _capacity.dispose();
    if (widget.service == null && _service is HttpTeamMatchingService) {
      _service.close();
    }
    super.dispose();
  }

  bool _hasAnswer(MatchingParticipant participant, String question) {
    final answer = participant.answers[question];
    if (question == 'experience') {
      return answer is int && answer >= 1 && answer <= 5;
    }
    if (question == 'role') return answer is String && answer.isNotEmpty;
    return answer is List && answer.isNotEmpty;
  }

  int get _respondents => _source!.participants
      .where((p) => _selected.every((q) => _hasAnswer(p, q))).length;

  void _toggle(String question, bool enabled) {
    setState(() {
      if (enabled) {
        _selected.add(question);
        _priority.add(question);
      } else {
        _selected.remove(question);
        _priority.remove(question);
        if (question == 'time') _requireCommonTime = false;
      }
    });
  }

  void _start() {
    final source = _source!;
    final capacity = int.tryParse(_capacity.text.trim());
    String? error;
    if (capacity == null || capacity < 1) {
      error = '팀당 정원을 1 이상의 정수로 입력해 주세요.';
    } else if (capacity * _teamCount < source.participants.length) {
      error = '전체 참가자를 수용할 수 있도록 팀당 정원을 늘려 주세요.';
    } else if (_respondents != source.participants.length) {
      error = '선택한 질문에 대한 참가자 응답을 모두 확인해 주세요.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final json = source.toJson();
    json['method'] = _method;
    json['selected_questions'] = _priority.where((q) => q != 'size').toList();
    json['priority'] = _priority.toList();
    json['teams'] = List.generate(_teamCount,
      (i) => {'id': 'team_${i + 1}', 'capacity': capacity});
    json['require_common_time'] = _selected.contains('time') && _requireCommonTime;
    json['fixed'] = <dynamic>[];
    json['required_roles'] = <dynamic>[];
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MatchingRunningScreen(
        input: MatchingInput.fromJson(json), service: _service,
      ),
    ));
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: mint,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
            color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12), child,
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      backgroundColor: teamixBackground,
      appBar: AppBar(title: const Text('편성 설정')),
      bottomNavigationBar: source == null ? null : SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Align(heightFactor: 1, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FilledButton.icon(
            key: const ValueKey('matching-start'),
            onPressed: _start, icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('편성 실행'),
          ),
        )),
      ),
      body: source == null
        ? Center(child: _loadError == null
          ? const CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_loadError!),
              TextButton(onPressed: () {
                setState(() => _loadError = null);
                _load();
              }, child: const Text('다시 불러오기')),
            ]))
        : Align(alignment: Alignment.topCenter, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            _section('참가자 응답', Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('응답 현황 $_respondents/${source.participants.length}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 8),
                const Text('가상 부원 20명의 시연 데이터예요. 선택한 질문의 응답만 확인해요.'),
              ],
            )),
            _section('팀 구성', Column(children: [
              Row(children: [
                const Expanded(child: Text('팀 수')),
                DropdownButton<int>(
                  value: _teamCount,
                  items: List.generate(source.participants.length, (i) =>
                    DropdownMenuItem(value: i + 1, child: Text('${i + 1}팀'))),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _teamCount = value;
                      _capacity.text = (source.participants.length / value).ceil().toString();
                    });
                  },
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '팀당 정원', helperText: '팀 수를 바꾸면 인원 ÷ 팀 수의 올림으로 설정돼요.',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true, value: _method,
                items: const [
                  DropdownMenuItem(value: 'balanced', child: Text('균형')),
                  DropdownMenuItem(value: 'similar', child: Text('비슷하게')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
            ])),
            _section('사용할 질문', Column(children: [
              for (final q in ['role', 'time', 'experience', 'interest'])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_labels[q]!), value: _selected.contains(q),
                  onChanged: (value) => _toggle(q, value ?? false),
                ),
              const Text('선택하지 않은 질문은 편성과 요약에서 제외해요.'),
            ])),
            _section('우선순위', Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('손잡이를 드래그해 정렬하세요. 위쪽일수록 중요해요.'),
                const SizedBox(height: 8),
                ReorderableListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _priority.length,
                  onReorderItem: (oldIndex, newIndex) => setState(() {
                    final question = _priority.removeAt(oldIndex);
                    _priority.insert(newIndex, question);
                  }),
                  itemBuilder: (context, index) => ListTile(
                    key: ValueKey(_priority[index]), contentPadding: EdgeInsets.zero,
                    leading: Text('${index + 1}'),
                    title: Text(_labels[_priority[index]]!),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: const Tooltip(message: '우선순위 이동', child: Icon(Icons.drag_handle)),
                    ),
                  ),
                ),
              ],
            )),
            _section('추가 조건', Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('공통 시간 필수'),
                subtitle: const Text('모든 팀에 전원이 가능한 시간이 있어야 해요.'),
                value: _requireCommonTime,
                onChanged: !_selected.contains('time') ? null
                  : (value) => setState(() => _requireCommonTime = value),
              ),
              const ListTile(enabled: false, contentPadding: EdgeInsets.zero,
                title: Text('고정 배치'), subtitle: Text('추후 지원'),
                trailing: Icon(Icons.lock_outline)),
              const ListTile(enabled: false, contentPadding: EdgeInsets.zero,
                title: Text('필수 역할'), subtitle: Text('추후 지원'),
                trailing: Icon(Icons.lock_outline)),
            ])),
          ]),
        )),
    );
  }
}
