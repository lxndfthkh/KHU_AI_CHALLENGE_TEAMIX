import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/formation.dart';
import '../services/formation_api.dart';

/// Operator team formation (팀편성흐름 v4 ①~④). Mutations go to the
/// formation server (algorithm/server_v3.py), which checks roles and versions;
/// the draft is read back from Firestore (`drafts/{a}`, admin only).
abstract interface class FormationBackend {
  Stream<FormationDraft?> draft(String activityId);

  /// userId -> display name for the group's approved members.
  Future<Map<String, String>> memberNames(String groupId);

  /// Pre-check problems (empty when ready), v4 ① 설정 검증.
  Future<List<String>> precheck(String groupId, String activityId);
  Future<FormationOutcome> closeRecruitment(String groupId, String activityId);
  Future<FormationOutcome> generate(
    String groupId,
    String activityId, {
    required bool republish,
  });

  /// Moves a member to a team, or to unassigned with a null [teamId].
  Future<FormationOutcome> move(
    String groupId,
    String activityId,
    String userId,
    String? teamId,
  );
  Future<FormationOutcome> publish(String groupId, String activityId);

  // v4 ① settings (before publishing).
  Stream<FormationSettings?> settings(String activityId);

  /// Whether learning is applied, and per-criterion up/down/same (never the
  /// numbers behind them).
  Future<(bool, Map<String, String>)> learning(
    String groupId,
    String activityId,
  );
  Future<FormationOutcome> saveSettings(
    String groupId,
    String activityId,
    FormationSettingsPatch patch,
  );

  // v4 ③ review tools.
  Future<FormationOutcome> setLocked(
    String groupId,
    String activityId,
    String userId, {
    required bool locked,
  });

  /// Re-forms only [teamIds] after publishing; others stay as they are.
  Future<FormationOutcome> generatePartial(
    String groupId,
    String activityId,
    List<String> teamIds,
  );

  /// Drops the post-publish edit draft; the published teams stay.
  Future<FormationOutcome> discardDraft(String groupId, String activityId);
}

class ServerFormationBackend implements FormationBackend {
  ServerFormationBackend(this._db, this._api);

  final FirebaseFirestore _db;
  final FormationApi _api;

  static const _stale = FormationOutcome(
    false,
    '그 사이 신청·설정·초안이 바뀌었어요. 최신 상태로 다시 시도해 주세요.',
  );

  @override
  Stream<FormationDraft?> draft(String activityId) => _db
      .doc('drafts/$activityId')
      .snapshots()
      .map((d) => d.exists ? FormationDraft.fromFirestore(d.data()!) : null);

  @override
  Future<Map<String, String>> memberNames(String groupId) async {
    final s = await _db
        .collection('memberships')
        .where('groupId', isEqualTo: groupId)
        .get();
    return {
      for (final d in s.docs)
        if (d.data()['userId'] is String)
          d.data()['userId'] as String:
              d.data()['displayName'] as String? ?? '이름 없음',
    };
  }

  @override
  Future<List<String>> precheck(String groupId, String activityId) async {
    final r = await _api.request(
      'precheck',
      groupId: groupId,
      activityId: activityId,
    );
    return [for (final c in (r['conflicts'] as List?) ?? const []) '$c'];
  }

  /// Every mutation names the versions it was based on; the server refuses
  /// (STALE) if anything changed in between (v4 ② 실행 기준, ④ 검토 후 변경).
  Future<Map<String, dynamic>> _mutate(
    String route,
    String groupId,
    String activityId, [
    Map<String, dynamic> options = const {},
  ]) async {
    final check = await _api.request(
      'precheck',
      groupId: groupId,
      activityId: activityId,
    );
    final versions = Map<String, Object>.from(check['versions'] as Map);
    return _api.request(
      route,
      groupId: groupId,
      activityId: activityId,
      expected: versions,
      options: options,
    );
  }

  Future<FormationOutcome> _guard(
    Future<FormationOutcome> Function() action,
  ) async {
    try {
      return await action();
    } catch (_) {
      return const FormationOutcome(
        false,
        '요청을 처리하지 못했어요. 상태를 확인하고 다시 시도해 주세요.',
      );
    }
  }

  @override
  Future<FormationOutcome> closeRecruitment(
    String groupId,
    String activityId,
  ) => _guard(() async {
    final r = await _mutate('closeRecruitment', groupId, activityId);
    if (r['status'] == 'STALE') return _stale;
    return const FormationOutcome(true, '신청을 마감했어요. 이제 팀을 편성할 수 있어요.');
  });

