import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/formation.dart';
import '../screens/formation_screen.dart' show teamLabel;
import '../screens/group_card_palette.dart';
import '../theme.dart';

/// The participant's own published team (teamViews), shown on the subgroup
/// detail. Renders nothing until teams are published for them.
class MyTeamCard extends StatefulWidget {
  const MyTeamCard({
    super.key,
    required this.team,
    required this.questions,
    this.palette = GroupCardPalette.defaultJoined,
  });

  final Stream<MyTeam?> Function() team;

  /// Option labels for roles and common times.
  final Future<List<ActivityQuestion>> Function() questions;
  final GroupCardPalette palette;

  @override
  State<MyTeamCard> createState() => _MyTeamCardState();
}

class _MyTeamCardState extends State<MyTeamCard> {
  late final Stream<MyTeam?> _team = widget.team();
  Map<String, String> _labels = const {};

  @override
  void initState() {
    super.initState();
    widget.questions().then((qs) {
      if (!mounted) return;
      setState(() {
        _labels = {
          for (final q in qs)
            for (final o in q.options) '${q.id}:${o.id}': o.label,
        };
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<MyTeam?>(
    stream: _team,
    builder: (context, snapshot) {
      final team = snapshot.data;
      if (team == null) return const SizedBox.shrink();
      return Container(
        key: const ValueKey('my-team-card'),
        width: double.infinity,
        margin: const EdgeInsets.only(top: 22),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: widget.palette.background,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: widget.palette.accent.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '내 팀 · ${teamLabel(team.teamId)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: widget.palette.accent,
              ),
            ),
            const SizedBox(height: 8),
            for (final (name, role) in team.members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  role == null
                      ? name
                      : '$name · ${_labels['role:$role'] ?? role}',
                  style: const TextStyle(fontSize: 13, color: ink),
                ),
              ),
            if (team.commonTimes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '모두 가능한 시간 · '
                '${team.commonTimes.map((t) => _labels['time:$t'] ?? t).join(', ')}',
                style: const TextStyle(fontSize: 12, color: teamixMuted),
              ),
            ],
          ],
        ),
      );
    },
  );
}
