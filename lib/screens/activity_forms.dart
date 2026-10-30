import 'package:flutter/material.dart';
import '../data/activity_registration.dart';
import '../theme.dart';

const questionLabels = {'role': '희망 역할', 'time': '가능 시간', 'experience': '경험 수준', 'interest': '관심 분야'};

class CreateActivityScreen extends StatefulWidget {
  const CreateActivityScreen({super.key, required this.api, required this.groupId,
    this.themeColor = 'mint', this.ownsApi = false});
  final ActivityRegistrationApi api;
  final String groupId, themeColor;
  final bool ownsApi;
  @override
  State<CreateActivityScreen> createState() => _CreateActivityScreenState();
}
class _CreateActivityScreenState extends State<CreateActivityScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController(), goal = TextEditingController();
  final capacity = TextEditingController(), size = TextEditingController();
  final options = {
    'role': TextEditingController(text: '기획\n개발\n디자인\n운영'),
    'time': TextEditingController(text: '수 저녁\n금 저녁\n토 오후'),
    'interest': TextEditingController(text: '웹 서비스\n콘텐츠\n커뮤니티\n앱 개발'),
  };
  final selected = <String>{'role', 'time', 'experience', 'interest'};
  late String color;
  DateTime? deadline;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    deadline = DateTime.now().add(const Duration(days: 7));
    color = ['mint', 'peach', 'lilac'].contains(widget.themeColor) ? widget.themeColor : 'mint';
  }
  @override
  void dispose() {
    for (final c in [title, description, goal, capacity, size, ...options.values]) {
      c.dispose();
    }
    if (widget.ownsApi) {
      widget.api.dispose();
    }
    super.dispose();
  }
  Future<void> pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: deadline ?? now,
      firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 10));
    if (!mounted || date == null) {
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(deadline ?? now));
    if (!mounted || time == null) {
      return;
    }
    setState(() => deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) {
      return;
    }
    if (deadline == null || !deadline!.isAfter(DateTime.now())) {
      setState(() => error = '미래의 마감일시를 선택해 주세요.');
      return;
    }
    final fullDescription = [description.text.trim(), '활동 목표: ${goal.text.trim()}'].where((v) => v.isNotEmpty).join('\n\n');
    if (fullDescription.length > 5000) {
      setState(() => error = '설명과 활동 목표는 합쳐서 5,000자 이내로 입력해 주세요.');
      return;
    }
    final questions = <Map<String, dynamic>>[];
    for (final id in questionLabels.keys.where(selected.contains)) {
      questions.add({'id': id, 'label': questionLabels[id], 'required': true, 'enabled': true,
        'type': id == 'role' ? 'single' : id == 'experience' ? 'scale' : 'multiple',
        'options': id == 'experience' ? <Map<String, String>>[] : [
          for (final (index, label) in options[id]!.text.trim().split('\n').map((v) => v.trim()).indexed)
            {'id': 'o$index', 'label': label},
        ],
      });
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.api.createActivity(widget.groupId, {
        'title': title.text.trim(), 'description': fullDescription,
        'capacity': int.parse(capacity.text), 'targetTeamSize': int.parse(size.text),
        'deadlineAt': deadline!.millisecondsSinceEpoch, 'themeColor': color, 'questions': questions,
        'matching': {'method': 'balanced', 'questionCriteria': {for (final q in questions) q['id'] as String: q['id']},
          'priority': [...questions.map((q) => q['id']), 'size'], 'requireCommonTime': false},
      });
      if (result['activityId'] is! String) {
        throw StateError('Invalid result');
      }
      if (mounted) {
        Navigator.pop(context, result['activityId']);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = activityError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
  Widget input(String label, TextEditingController controller, {int? maximum, int lines = 1}) =>
    Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
      controller: controller, enabled: !busy, maxLines: lines,
      keyboardType: maximum == null ? TextInputType.text : TextInputType.number,
      decoration: InputDecoration(labelText: label), validator: (value) {
        final v = value?.trim() ?? '';
        if (v.isEmpty) {
          return '입력해 주세요.';
        }
        if (maximum != null && (int.tryParse(v) == null || int.parse(v) < 1 || int.parse(v) > maximum)) {
          return '1~$maximum 범위의 정수를 입력해 주세요.';
        }
        if (controller == title && v.length > 120) {
          return '제목은 120자 이내로 입력해 주세요.';
        }
        return null;
      },
    ));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('소모임 만들기')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      input('제목', title), input('설명', description, lines: 3), input('활동 목표', goal),
      input('모집 정원', capacity, maximum: 500), input('팀당 목표 인원', size, maximum: 50),
      OutlinedButton(onPressed: busy ? null : pickDeadline,
        child: Text(deadline == null ? '마감일시 선택' : '마감: $deadline')),
      Wrap(spacing: 8, children: [for (final c in ['mint', 'peach', 'lilac'])
        ChoiceChip(label: Text(switch (c) {'mint' => '민트', 'peach' => '피치', _ => '라일락'}),
          selected: color == c, onSelected: busy ? null : (_) => setState(() => color = c)),
      ]),
      const SizedBox(height: 16), const Text('참가 질문 · 선택한 항목만 필수 질문으로 사용해요.'),
      const Text('첫 신청 후 질문은 잠겨요. 편성 방식 기본값은 균형형이에요.'),
      for (final id in questionLabels.keys) ...[
        CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(questionLabels[id]!),
          value: selected.contains(id), onChanged: busy ? null : (value) => setState(() {
            if (value == true) { selected.add(id); } else { selected.remove(id); }
          })),
        if (selected.contains(id) && id != 'experience') TextFormField(
          key: ValueKey('options-$id'), controller: options[id], enabled: !busy, maxLines: 4,
          decoration: const InputDecoration(labelText: '선택지 · 한 줄에 하나'), validator: (value) {
            final labels = (value ?? '').trim().split('\n').map((v) => v.trim()).toList();
            if (labels.length > 30 || labels.any((v) => v.isEmpty || v.length > 60)) {
              return '선택지는 1~30개, 각 1~60자로 입력해 주세요.';
            }
            if (labels.toSet().length != labels.length) {
              return '같은 선택지는 한 번만 입력해 주세요.';
            }
            return null;
          }),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: coral)),
      const SizedBox(height: 24), FilledButton(onPressed: busy ? null : save,
        child: Text(busy ? '생성 중…' : '소모임 생성')),
    ]))),
  );
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.api, required this.activityId,
    required this.registration, required this.canEdit, required this.canCancel});
  final ActivityRegistrationApi api;
  final String activityId;
  final Map<String, dynamic>? registration;
  final bool canEdit, canCancel;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}
