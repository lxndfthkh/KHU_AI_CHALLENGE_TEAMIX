import 'package:flutter/material.dart';

import '../data/activity_backend.dart';
import '../data/firestore_activities_source.dart';
import '../data/formation_backend.dart';
import '../models/activity.dart';
import '../theme.dart';
import 'edit_activity_screen.dart';
import 'formation_screen.dart';
import 'group_card_palette.dart';

/// Operator actions on one subgroup, shared by the card's ⚙ menu, the group
/// home's 팀 편성 button and the subgroup detail.
class ActivityAdmin {
  const ActivityAdmin({
    required this.source,
    required this.backend,
    required this.formation,
    required this.groupId,
    required this.palette,
  });

  final ActivitiesSource source;
  final ActivityBackend backend;

  /// Null when FORMATION_URL isn't configured.
  final FormationBackend? formation;
  final String groupId;
  final GroupCardPalette palette;

  void _tell(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void edit(BuildContext context, ActivityRecord activity) {
    if (!activity.recruiting) {
      return _tell(context, '모집 중인 소모임만 수정할 수 있어요.');
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EditActivityScreen(
          activity: activity,
          palette: palette,
          onSave: (patch) => backend.updateActivity(activity.id, patch),
        ),
      ),
    );
  }

  Future<void> formationFor(
    BuildContext context,
    ActivityRecord activity,
  ) async {
    final server = formation;
    if (server == null) {
      return _tell(context, '편성 서버 주소가 설정되지 않았어요. FORMATION_URL로 실행해 주세요.');
    }
    // Labels only; the screen still works with raw option IDs.
    final questions = await backend
        .questions(activity.id)
        .catchError((_) => const <ActivityQuestion>[]);
    if (!context.mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FormationScreen(
          groupId: groupId,
          activity: source.watchActivity(activity.id),
          backend: server,
          questions: questions,
          palette: palette,
        ),
      ),
    );
  }

  Future<void> applicants(BuildContext context, ActivityRecord activity) async {
    final questions = await backend
        .questions(activity.id)
        .catchError((_) => const <ActivityQuestion>[]);
    if (!context.mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApplicantsScreen(
          activity: activity,
          applicants: backend.applicants(groupId, activity.id),
          questions: questions,
          palette: palette,
        ),
      ),
    );
  }

  /// ⚙ on a subgroup card: what an operator can do at this stage.
  Future<void> showMenu(
    BuildContext context,
    ActivityRecord activity, {
    required VoidCallback onOpenDetail,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: teamixBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) {
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '${activity.title} 관리',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (activity.recruiting)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('소모임 정보 수정'),
                onTap: () => run(() => edit(context, activity)),
              ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text('신청 현황 · ${activity.participantCount}명'),
              onTap: () => run(() => applicants(context, activity)),
            ),
            if (activity.status == 'recruiting' || activity.status == 'closed')
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(activity.recruiting ? '신청 마감 · 팀 편성' : '팀 편성 관리'),
                onTap: () => run(() => formationFor(context, activity)),
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('상세 보기 · 활동 단계'),
              onTap: () => run(onOpenDetail),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Operator list of sign-ups with their answers as labels.
class ApplicantsScreen extends StatelessWidget {
  const ApplicantsScreen({
    super.key,
    required this.activity,
    required this.applicants,
    this.questions = const [],
    this.palette = GroupCardPalette.defaultJoined,
  });

  final ActivityRecord activity;
  final Stream<List<Applicant>> applicants;
  final List<ActivityQuestion> questions;
  final GroupCardPalette palette;

  String _answer(ActivityQuestion q, Object? value) {
    String label(Object? id) =>
        q.options.where((o) => o.id == '$id').map((o) => o.label).firstOrNull ??
        '$id';
    return switch (value) {
      null => '-',
      final List<Object?> ids => ids.map(label).join(', '),
      final num n when q.type == 'scale' => '$n / 5',
      _ => label(value),
    };
  }

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
        '신청 현황',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<List<Applicant>>(
          stream: applicants,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('신청 현황을 불러오지 못했어요.'));
            }
            final all = snapshot.data;
            if (all == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final active = [
              for (final a in all)
                if (a.submitted) a,
            ]..sort((a, b) => a.name.compareTo(b.name));
            final cancelled = all.length - active.length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  activity.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                Text(
                  '신청 ${active.length} / ${activity.capacity}명'
                  '${cancelled > 0 ? ' · 취소 $cancelled명' : ''}',
                  style: const TextStyle(fontSize: 12, color: teamixMuted),
                ),
                const SizedBox(height: 12),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      '아직 신청한 사람이 없어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: teamixMuted),
                    ),
                  ),
                for (final a in active)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        for (final q in questions)
                          Text(
                            '${q.label} · ${_answer(q, a.answers[q.id])}',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
