import 'package:firebase_auth/firebase_auth.dart';

import '../services/formation_api.dart';
import 'feedback_learning_api.dart';

/// Latest training run as the formation server reports it (learning_api.py).
class LearningRun {
  const LearningRun({
    required this.status,
    this.modelId,
    this.modelStatus,
    this.rowCount = 0,
    this.activityCount = 0,
    this.rmse = const {},
    this.b = const {},
    this.trainedAt,
  });

  factory LearningRun.fromJson(Map<String, dynamic> j) => LearningRun(
    status: j['status'] as String? ?? '',
    modelId: j['modelId'] as String?,
    modelStatus: j['modelStatus'] as String?,
    rowCount: (j['rowCount'] as num?)?.toInt() ?? 0,
    activityCount: (j['activityCount'] as num?)?.toInt() ?? 0,
    rmse: _doubles(j['rmse']),
    b: _doubles(j['b']),
    trainedAt: DateTime.tryParse(j['trainedAt'] as String? ?? '')?.toLocal(),
  );

  /// candidate | not_better_than_baselines | insufficient_data | failed_reformation_check
  final String status;
  final String? modelId;

  /// candidate | approved | active | retired; null when no model was saved.
  final String? modelStatus;
  final int rowCount, activityCount;

  /// model, baseline_mean, baseline_weighted_loss.
  final Map<String, double> rmse;

  /// Per-criterion multipliers (time, role, experience, interest, size).
  final Map<String, double> b;
  final DateTime? trainedAt;
}

Map<String, double> _doubles(Object? m) => {
  if (m is Map)
    for (final e in m.entries)
      if (e.value is num) '${e.key}': (e.value as num).toDouble(),
};

/// A subgroup the comparison can form (recruitment closed).
class CompareTarget {
  const CompareTarget({
    required this.groupId,
    required this.activityId,
    required this.title,
    this.groupName = '',
  });

  factory CompareTarget.fromJson(Map<String, dynamic> j) => CompareTarget(
    groupId: '${j['groupId']}',
    activityId: '${j['activityId']}',
    title: j['title'] as String? ?? '',
    groupName: j['groupName'] as String? ?? '',
  );

  final String groupId, activityId, title, groupName;

  // Each status reload makes new objects; the dropdown matches by subgroup.
  @override
  bool operator ==(Object other) =>
      other is CompareTarget &&
      other.groupId == groupId &&
      other.activityId == activityId;

  @override
  int get hashCode => Object.hash(groupId, activityId);
}

class CompareTeam {
  const CompareTeam(this.members, this.commonTimes);

  factory CompareTeam.fromJson(Map<String, dynamic> j) => CompareTeam(
    [for (final m in (j['members'] as List?) ?? const []) '$m'],
    [for (final t in (j['commonTimes'] as List?) ?? const []) '$t'],
  );

  final List<String> members, commonTimes;
}

/// One roster formed with default weights and with the latest model.
class FormationCompare {
  const FormationCompare({
    required this.before,
    required this.after,
    this.modelId,
    this.b = const {},
  });

  factory FormationCompare.fromJson(Map<String, dynamic> j) {
    List<CompareTeam> teams(Object? side) => [
      if (side is Map)
        for (final t in (side['teams'] as List?) ?? const [])
          CompareTeam.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    return FormationCompare(
      before: teams(j['before']),
      after: teams(j['after']),
      modelId: j['modelId'] as String?,
      b: _doubles(j['b']),
    );
  }

  final List<CompareTeam> before, after;
  final String? modelId;
  final Map<String, double> b;
}

class LearningStatus {
  const LearningStatus({
    this.activeModelId,
    this.activeB = const {},
    this.latest,
    this.targets = const [],
  });

  factory LearningStatus.fromJson(Map<String, dynamic> j) {
    final active = j['active'];
    return LearningStatus(
      activeModelId: active is Map ? active['modelId'] as String? : null,
      activeB: active is Map ? _doubles(active['b']) : const {},
      latest: j['latest'] is Map
          ? LearningRun.fromJson(Map<String, dynamic>.from(j['latest'] as Map))
          : null,
      targets: [
        for (final t in (j['targets'] as List?) ?? const [])
          CompareTarget.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
    );
  }

  /// Null means the engine uses default weights (every b = 1).
  final String? activeModelId;
  final Map<String, double> activeB;
  final LearningRun? latest;

  /// Subgroups the before/after comparison can use.
  final List<CompareTarget> targets;
}

/// Service admin learning controls: train on demand, then apply or reset.
abstract interface class LearningAdmin {
  /// True only for the Auth custom claim admin: true.
  Future<bool> isServiceAdmin();
  Future<LearningStatus> status();

  /// Extracts closed feedback and trains; a passing model is saved as a candidate.
  Future<LearningStatus> train();

  /// Forms [target]'s roster with default weights and with the latest model.
  /// Nothing is saved.
  Future<FormationCompare> compare(CompareTarget target);

  /// approveModel + activateModel: formation uses the model's b from now on.
  Future<void> apply(String modelId);

  /// deactivateModel: back to default weights.
  Future<void> reset();
}

class ServerLearningAdmin implements LearningAdmin {
  ServerLearningAdmin(this._formation, this._functions, {FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FormationApi _formation;
  final FeedbackLearningApi _functions;
  final FirebaseAuth _auth;

  @override
  Future<bool> isServiceAdmin() async {
    final result = await _auth.currentUser?.getIdTokenResult();
    return result?.claims?['admin'] == true;
  }

  @override
  Future<LearningStatus> status() async =>
      LearningStatus.fromJson(await _formation.learning('status'));

  @override
  Future<LearningStatus> train() async =>
      LearningStatus.fromJson(await _formation.learning('train'));

  @override
  Future<FormationCompare> compare(CompareTarget target) async =>
      FormationCompare.fromJson(
        await _formation.learning('compare', {
          'groupId': target.groupId,
          'activityId': target.activityId,
        }),
      );

  @override
  Future<void> apply(String modelId) async {
    await _functions.call('approveModel', {'modelId': modelId});
    await _functions.call('activateModel', {'modelId': modelId});
  }

  @override
  Future<void> reset() => _functions.call('deactivateModel', {});
}
