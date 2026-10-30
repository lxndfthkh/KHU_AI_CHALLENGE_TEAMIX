import 'package:flutter/material.dart';

import '../data/firestore_activities_source.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// Operator edit of an open (recruiting) subgroup: name, description, type,
/// capacity, team size and deadline. Questions stay as created because
/// registrations already answered them. Sends only the changed fields
/// (functions updateActivity).
class EditActivityScreen extends StatefulWidget {
  const EditActivityScreen({
    super.key,
    required this.activity,
    required this.onSave,
    this.palette = GroupCardPalette.defaultJoined,
    this.now,
  });

  final ActivityRecord activity;
  final Future<void> Function(Map<String, Object> patch) onSave;
  final GroupCardPalette palette;
  final DateTime Function()? now;

  @override
  State<EditActivityScreen> createState() => _EditActivityScreenState();
}

class _EditActivityScreenState extends State<EditActivityScreen> {
  late final _title = TextEditingController(text: widget.activity.title);
  late final _description = TextEditingController(
    text: widget.activity.description,
  );
  late final _capacity = TextEditingController(
    text: '${widget.activity.capacity}',
  );
  late final _teamSize = TextEditingController(
    text: '${widget.activity.targetTeamSize}',
  );
  late DateTime _deadline = widget.activity.deadlineAt;
  late String? _type = widget.activity.type;
  bool _busy = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    for (final c in [_title, _description, _capacity, _teamSize]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDeadline() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _deadline.isAfter(_now) ? _deadline : _now,
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

  /// Changed fields only, or null after telling the operator what to fix.
  Map<String, Object>? _patch() {
    final a = widget.activity;
    final title = _title.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    final teamSize = int.tryParse(_teamSize.text.trim());
    if (title.isEmpty || title.length > 120) {
      _toast('소모임 이름을 1~120자로 입력해 주세요.');
      return null;
    }
    if (capacity == null || capacity < 1 || capacity > 500) {
      _toast('모집 정원은 1~500명으로 입력해 주세요.');
      return null;
    }
    if (capacity < a.participantCount) {
      _toast('이미 ${a.participantCount}명이 신청해서 그보다 줄일 수 없어요.');
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
    return {
      if (title != a.title) 'title': title,
      if (_description.text.trim() != a.description.trim())
        'description': _description.text.trim(),
      if (_type != a.type && _type != null) 'type': _type!,
      if (capacity != a.capacity) 'capacity': capacity,
      if (teamSize != a.targetTeamSize) 'targetTeamSize': teamSize,
      if (_deadline != a.deadlineAt)
        'deadlineAt': _deadline.millisecondsSinceEpoch,
    };
  }

  Future<void> _save() async {
    final patch = _patch();
    if (patch == null || _busy) return;
    if (patch.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave(patch);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('소모임 정보를 바꿨어요.')));
    } catch (_) {
      if (mounted) _toast('수정하지 못했어요. 모집이 마감됐을 수 있어요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
        '소모임 정보 수정',
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
            Material(
              color: widget.palette.background,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(
                      '소모임 이름 *',
                      _title,
                      key: const ValueKey('edit-title'),
                    ),
                    _field('소개', _description, lines: 3),
                    const Text('유형', style: TextStyle(fontSize: 12)),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            '모집 정원',
                            _capacity,
                            number: true,
                            key: const ValueKey('edit-capacity'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            '팀당 인원',
                            _teamSize,
                            number: true,
                            key: const ValueKey('edit-team-size'),
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
                        trailing: Text(
                          '${_deadline.month}월 ${_deadline.day}일 '
                          '${_deadline.hour.toString().padLeft(2, '0')}:'
                          '${_deadline.minute.toString().padLeft(2, '0')}',
                        ),
                        onTap: _pickDeadline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '지금 ${widget.activity.participantCount}명이 신청했어요. '
              '편성 질문은 이미 받은 응답 때문에 바꿀 수 없어요.',
              style: const TextStyle(fontSize: 11, color: teamixMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '저장하는 중…' : '저장'),
            ),
          ],
        ),
      ),
    ),
  );
}