class _RegistrationScreenState extends State<RegistrationScreen> {
  late final Future<List<Map<String, dynamic>>> questions;
  late final Map<String, dynamic> answers;
  bool busy = false;
  String? error;
  bool get editing => widget.registration?['status'] == 'submitted';
  @override
  void initState() {
    super.initState();
    questions = widget.api.questions(widget.activityId);
    answers = Map<String, dynamic>.from(widget.registration?['answers'] as Map? ?? {});
  }
  bool valid(List<Map<String, dynamic>> qs) => qs.every((q) {
    final value = answers[q['id']];
    final ids = [for (final o in q['options'] as List) (o as Map)['id']];
    if (value == null) {
      return q['required'] == false;
    }
    return switch (q['type']) {
      'single' => value is String && ids.contains(value),
      'multiple' => value is List && value.isNotEmpty && value.toSet().length == value.length && value.every(ids.contains),
      'scale' => value is int && value >= 1 && value <= 5,
      _ => false,
    };
  });
  Future<void> send(List<Map<String, dynamic>> qs, {bool cancel = false}) async {
    if (busy) {
      return;
    }
    if (!cancel && !valid(qs)) {
      setState(() => error = '각 질문에 응답해 주세요. 복수 선택은 1개 이상, 경험 수준은 1~5예요.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (cancel) {
        await widget.api.cancel(widget.activityId);
      } else {
        await widget.api.submit(widget.activityId,
          {for (final q in qs) if (answers.containsKey(q['id'])) q['id'] as String: answers[q['id']]}, editing: editing);
      }
      if (mounted) {
        Navigator.pop(context, {'status': cancel ? 'cancelled' : 'submitted', 'answers': answers});
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = activityError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(editing ? '응답 수정·취소' : '참가 설문')),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: questions, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('질문을 불러오지 못했어요. 다시 열어 주세요.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final qs = snapshot.data!;
      return ListView(padding: const EdgeInsets.all(24), children: [
        if (!widget.canEdit) const Text('지금은 응답을 제출·수정할 수 없어요.'),
        for (final q in qs) Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q['label'] as String),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (q['type'] == 'scale') for (var n = 1; n <= 5; n++)
              ChoiceChip(label: Text('$n'), selected: answers[q['id']] == n,
                onSelected: busy || !widget.canEdit ? null : (_) => setState(() => answers[q['id']] = n)),
            if (q['type'] != 'scale') for (final option in q['options'] as List)
              FilterChip(label: Text(option['label'] as String),
                selected: q['type'] == 'single' ? answers[q['id']] == option['id']
                  : (answers[q['id']] as List? ?? []).contains(option['id']),
                onSelected: busy || !widget.canEdit ? null : (selected) => setState(() {
                  if (q['type'] == 'single') {
                    answers[q['id']] = option['id'];
                  } else {
                    final values = List<dynamic>.from(answers[q['id']] as List? ?? []);
                    if (selected) { values.add(option['id']); } else { values.remove(option['id']); }
                    answers[q['id']] = values;
                  }
                })),
          ]),
        ])),
        if (error != null) Text(error!, style: const TextStyle(color: coral)),
        FilledButton(onPressed: busy || !widget.canEdit ? null : () => send(qs),
          child: Text(busy ? '처리 중…' : editing ? '응답 저장' : '참가 신청 제출')),
        if (editing) OutlinedButton(onPressed: busy || !widget.canCancel ? null : () => send(qs, cancel: true),
          child: const Text('참가 신청 취소')),
      ]);
    }),
  );
}
