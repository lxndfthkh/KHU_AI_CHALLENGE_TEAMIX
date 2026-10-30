/// Public per-team summary the formation server stores with a draft
/// (algorithm/formation.py assess → drafts/{a}.validation.summary).
/// A team's score on one personality axis (formation.py assess): [sum] of
/// item answers over [respondents] people answering [items] questions each.
class TraitScore {
  const TraitScore({
    required this.sum,
    required this.items,
    required this.respondents,
  });

  final int sum;
  final int items;
  final int respondents;

  /// Team average on the 1-5 answer scale.
  double get mean =>
      items <= 0 || respondents <= 0 ? 0 : sum / (items * respondents);
}

class TeamSummary {
  const TeamSummary({
    this.size = 0,
    this.commonTimes = const [],
    this.roleCounts = const {},
    this.experienceMean,
    this.personality = const {},
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
      personality: {
        for (final e in ((d['personality'] as Map?) ?? const {}).entries)
          if (e.value is Map)
            '${e.key}': TraitScore(
              sum: ((e.value as Map)['sum'] as num?)?.toInt() ?? 0,
              items: ((e.value as Map)['items'] as num?)?.toInt() ?? 0,
              respondents:
                  ((e.value as Map)['respondents'] as num?)?.toInt() ?? 0,
            ),
      },
    );
  }

  final int size;

  /// Option IDs of the time question everyone in the team picked.
  final List<String> commonTimes;

  /// Role option ID -> how many members want it.
  final Map<String, int> roleCounts;
  final double? experienceMean;

  /// Personality axis ID -> team score. Team averages only, never people.
  final Map<String, TraitScore> personality;
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

/// Korean labels for matching criteria (algorithm CRITERIA plus size).
const criterionLabels = {
  'role': '희망 역할',
  'time': '가능 시간',
  'experience': '경험 수준',
  'interest': '관심 분야',
  'personality': '성향 균형',
  'size': '인원 균형',
};

/// `activities/{a}/settings/matching` (admin read), as repository.py writes it.
class FormationSettings {
  const FormationSettings({
    this.teamIds = const [],
    this.priority = const [],
    this.method = 'balanced',
    this.requireCommonTime = false,
    this.requiredRoles = const [],
    this.learningEnabled = true,
    this.questionCriteria = const {},
    this.traitLabels = const {},
  });

  factory FormationSettings.fromFirestore(Map<String, dynamic> d) =>
      FormationSettings(
        teamIds: [for (final t in (d['teamIds'] as List?) ?? const []) '$t'],
        priority: [for (final p in (d['priority'] as List?) ?? const []) '$p'],
        method: d['method'] as String? ?? 'balanced',
        requireCommonTime: d['requireCommonTime'] == true,
        requiredRoles: [
          for (final r in (d['requiredRoles'] as List?) ?? const [])
            if (r is Map)
              (
                '${r['teamId']}',
                '${r['optionId']}',
                (r['minimum'] as num?)?.toInt() ?? 1,
              ),
        ],
        learningEnabled: d['learningEnabled'] != false,
        questionCriteria: {
          for (final e in ((d['questionCriteria'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        },
        traitLabels: {
          for (final t in (d['traits'] as List?) ?? const [])
            if (t is Map && t['id'] is String)
              t['id'] as String: (t['label'] as String?) ?? t['id'] as String,
        },
      );

  /// Empty before recruiting closes (teams are estimated then).
  final List<String> teamIds;

  /// Criteria keys in priority order, ending with or containing 'size'.
  final List<String> priority;
  final String method;
  final bool requireCommonTime;

  /// (teamId, role option ID, minimum).
  final List<(String, String, int)> requiredRoles;
  final bool learningEnabled;

  /// questionId -> criterion.
  final Map<String, String> questionCriteria;

  /// Personality axis ID -> label, in the order set at creation.
  final Map<String, String> traitLabels;

  /// Priority to show when none is saved yet.
  List<String> get defaultPriority => [
    if (traitLabels.isNotEmpty) 'personality',
    ...questionCriteria.values,
    'size',
  ];
}

/// What the operator chose on the settings screen; sent as the server's
/// internal `updateMatchingSettings` patch.
class FormationSettingsPatch {
  const FormationSettingsPatch({
    required this.teamCount,
    required this.participants,
    required this.priority,
    required this.method,
    required this.requireCommonTime,
    required this.learningEnabled,
    this.requiredRole,
  });

  final int teamCount;

  /// Applicants now, for the default per-team capacity ceil(N / K).
  final int participants;
  final List<String> priority;
  final String method;
  final bool requireCommonTime;
  final bool learningEnabled;

  /// (role option ID, minimum per team), applied to every team.
  final (String, int)? requiredRole;

  List<String> get teamIds => [for (var i = 1; i <= teamCount; i++) 'team_$i'];

  Map<String, Object> toJson() {
    final cap = participants <= 0 ? 1 : (participants / teamCount).ceil();
    final role = requiredRole;
    return {
      'teamIds': teamIds,
      'capacity': {for (final t in teamIds) t: cap},
      'criteria': [
        for (var i = 0; i < priority.length; i++)
          {'key': priority[i], 'priority': i + 1},
      ],
      'formationMode': method,
      'extraRequirements': [
        if (requireCommonTime) {'type': 'commonTime'},
        if (role != null)
          for (final t in teamIds)
            {
              'type': 'requiredRole',
              'teamId': t,
              'role': role.$1,
              'minimum': role.$2,
            },
      ],
      'learningEnabled': learningEnabled,
    };
  }
}
