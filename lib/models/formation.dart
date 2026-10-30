/// Public per-team summary the formation server stores with a draft
/// (algorithm/formation.py assess → drafts/{a}.validation.summary).
class TeamSummary {
  const TeamSummary({
    this.size = 0,
    this.commonTimes = const [],
    this.roleCounts = const {},
    this.experienceMean,
  });

  factory TeamSummary.fromJson(Map<String, dynamic>? d) {
    if (d == null) return const TeamSummary();
    final experience = d['selfReportedExperience'];
    return TeamSummary(
      size: (d['size'] as num?)?.toInt() ?? 0,
      commonTimes: [
        for (final t in (d['commonTimes'] as List?) ?? const []) '$t',
      ],
      roleCounts: {
        for (final e in ((d['rolePreferences'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
      experienceMean: experience is Map
          ? (experience['mean'] as num?)?.toDouble()
          : null,
    );
  }

  final int size;

  /// Option IDs of the time question everyone in the team picked.
  final List<String> commonTimes;

  /// Role option ID -> how many members want it.
  final Map<String, int> roleCounts;
  final double? experienceMean;
}

class TeamDraft {
  const TeamDraft({
    required this.teamId,
    required this.members,
    this.summary = const TeamSummary(),
  });

  final String teamId;
  final List<String> members;
  final TeamSummary summary;
}

/// `drafts/{activityId}`: the operator's working draft (admin read only).
class FormationDraft {
  const FormationDraft({
    required this.version,
    required this.teams,
    this.unassigned = const [],
    this.locked = const {},
    this.valid = false,
    this.conflicts = const [],
    this.discarded = false,
  });

  factory FormationDraft.fromFirestore(Map<String, dynamic> d) {
    final validation = (d['validation'] as Map?)?.cast<String, dynamic>();
    final summary = (validation?['summary'] as Map?)?.cast<String, dynamic>();
    return FormationDraft(
      version: (d['version'] as num?)?.toInt() ?? 0,
      teams: [
        for (final t in (d['teams'] as List?) ?? const [])
          if (t is Map)
            TeamDraft(
              teamId: '${t['teamId']}',
              members: [
                for (final m in (t['members'] as List?) ?? const []) '$m',
              ],
              summary: TeamSummary.fromJson(
                (summary?['${t['teamId']}'] as Map?)?.cast<String, dynamic>(),
              ),
            ),
      ],
      unassigned: [
        for (final m in (d['unassigned'] as List?) ?? const []) '$m',
      ],
      locked: {...((d['locks'] as Map?) ?? const {}).keys.map((k) => '$k')},
      valid: validation?['valid'] == true,
      conflicts: [
        for (final c in (validation?['conflicts'] as List?) ?? const []) '$c',
      ],
      discarded: d['discarded'] == true,
    );
  }

  final int version;
  final List<TeamDraft> teams;
  final List<String> unassigned;

  /// Members pinned to their team (default or manual lock).
  final Set<String> locked;
  final bool valid;
  final List<String> conflicts;

  /// Set after publishing; the draft is then only history.
  final bool discarded;

  bool get usable => !discarded && teams.isNotEmpty;
}

/// `teamViews/{a}_{uid}`: the participant's own published team.
class MyTeam {
  const MyTeam({
    required this.teamId,
    required this.members,
    this.commonTimes = const [],
  });

  factory MyTeam.fromFirestore(Map<String, dynamic> d) => MyTeam(
    teamId: d['teamId'] as String? ?? '',
    members: [
      for (final m in (d['members'] as List?) ?? const [])
        if (m is Map)
          (m['displayName'] as String? ?? '팀원', m['role'] as String?),
    ],
    commonTimes: [
      for (final t in (d['commonTimes'] as List?) ?? const []) '$t',
    ],
  );

  final String teamId;

  /// (display name, role option ID or null).
  final List<(String, String?)> members;
  final List<String> commonTimes;
}

/// What the formation server said back, reduced to what the screen needs.
class FormationOutcome {
  const FormationOutcome(this.ok, this.message);

  final bool ok;
  final String message;
}
