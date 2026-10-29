import 'dart:convert';

// JSON-only deep copies keep snapshots independent of caller mutations.
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map<String, dynamic> _object(dynamic value) =>
    Map<String, dynamic>.from(value as Map);
List<String> _strings(dynamic value) => (value as List).cast<String>();
Map<String, int> _counts(dynamic value) =>
    Map<String, int>.from(value as Map);

class MatchingParticipant {
  MatchingParticipant({required this.id, required Map<String, dynamic> answers})
      : _answers = _copy(answers);
  final String id;
  final Map<String, dynamic> _answers;
  Map<String, dynamic> get answers => _copy(_answers);
  factory MatchingParticipant.fromJson(Map<String, dynamic> json) =>
      MatchingParticipant(id: json['id'] as String, answers: _object(json['answers']));
  Map<String, dynamic> toJson() => {'id': id, 'answers': answers};
}

class MatchingTeam {
  const MatchingTeam({required this.id, this.capacity});
  final String id;
  final int? capacity;
  factory MatchingTeam.fromJson(Map<String, dynamic> json) => MatchingTeam(
        id: json['id'] as String,
        capacity: json['capacity'] as int?,
      );
  Map<String, dynamic> toJson() => {'id': id, 'capacity': capacity};
}

class FixedAssignment {
  const FixedAssignment({required this.participant, required this.team});
  final String participant;
  final String team;
  factory FixedAssignment.fromJson(Map<String, dynamic> json) => FixedAssignment(
        participant: json['participant'] as String, team: json['team'] as String);
  Map<String, dynamic> toJson() => {'participant': participant, 'team': team};
}

class RequiredRole {
  const RequiredRole({required this.team, required this.role, required this.minimum});
  final String team;
  final String role;
  final int minimum;
  factory RequiredRole.fromJson(Map<String, dynamic> json) => RequiredRole(
        team: json['team'] as String,
        role: json['role'] as String,
        minimum: json['minimum'] as int,
      );
  Map<String, dynamic> toJson() => {'team': team, 'role': role, 'minimum': minimum};
}

class PrivatePreference {
  const PrivatePreference({required this.source, required this.target,
    required this.confirmed, this.withdrawn});
  final String source;
  final String target;
  final bool confirmed;
  final bool? withdrawn;
  factory PrivatePreference.fromJson(Map<String, dynamic> json) => PrivatePreference(
        source: json['source'] as String,
        target: json['target'] as String,
        confirmed: json['confirmed'] as bool,
        withdrawn: json['withdrawn'] as bool?,
      );
  Map<String, dynamic> toJson() => {
        'source': source, 'target': target, 'confirmed': confirmed,
        if (withdrawn != null) 'withdrawn': withdrawn,
      };
}

class MatchingInput {
  MatchingInput({required this.schemaVersion, required this.mode,
    required this.method, required List<String> selectedQuestions,
    required List<String> priority, required Map<String, dynamic> categories,
    required List<MatchingTeam> teams,
    required List<MatchingParticipant> participants,
    List<FixedAssignment> fixed = const [],
    List<RequiredRole> requiredRoles = const [],
    this.requireCommonTime = false,
    List<PrivatePreference> privatePreferences = const [],
    Map<String, dynamic> versions = const {},
    Map<String, dynamic> solver = const {}})
      : selectedQuestions = List.unmodifiable(selectedQuestions),
        priority = List.unmodifiable(priority),
        _categories = _copy(categories), teams = List.unmodifiable(teams),
        participants = List.unmodifiable(participants),
        fixed = List.unmodifiable(fixed), requiredRoles = List.unmodifiable(requiredRoles),
        privatePreferences = List.unmodifiable(privatePreferences),
        _versions = _copy(versions), _solver = _copy(solver);
  final int schemaVersion;
  final String mode;
  final String method;
  final List<String> selectedQuestions;
  final List<String> priority;
  final Map<String, dynamic> _categories;
  final List<MatchingTeam> teams;
  final List<MatchingParticipant> participants;
  final List<FixedAssignment> fixed;
  final List<RequiredRole> requiredRoles;
  final bool requireCommonTime;
  final List<PrivatePreference> privatePreferences;
  final Map<String, dynamic> _versions;
  final Map<String, dynamic> _solver;
  Map<String, dynamic> get categories => _copy(_categories);
  Map<String, dynamic> get versions => _copy(_versions);
  Map<String, dynamic> get solver => _copy(_solver);
  factory MatchingInput.fromJson(Map<String, dynamic> json) => MatchingInput(
        schemaVersion: json['schema_version'] as int,
        mode: json['mode'] as String, method: json['method'] as String,
        selectedQuestions: _strings(json['selected_questions']),
        priority: _strings(json['priority']), categories: _object(json['categories']),
        teams: (json['teams'] as List).map((e) => MatchingTeam.fromJson(_object(e))).toList(),
        participants: (json['participants'] as List)
            .map((e) => MatchingParticipant.fromJson(_object(e))).toList(),
        fixed: (json['fixed'] as List? ?? [])
            .map((e) => FixedAssignment.fromJson(_object(e))).toList(),
        requiredRoles: (json['required_roles'] as List? ?? [])
            .map((e) => RequiredRole.fromJson(_object(e))).toList(),
        requireCommonTime: json['require_common_time'] as bool? ?? false,
        privatePreferences: (json['private_preferences'] as List? ?? [])
            .map((e) => PrivatePreference.fromJson(_object(e))).toList(),
        versions: _object(json['versions'] ?? {}), solver: _object(json['solver'] ?? {}),
      );
  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion, 'mode': mode, 'method': method,
        'selected_questions': selectedQuestions.toList(), 'priority': priority.toList(),
        'categories': categories, 'teams': teams.map((e) => e.toJson()).toList(),
        'participants': participants.map((e) => e.toJson()).toList(),
        'fixed': fixed.map((e) => e.toJson()).toList(),
        'required_roles': requiredRoles.map((e) => e.toJson()).toList(),
        'require_common_time': requireCommonTime,
        'private_preferences': privatePreferences.map((e) => e.toJson()).toList(),
        'versions': versions, 'solver': solver,
      };
}

