import 'package:flutter/material.dart';

import '../data/activity_backend.dart';
import '../theme.dart';

/// functions/src/validation.js MAX_PREFERENCES.
const maxPlacementPreferences = 2;

/// Feedback "이 팀과 다시 하고 싶나요?" at or below this offers the sheet.
const preferencePromptRejoinAt = 3;

const _privacyLines = [
  '임원진과 상대방을 포함해 누구에게도 보이지 않아요. 상대에게 알리지도 않아요.',
  '다음 팀 편성부터 다른 기준과 함께 최대한 반영해요. 꼭 다른 팀이 된다고 보장하지는 않아요.',
  '한 모임에서 최대 $maxPlacementPreferences명까지, 언제든 해제할 수 있어요.',
];

/// 비공개 배치 선호: "다른 팀이면 좋겠는 사람" for this group. Only the
/// author can read these (firestore.rules placementPreferences); the
/// formation server reads them and never reports them back to operators.
class PlacementPreferencesScreen extends StatefulWidget {
  const PlacementPreferencesScreen({
    super.key,
    required this.groupName,
    required this.groupId,
    required this.backend,
  });

  final String groupName;
  final String groupId;
  final ActivityBackend backend;

  @override
  State<PlacementPreferencesScreen> createState() =>
      _PlacementPreferencesScreenState();
}

class _PlacementPreferencesScreenState
    extends State<PlacementPreferencesScreen> {
  late final Stream<Set<String>> _mine = widget.backend.myPlacementPreferences(
    widget.groupId,
  );
  late final Future<List<GroupPeer>> _peers = widget.backend.groupPeers(
    widget.groupId,
  );
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('저장하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<GroupPeer> peers, Set<String> mine) async {
    final choices = [
      for (final p in peers)
        if (!mine.contains(p.userId)) p,
    ];
    final picked = await showModalBottomSheet<GroupPeer>(
      context: context,
      backgroundColor: teamixBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            children: [
              const Text(
                '다른 팀이면 좋겠는 사람 고르기',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              if (choices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '고를 수 있는 멤버가 없어요.',
                    style: TextStyle(fontSize: 13, color: teamixMuted),
                  ),
                ),
              for (final p in choices)
                ListTile(
                  key: ValueKey('peer-${p.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name),
                  onTap: () => Navigator.pop(sheet, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${picked.name}님과 다른 팀이면 좋겠어요'),
        content: const Text('이 선택은 나만 볼 수 있어요. 임원진과 상대방에게 보이지 않아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('비공개로 저장'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () =>
          widget.backend.setPlacementPreference(widget.groupId, picked.userId),
      '저장했어요. 다음 팀 편성부터 반영돼요.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '모임 홈으로 돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      title: const Text(
        '비공개 배치 선호',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      centerTitle: true,
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: FutureBuilder<List<GroupPeer>>(
          future: _peers,
          builder: (context, peers) => StreamBuilder<Set<String>>(
            stream: _mine,
            builder: (context, mine) {
              if (peers.hasError || mine.hasError) {
                return const _Message('불러오지 못했어요.\n잠시 후 다시 열어 주세요.');
              }
              if (!peers.hasData || !mine.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final names = {for (final p in peers.data!) p.userId: p.name};
              final chosen = mine.data!.toList()..sort();
              final full = chosen.length >= maxPlacementPreferences;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    widget.groupName,
                    style: const TextStyle(fontSize: 12, color: teamixMuted),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '다른 팀이면 좋겠는 사람이 있나요?',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PrivacyNote(),
                  const SizedBox(height: 20),
                  Text(
                    '지정한 사람 ${chosen.length}/$maxPlacementPreferences',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (chosen.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '아직 지정한 사람이 없어요.',
                        style: TextStyle(fontSize: 12, color: teamixMuted),
                      ),
                    ),
                  for (final id in chosen)
                    Container(
                      key: ValueKey('preference-$id'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                      decoration: BoxDecoration(
                        color: lilac,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: teamixPurpleAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              names[id] ?? '모임을 나간 멤버',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => widget.backend
                                        .revokePlacementPreference(
                                          widget.groupId,
                                          id,
                                        ),
                                    '해제했어요.',
                                  ),
                            child: const Text('해제'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || full
                        ? null
                        : () => _add(peers.data!, mine.data!),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(
                      full
                          ? '최대 $maxPlacementPreferences명까지 지정할 수 있어요'
                          : '사람 고르기',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// The privacy promises, shared by the screen and the feedback sheet.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: teamixActionBackground,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in _privacyLines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '· $line',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: teamixActionForeground,
              ),
            ),
          ),
      ],
    ),
  );
}

/// After a low "다시 하고 싶나요?" score: offer this team's members, kept
/// separate from the scores. Does nothing if there's no teammate or slot.
Future<void> offerTeammatePreferences(
  BuildContext context,
  ActivityBackend backend,
  String groupId,
  String activityId,
) async {
  final List<GroupPeer> mates;
  final Set<String> mine;
  try {
    mates = await backend.teammates(groupId, activityId);
    mine = await backend.myPlacementPreferences(groupId).first;
  } catch (_) {
    return;
  }
  final open = [
    for (final m in mates)
      if (!mine.contains(m.userId)) m,
  ];
  final slots = maxPlacementPreferences - mine.length;
  if (open.isEmpty || slots <= 0 || !context.mounted) return;

  final picked = await showModalBottomSheet<Set<String>>(
    context: context,
    backgroundColor: teamixBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => _TeammateSheet(mates: open, slots: slots),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    for (final id in picked) {
      await backend.setPlacementPreference(groupId, id);
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('비공개로 저장했어요. 다음 팀 편성부터 반영돼요.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('저장하지 못했어요. 모임 홈에서 다시 지정할 수 있어요.')),
    );
  }
}

class _TeammateSheet extends StatefulWidget {
  const _TeammateSheet({required this.mates, required this.slots});

  final List<GroupPeer> mates;
  final int slots;

  @override
  State<_TeammateSheet> createState() => _TeammateSheetState();
}

class _TeammateSheetState extends State<_TeammateSheet> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      key: const ValueKey('teammate-preference-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      children: [
        const Text(
          '다음 편성에서 다른 팀이면 좋겠는 팀원이 있나요?',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '선택은 후기 점수와 따로 저장돼요. 최대 ${widget.slots}명.',
          style: const TextStyle(fontSize: 12, color: teamixMuted),
        ),
        const SizedBox(height: 10),
        const PrivacyNote(),
        const SizedBox(height: 6),
        for (final m in widget.mates)
          CheckboxListTile(
            key: ValueKey('mate-${m.userId}'),
            contentPadding: EdgeInsets.zero,
            value: _picked.contains(m.userId),
            title: Text(m.name),
            onChanged:
                _picked.contains(m.userId) || _picked.length < widget.slots
                ? (on) => setState(
                    () => on == true
                        ? _picked.add(m.userId)
                        : _picked.remove(m.userId),
                  )
                : null,
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, _picked),
          child: const Text('비공개로 저장'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('괜찮아요'),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, height: 1.6, color: teamixMuted),
    ),
  );
}