  @override
  Future<FormationOutcome> generate(
    String groupId,
    String activityId, {
    required bool republish,
  }) => _guard(() async {
    final r = await _mutate('generateDraft', groupId, activityId, {
      'kind': republish ? 'republish' : 'initial',
    });
    return _runOutcome(r);
  });

  FormationOutcome _runOutcome(Map<String, dynamic> r) => switch (r['status']) {
    'OPTIMAL' || 'FEASIBLE' => FormationOutcome(
      true,
      r['notice'] as String? ?? '추천 편성안을 만들었어요. 검토 후 공개해 주세요.',
    ),
    'STALE' => _stale,
    'INFEASIBLE' => FormationOutcome(
      false,
      '조건을 모두 만족하는 편성이 없어요. '
      '${[for (final c in (r['conflicts'] as List?) ?? const []) '$c'].join(', ')}',
    ),
    'LIMIT_NO_CANDIDATE' => const FormationOutcome(
      false,
      '시간 안에 편성안을 찾지 못했어요. 다시 시도하거나 직접 옮겨 편성해 주세요.',
    ),
    _ => const FormationOutcome(false, '편성 중 오류가 났어요. 기존 초안은 그대로예요.'),
  };

  @override
  Future<FormationOutcome> move(
    String groupId,
    String activityId,
    String userId,
    String? teamId,
  ) => _guard(() async {
    // After publishing everyone starts pinned to their team; an explicit
    // move by the operator unpins that one member first.
    final r = await _mutate('moveMember', groupId, activityId, {
      'operations': [
        {'type': 'unlock', 'uid': userId},
        {'type': 'move', 'uid': userId, 'teamId': teamId},
      ],
    });
    if (r['status'] == 'STALE') return _stale;
    return const FormationOutcome(true, '옮겼어요.');
  });

  @override
  Stream<FormationSettings?> settings(String activityId) => _db
      .doc('activities/$activityId/settings/matching')
      .snapshots()
      .map((d) => d.exists ? FormationSettings.fromFirestore(d.data()!) : null);

  @override
  Future<(bool, Map<String, String>)> learning(
    String groupId,
    String activityId,
  ) async {
    final r = await _api.request(
      'precheck',
      groupId: groupId,
      activityId: activityId,
    );
    final l = (r['learning'] as Map?) ?? const {};
    return (
      l['enabled'] != false,
      {
        for (final e in ((l['directions'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
    );
  }

  @override
  Future<FormationOutcome> saveSettings(
    String groupId,
    String activityId,
    FormationSettingsPatch patch,
  ) => _guard(() async {
    final r = await _mutate('updateMatchingSettings', groupId, activityId, {
      'patch': patch.toJson(),
    });
    if (r['status'] == 'STALE') return _stale;
    return const FormationOutcome(true, '편성 설정을 저장했어요.');
  });

  @override
  Future<FormationOutcome> setLocked(
    String groupId,
    String activityId,
    String userId, {
    required bool locked,
  }) => _guard(() async {
    final r = await _mutate('moveMember', groupId, activityId, {
      'operations': [
        {'type': locked ? 'lock' : 'unlock', 'uid': userId},
      ],
    });
    if (r['status'] == 'STALE') return _stale;
    return FormationOutcome(true, locked ? '이 팀에 고정했어요.' : '고정을 풀었어요.');
  });

  @override
  Future<FormationOutcome> generatePartial(
    String groupId,
    String activityId,
    List<String> teamIds,
  ) => _guard(() async {
    final r = await _mutate('generateDraft', groupId, activityId, {
      'kind': 'partial',
      'scopeTeamIds': teamIds,
    });
    return _runOutcome(r);
  });

  @override
  Future<FormationOutcome> discardDraft(String groupId, String activityId) =>
      _guard(() async {
        final r = await _mutate('discardDraft', groupId, activityId);
        if (r['status'] == 'STALE') return _stale;
        return const FormationOutcome(true, '수정 초안을 버렸어요. 공개된 팀은 그대로예요.');
      });

  @override
  Future<FormationOutcome> publish(String groupId, String activityId) =>
      _guard(() async {
        final r = await _mutate('publishTeams', groupId, activityId);
        if (r['status'] == 'STALE') return _stale;
        return const FormationOutcome(true, '팀을 공개했어요. 참가자에게 알림이 가요.');
      });
}