class ExperienceMean {
  const ExperienceMean({required this.numerator, required this.denominator});
  final int numerator;
  final int denominator;
  double? get value => denominator == 0 ? null : numerator / denominator;
  factory ExperienceMean.fromJson(Map<String, dynamic> json) => ExperienceMean(
        numerator: json['numerator'] as int, denominator: json['denominator'] as int);
  Map<String, dynamic> toJson() => {'numerator': numerator, 'denominator': denominator};
}

class SelfReportedExperience {
  const SelfReportedExperience({required this.sum, required this.respondents, this.mean});
  final int sum;
  final int respondents;
  final ExperienceMean? mean;
  factory SelfReportedExperience.fromJson(Map<String, dynamic> json) => SelfReportedExperience(
        sum: json['sum'] as int, respondents: json['respondents'] as int,
        mean: json['mean'] == null ? null : ExperienceMean.fromJson(_object(json['mean'])),
      );
  Map<String, dynamic> toJson() => {'sum': sum, 'respondents': respondents, 'mean': mean?.toJson()};
}

// Only public fields are accepted/serialized. Internal scores are never retained.
class MatchingTeamResult {
  MatchingTeamResult({required this.teamId, required List<String> participants,
    required this.size, List<String>? commonTimes,
    Map<String, int>? timeAvailability, Map<String, int>? rolePreferences,
    this.selfReportedExperience, Map<String, int>? interests,
    Map<String, int>? publicLosses})
      : participants = List.unmodifiable(participants),
        commonTimes = commonTimes == null ? null : List.unmodifiable(commonTimes),
        timeAvailability = timeAvailability == null ? null : Map.unmodifiable(timeAvailability),
        rolePreferences = rolePreferences == null ? null : Map.unmodifiable(rolePreferences),
        interests = interests == null ? null : Map.unmodifiable(interests),
        publicLosses = publicLosses == null ? null : Map.unmodifiable(publicLosses);
  final String teamId;
  final List<String> participants;
  final int size;
  final List<String>? commonTimes;
  final Map<String, int>? timeAvailability;
  final Map<String, int>? rolePreferences;
  final SelfReportedExperience? selfReportedExperience;
  final Map<String, int>? interests;
  final Map<String, int>? publicLosses;
  factory MatchingTeamResult.fromJson(Map<String, dynamic> json) => MatchingTeamResult(
        teamId: json['team_id'] as String, participants: _strings(json['participants']),
        size: json['size'] as int,
        commonTimes: json['common_times'] == null ? null : _strings(json['common_times']),
        timeAvailability: json['time_availability'] == null ? null : _counts(json['time_availability']),
        rolePreferences: json['role_preferences'] == null ? null : _counts(json['role_preferences']),
        selfReportedExperience: json['self_reported_experience'] == null ? null
            : SelfReportedExperience.fromJson(_object(json['self_reported_experience'])),
        interests: json['interests'] == null ? null : _counts(json['interests']),
        publicLosses: json['public_losses'] == null ? null : _counts(json['public_losses']),
      );
  Map<String, dynamic> toJson() => {
        'team_id': teamId, 'participants': participants.toList(), 'size': size,
        if (commonTimes != null) 'common_times': commonTimes!.toList(),
        if (timeAvailability != null) 'time_availability': Map<String, int>.from(timeAvailability!),
        if (rolePreferences != null) 'role_preferences': Map<String, int>.from(rolePreferences!),
        if (selfReportedExperience != null) 'self_reported_experience': selfReportedExperience!.toJson(),
        if (interests != null) 'interests': Map<String, int>.from(interests!),
        if (publicLosses != null) 'public_losses': Map<String, int>.from(publicLosses!),
      };
}

class MatchingResult {
  MatchingResult({required this.status, this.label, this.elapsedSeconds,
    List<MatchingTeamResult> teams = const [], List<String> messages = const []})
      : teams = List.unmodifiable(teams), messages = List.unmodifiable(messages);
  final String status;
  final String? label;
  final num? elapsedSeconds;
  final List<MatchingTeamResult> teams;
  final List<String> messages;
  factory MatchingResult.fromJson(Map<String, dynamic> json) => MatchingResult(
        status: json['status'] as String, label: json['label'] as String?,
        elapsedSeconds: json['elapsed_seconds'] as num?,
        teams: (json['teams'] as List? ?? [])
            .map((e) => MatchingTeamResult.fromJson(_object(e))).toList(),
        messages: _strings(json['messages'] ?? []),
      );
  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label, 'status': status,
        if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
        'teams': teams.map((e) => e.toJson()).toList(), 'messages': messages.toList(),
      };
}
