"""편성알고리즘 v3 13-1 사례 1~22를 운영 경로(formation.py, service.py)에서 검증.

번호는 명세 13-1 번호와 같다. Firebase 자격 증명·네트워크 없이 실행된다.
실제 Firestore 트랜잭션(8번)은 tests/test_firestore_emulator.py에서 별도로 검증한다.
"""
import itertools
import unittest
from copy import deepcopy
from unittest import mock

import formation
from formation import Invalid, assess, prepare, solve, VALID
from service import versions
from validated_service import ValidatedFormationService
import test_main_adapter as adapter_tests
from test_stage3_boundary import MemoryRepository

ROLES = ['dev', 'design', 'plan']
TIMES = ['mon', 'wed', 'fri']
INTERESTS = ['web', 'app', 'ai']


def person(pid, role='dev', time=('wed',), exp=3, interest=('web',)):
    return {'id': pid, 'answers': {'role': role, 'time': list(time), 'experience': exp, 'interest': list(interest)}}


def raw(people, caps, selected=('role', 'time', 'experience', 'interest'), **extra):
    selected = list(selected)
    cats = {'role': ROLES, 'time': TIMES, 'interest': INTERESTS}
    out = {'participants': people,
           'teams': [{'id': f'team_{i+1}', 'capacity': c} for i, c in enumerate(caps)],
           'selected_questions': selected, 'priority': selected + ['size'], 'method': 'balanced',
           'categories': {q: cats[q] for q in selected if q != 'experience'}, 'limit': 5}
    out.update(extra)
    return out


def twenty():
    return [person(f'p{i:02d}', ROLES[i % 3], sorted({TIMES[i % 3], 'wed'}), 1 + i % 5, [INTERESTS[i % 3]])
            for i in range(20)]


def keys_of(r):
    """모든 배정을 열거해 유효 후보의 사전식 키를 모은다 (작은 사례 전용)."""
    s = prepare(r)
    ids, tids = [p['id'] for p in s['participants']], [t['id'] for t in s['teams']]
    out = []
    for combo in itertools.product(tids, repeat=len(ids)):
        a = dict(zip(ids, combo))
        _, internal = assess(s, a)
        if internal is not None:
            out.append((internal['key'], a))
    return out


def internal_of(r, assignment):
    return assess(prepare(r), assignment)[1]


class Spec13EngineTests(unittest.TestCase):
    def assertValid(self, result):
        self.assertIn(result['status'], VALID, result.get('internal'))

    def test_01_basic_twenty(self):
        r = raw(twenty(), [5, 5, 5, 5])
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(sorted(result['assignments']), sorted(p['id'] for p in r['participants']))
        sizes = [list(result['assignments'].values()).count(t) for t in ('team_1', 'team_2', 'team_3', 'team_4')]
        self.assertTrue(all(1 <= n <= 5 for n in sizes))
        self.assertTrue(result['requiredStatus']['valid'])

    def test_02_partial_keeps_outside_scope_and_manual_lock(self):
        people = [person(f'p{i}', ROLES[i % 3], exp=1 + i % 5) for i in range(9)]
        published = {f'p{i}': f'team_{i // 3 + 1}' for i in range(9)}
        r = raw(people, [4, 4, 4], published=published, draft=dict(published),
                locks={'p0': {'type': 'manual', 'teamId': 'team_1'}}, scopeTeamIds=['team_1', 'team_2'])
        result = solve(r)
        self.assertValid(result)
        a = result['assignments']
        for i in (6, 7, 8):
            self.assertEqual(a[f'p{i}'], 'team_3')
        self.assertEqual(a['p0'], 'team_1')
        self.assertTrue(all(a[f'p{i}'] in ('team_1', 'team_2') for i in range(6)))

    def test_03_minimum_change_new_participant_fills_open_seat(self):
        people = [person('a0', 'dev'), person('a1', 'design'), person('b0', 'dev'), person('b1', 'design'),
                  person('n0', 'plan'), person('n1', 'plan')]
        published = {'a0': 'team_1', 'a1': 'team_1', 'b0': 'team_2', 'b1': 'team_2'}
        r = raw(people, [3, 3], published=published, draft=dict(published))
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(result['internal']['M_pub'], 0)
        for uid, team in published.items():
            self.assertEqual(result['assignments'][uid], team)
        self.assertEqual(result['internal']['key'], min(k for k, _ in keys_of(r)))

    def test_04_quality_before_draft(self):
        people = [person('a0', 'dev'), person('a1', 'dev'), person('b0', 'design'), person('b1', 'design'),
                  person('n_dev', 'dev'), person('n_des', 'design')]
        published = {'a0': 'team_1', 'a1': 'team_1', 'b0': 'team_2', 'b1': 'team_2'}
        draft = {**published, 'n_dev': 'team_1', 'n_des': 'team_2'}
        r = raw(people, [3, 3], selected=['role'], published=published, draft=draft)
        self.assertIsNotNone(internal_of(r, draft), '초안 자체는 유효해야 한다')
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(result['internal']['M_pub'], internal_of(r, draft)['M_pub'])
        self.assertLess(result['internal']['J_int'], internal_of(r, draft)['J_int'])
        self.assertEqual(result['assignments']['n_dev'], 'team_2')
        self.assertEqual(result['internal']['key'], min(k for k, _ in keys_of(r)))

    def test_05_draft_respected_among_quality_ties(self):
        people = [person('a0', 'dev'), person('a1', 'design'), person('b0', 'dev'), person('b1', 'design'),
                  person('n0', 'plan'), person('n1', 'plan')]
        published = {'a0': 'team_1', 'a1': 'team_1', 'b0': 'team_2', 'b1': 'team_2'}
        draft = {**published, 'n0': 'team_2', 'n1': 'team_1'}
        r = raw(people, [3, 3], published=published, draft=draft)
        best = min(k for k, _ in keys_of(r))
        ties = [a for k, a in keys_of(r) if k[:2] == best[:2]]
        self.assertGreater(len(ties), 1, '같은 공개 이동·품질 후보가 여러 개여야 한다')
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(result['internal']['M_draft'], 0)
        self.assertEqual(result['assignments'], draft)

    def test_06_required_role_conflict_is_infeasible(self):
        people = [person(f'd{i}', 'dev') for i in range(3)] + [person(f'x{i}', 'design') for i in range(5)]
        req = [{'team': f'team_{t}', 'role': 'dev', 'minimum': 1} for t in range(1, 5)]
        result = solve(raw(people, [2, 2, 2, 2], required_roles=req))
        self.assertEqual(result['status'], 'INFEASIBLE')
        self.assertTrue(result['conflicts'])
        self.assertNotIn('assignments', result)

    def test_07_private_preference_blocked_by_lock_does_not_block(self):
        people = [person(f'p{i}', ROLES[i % 3]) for i in range(6)]
        locks = {'p0': {'type': 'manual', 'teamId': 'team_1'}, 'p1': {'type': 'manual', 'teamId': 'team_1'}}
        prefs = [{'source': 'p0', 'target': 'p1', 'confirmed': True}]
        result = solve(raw(people, [3, 3], locks=locks, private_preferences=prefs))
        self.assertValid(result)
        self.assertEqual(result['internal']['V'], 1)
        self.assertTrue(result['requiredStatus']['valid'])

    def test_13_reproducible(self):
        r = raw(twenty(), [5, 5, 5, 5])
        first, second = solve(deepcopy(r)), solve(deepcopy(r))
        self.assertEqual(first['assignments'], second['assignments'])
        self.assertEqual(first['internal']['key'], second['internal']['key'])

    def sixty(self):
        return [person(f'p{i:02d}', ROLES[i % 3], sorted({TIMES[i % 3], TIMES[(i + 1) % 3]}), 1 + (i * 3) % 5,
                       [INTERESTS[(i * 5) % 3]]) for i in range(60)]

    def test_09_limit_without_candidate_is_not_conflict(self):
        result = solve(raw(self.sixty(), [5] * 12, limit=0.05))
        self.assertEqual(result['status'], 'LIMIT_NO_CANDIDATE')
        self.assertEqual(result['conflicts'], [])
        self.assertNotIn('assignments', result)

    def test_14_feasible_stage_never_reported_optimal(self):
        result = solve(raw(self.sixty(), [5] * 12, limit=0.5))
        self.assertValid(result)
        self.assertFalse(result['stageProof']['quality'])
        self.assertEqual(result['status'], 'FEASIBLE')

    def test_14b_status_matches_stage_proofs(self):
        for r in (raw(twenty(), [5, 5, 5, 5], limit=0.05), raw(twenty()[:6], [3, 3])):
            result = solve(r)
            self.assertValid(result)
            proven = all(result['stageProof'][p] for p in (['pub', 'quality', 'draft'] if r.get('published') else ['quality']))
            self.assertEqual(result['status'] == 'OPTIMAL', proven)

    def test_15_and_21a_limit_in_later_stage_keeps_incumbent(self):
        real = formation.cp.CpSolver
        calls = []

        class LaterStagesHitLimit:
            def __init__(self):
                self.inner = real()
                self.parameters = self.inner.parameters
            def solve(self, model, callback=None):
                calls.append(1)
                if len(calls) == 1:
                    return self.inner.solve(model, callback)
                return formation.cp.UNKNOWN
            def status_name(self, status):
                return self.inner.status_name(status)
            best_objective_bound = 0
            objective_value = 0

        people = [person(f'p{i}', ROLES[i % 3]) for i in range(6)]
        published = {f'p{i}': f'team_{i % 2 + 1}' for i in range(4)}
        with mock.patch.object(formation.cp, 'CpSolver', LaterStagesHitLimit):
            result = solve(raw(people, [3, 3], published=published, draft=dict(published)))
        self.assertEqual(len(calls), 3)
        self.assertEqual(result['status'], 'FEASIBLE')
        self.assertTrue(result['stageProof']['pub'])
        self.assertFalse(result['stageProof']['quality'])
        self.assertIn('assignments', result)

    def test_16_private_loss_not_saturated(self):
        people, prefs = [], []
        for t in range(6):
            tri = [f't{t}_{k}' for k in range(3)]
            people += [person(p) for p in tri]
            prefs += [{'source': tri[k], 'target': tri[(k + 1) % 3], 'confirmed': True} for k in range(3)]
        people += [person('e0'), person('e1')]
        r = raw(people, [10, 10], selected=[], private_preferences=prefs, categories={})
        split = {}
        for t in range(6):
            first, second = ('team_1', 'team_2') if t < 3 else ('team_2', 'team_1')
            split.update({f't{t}_0': first, f't{t}_1': first, f't{t}_2': second})
        v6 = {**split, 'e0': 'team_1', 'e1': 'team_2'}
        v10 = dict(v6)
        for t in (0, 3):
            for k in range(3):
                v10[f't{t}_{k}'] = 'team_1' if t == 0 else 'team_2'
        a6, a10 = internal_of(r, v6), internal_of(r, v10)
        self.assertEqual((a6['V'], a10['V']), (6, 10))
        self.assertLess(a6['J_int'], a10['J_int'])
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(result['internal']['V'], 6)

    def test_17_scoring_infeasible_but_diagnostic_feasible_is_error(self):
        real_build = formation.build

        def broken(s, scoring=True, diagnostic=False):
            model, x, obj, labels = real_build(s, scoring, diagnostic)
            if scoring:
                first = s['participants'][0]['id']
                model.add(sum(x[first, t['id']] for t in s['teams']) == 2)
            return model, x, obj, labels

        with mock.patch.object(formation, 'build', broken):
            result = solve(raw(twenty()[:6], [3, 3]))
        self.assertEqual(result['status'], 'ERROR')
        self.assertNotIn('assignments', result)

    def test_18_final_candidate_not_worse_than_any_stage_candidate(self):
        seen = []
        real_assess = formation.assess

        def recording(s, assignment):
            pub, internal = real_assess(s, assignment)
            if internal is not None:
                seen.append(internal['key'])
            return pub, internal

        people = [person(f'p{i:02d}', ROLES[i % 3], [TIMES[i % 3]], 1 + i % 5) for i in range(16)]
        published = {f'p{i:02d}': f'team_{i % 4 + 1}' for i in range(12)}
        draft = {**published, 'p12': 'team_1', 'p13': 'team_2', 'p14': 'team_3', 'p15': 'team_4'}
        with mock.patch.object(formation, 'assess', recording):
            result = solve(raw(people, [4, 4, 4, 4], published=published, draft=draft, limit=0.3))
        self.assertValid(result)
        self.assertGreater(len(seen), 1)
        self.assertEqual(result['internal']['key'], min(seen))

    def test_18b_small_instance_matches_exhaustive_lexicographic_optimum(self):
        people = [person('a0', 'dev', exp=1), person('a1', 'design', exp=5), person('b0', 'dev', exp=2),
                  person('b1', 'plan', exp=4), person('n0', 'design', exp=3), person('n1', 'dev', exp=3)]
        published = {'a0': 'team_1', 'a1': 'team_1', 'b0': 'team_2', 'b1': 'team_2'}
        draft = {**published, 'n0': 'team_1', 'n1': 'team_2'}
        r = raw(people, [3, 3], published=published, draft=draft)
        result = solve(r)
        self.assertEqual(result['status'], 'OPTIMAL')
        self.assertEqual(result['internal']['key'], min(k for k, _ in keys_of(r)))

    def test_19_zero_move_policy_keeps_valid_publication(self):
        people = [person('a0', 'dev'), person('a1', 'dev'), person('b0', 'design'), person('b1', 'design')]
        published = {'a0': 'team_1', 'a1': 'team_1', 'b0': 'team_2', 'b1': 'team_2'}
        r = raw(people, [2, 2], selected=['role'], published=published, draft=dict(published))
        swapped = {'a0': 'team_1', 'b0': 'team_1', 'a1': 'team_2', 'b1': 'team_2'}
        self.assertLess(internal_of(r, swapped)['J_int'], internal_of(r, published)['J_int'])
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(result['assignments'], published)
        self.assertEqual(result['internal']['M_pub'], 0)

    def test_20_uncapped_team_is_not_hidden_capacity(self):
        people = [person(f'p{i}', ROLES[i % 3]) for i in range(6)]
        result = solve(raw(people, [None, 1]))
        self.assertValid(result)
        self.assertEqual(list(result['assignments'].values()).count('team_1'), 5)

    def test_21b_solver_exception_blocks_candidate(self):
        with mock.patch.object(formation, 'build', side_effect=RuntimeError('boom')):
            result = solve(raw(twenty()[:6], [3, 3]))
        self.assertEqual(result['status'], 'ERROR')
        self.assertNotIn('assignments', result)

    def test_21c_verifier_mismatch_blocks_candidate(self):
        real_assess = formation.assess

        def lying(s, assignment):
            pub, internal = real_assess(s, assignment)
            if internal is not None:
                internal = {**internal, 'J_int': internal['J_int'] + 1}
            return pub, internal

        with mock.patch.object(formation, 'assess', lying):
            result = solve(raw(twenty()[:6], [3, 3]))
        self.assertEqual(result['status'], 'ERROR')
        self.assertNotIn('assignments', result)

    def test_22_team_add_delete_keeps_ids(self):
        people = [person(f'p{i}', ROLES[i % 3]) for i in range(6)]
        published = {f'p{i}': f'team_{i // 2 + 1}' for i in range(6)}
        r = raw(people, [3, 3, 3], published=published, draft=dict(published))
        r['teams'] = [{'id': 'team_1', 'capacity': 3}, {'id': 'team_2', 'capacity': 3}, {'id': 'team_4', 'capacity': 3}]
        result = solve(r)
        self.assertValid(result)
        self.assertEqual(set(result['publicSummary']), {'team_1', 'team_2', 'team_4'})
        self.assertGreaterEqual(result['internal']['M_pub'], 2)
        for i in range(4):
            self.assertEqual(result['assignments'][f'p{i}'], published[f'p{i}'])

    def test_22b_manual_lock_on_deleted_team_is_conflict(self):
        people = [person(f'p{i}', ROLES[i % 3]) for i in range(6)]
        published = {f'p{i}': f'team_{i // 2 + 1}' for i in range(6)}
        r = raw(people, [3, 3, 3], published=published, draft=dict(published),
                locks={'p4': {'type': 'manual', 'teamId': 'team_3'}})
        r['teams'] = r['teams'][:2]
        with self.assertRaisesRegex(Invalid, '삭제할 팀의 수동 고정'):
            prepare(r)

    def test_weights_times_ten_same_result(self):
        r = raw(twenty(), [5, 5, 5, 5])
        base = solve(deepcopy(r))
        real_prepare = formation.prepare

        def scaled(value):
            s = real_prepare(value)
            s['weights'] = {q: 10 * w for q, w in s['weights'].items()}
            return s

        with mock.patch.object(formation, 'prepare', scaled):
            times_ten = solve(deepcopy(r))
        self.assertValid(base)
        self.assertEqual(base['assignments'], times_ten['assignments'])


class Spec13ServiceTests(unittest.TestCase):
    """서비스 경로: 정원·초안·공개·노출 금지 (8~12, 19, 22와 가이드 3단계 기준)."""
    def setUp(self):
        _, _, state = adapter_tests.MainAdapterTests().adapter()
        self.repo = MemoryRepository(state)
        self.service = ValidatedFormationService(self.repo)

    def body(self, **patch):
        current = versions(self.repo.state)
        return {'groupId': 'g', 'activityId': 'a', 'kind': 'initial', 'limit': 2,
                'expected': {k: current[k] for k in ('roster', 'settings', 'draft')}, **patch}

    def add_applicant(self, uid, role='dev'):
        s = self.repo.state
        s['members'][uid] = {'role': 'participant', 'status': 'active', 'nickname': uid}
        app = deepcopy(s['applications']['u0'])
        app['answers']['role']['value'] = role
        s['applications'][uid] = app
        s['activity']['rosterVersion'] = f"{s['activity']['rosterVersion']}+{uid}"

    def publish_current_draft(self):
        return self.service.invoke('publish', 'operator', self.body())

    def test_07_service_lock_with_private_preference_still_publishes(self):
        first = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(first['applied'])
        a = self.repo.state['draft']['assignments']
        mate = next(u for u, t in a.items() if t == a['u0'] and u != 'u0')
        self.service.invoke('edit', 'operator', self.body(operations=[
            {'type': 'lock', 'uid': 'u0'}, {'type': 'lock', 'uid': mate}]))
        self.repo.state['preferences'] = {'p': {'ownerUid': 'u0', 'targetUid': mate, 'status': 'active'}}
        second = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(second['applied'])
        self.assertEqual(self.repo.state['draft']['assignments'][mate], self.repo.state['draft']['assignments']['u0'])
        self.assertIn('publishedVersionId', self.publish_current_draft())

    def test_10_manual_edit_recomputes_public_metrics_and_required_status(self):
        self.repo.state['activity']['extraRequirements'] = [
            {'type': 'requiredRole', 'teamId': 'team_1', 'role': 'dev', 'minimum': 1}]
        self.service.invoke('run', 'operator', self.body())
        a = self.repo.state['draft']['assignments']
        apps = self.repo.state['applications']
        role = {u: apps[u]['answers']['role']['value'] for u in a}
        devs_t1 = [u for u in a if a[u] == 'team_1' and role[u] == 'dev']
        designers_t2 = [u for u in a if a[u] == 'team_2' and role[u] == 'design']
        self.assertEqual(len(devs_t1), 1, '균형 편성은 1팀에 개발 1명')
        edited = self.service.invoke('edit', 'operator', self.body(operations=[
            {'type': 'swap', 'uid': devs_t1[0], 'otherUid': designers_t2[0]}]))
        self.assertFalse(edited['requiredStatus']['valid'])
        self.assertEqual(edited['publicSummary']['team_1']['rolePreferences']['dev'], 0)
        self.assertEqual(sorted(edited['publicSummary']['team_1']['members']),
                         sorted(u for u, t in self.repo.state['draft']['assignments'].items() if t == 'team_1'))
        with self.assertRaisesRegex(Invalid, '필수 조건'):
            self.publish_current_draft()

    def recruiting_without_capacity(self):
        s = self.repo.state['activity']
        s.update(state='recruiting', capacity={'team_1': None, 'team_2': None}, capacityInitialized=False)
        self.add_applicant('u4')

    def test_11_default_capacity_is_upper_bound_ceil_n_over_k(self):
        self.recruiting_without_capacity()
        self.service.invoke('close', 'operator', self.body())
        self.assertEqual(self.repo.state['activity']['capacity'], {'team_1': 3, 'team_2': 3})
        result = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(result['applied'])
        sizes = [s['size'] for s in result['publicSummary'].values()]
        self.assertTrue(all(n <= 3 for n in sizes))

    def test_12_capacity_not_changed_when_roster_grows(self):
        self.recruiting_without_capacity()
        self.service.invoke('close', 'operator', self.body())
        self.add_applicant('u5'); self.add_applicant('u6', 'design')
        self.assertEqual(self.repo.state['activity']['capacity'], {'team_1': 3, 'team_2': 3})
        check = self.service.invoke('precheck', 'operator', self.body())
        self.assertFalse(check['valid'])
        self.assertIn('전체 최대 정원이 부족합니다', check['conflicts'])
        result = self.service.invoke('run', 'operator', self.body())
        self.assertEqual(result['status'], 'INFEASIBLE')
        self.assertFalse(result['applied'])
        self.assertEqual(self.repo.state['activity']['capacity'], {'team_1': 3, 'team_2': 3})

    def publish_initial(self):
        self.service.invoke('run', 'operator', self.body())
        out = self.publish_current_draft()
        s = self.repo.state
        s['published'] = {}
        for path, doc in self.repo.documents.items():
            if path.startswith(f"groups/g/activities/a/teamVersions/{out['publishedVersionId']}/teams/"):
                for uid in doc['members']:
                    s['published'][uid] = path.rsplit('/', 1)[1]
        s['activity'].update(publishedVersionId=out['publishedVersionId'], state='published')
        return out

    def test_19_zero_move_notice(self):
        self.publish_initial()
        self.add_applicant('u4', 'design')
        self.repo.state['activity']['capacity'] = {'team_1': 3, 'team_2': 3}
        result = self.service.invoke('run', 'operator', self.body(kind='republish'))
        self.assertTrue(result['applied'])
        self.assertEqual(result['movementSummary']['publishedMoved'], 0)
        self.assertIn('기존 팀원은 이동하지 않았습니다', result['notice'])

    def test_20_precheck_with_uncapped_team(self):
        self.repo.state['activity']['capacity'] = {'team_1': None, 'team_2': 1}
        check = self.service.invoke('precheck', 'operator', self.body())
        self.assertTrue(check['valid'], check)
        result = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(result['applied'])
        self.assertEqual(result['publicSummary']['team_1']['size'], 3)

    def test_22_deleted_team_moves_reported_and_locks_conflict(self):
        self.publish_initial()
        s = self.repo.state
        s['activity'].update(teamIds=['team_1', 'team_3'], capacity={'team_1': 2, 'team_3': 2})
        s['activity']['settingsVersion'] += 1
        result = self.service.invoke('run', 'operator', self.body(kind='republish'))
        self.assertTrue(result['applied'])
        self.assertEqual(result['movementSummary']['deletedTeamMoved'], 2)
        self.assertEqual(set(result['publicSummary']), {'team_1', 'team_3'})
        moved_team2 = [u for u, t in s['published'].items() if t == 'team_2']
        s['draft'] = {'version': s['draft'].get('version', 0), 'assignments': dict(s['published']),
                      'locks': {moved_team2[0]: {'type': 'manual', 'teamId': 'team_2'}}}
        with self.assertRaisesRegex(Invalid, '삭제할 팀의 수동 고정'):
            self.service.invoke('run', 'operator', self.body(kind='republish'))

    def test_precheck_available_while_recruiting(self):
        self.repo.state['activity']['state'] = 'recruiting'
        check = self.service.invoke('precheck', 'operator', self.body())
        self.assertIn('roster', check['versions'])
        self.repo.state['activity']['state'] = 'ended'
        with self.assertRaises(Invalid):
            self.service.invoke('precheck', 'operator', self.body())

    def test_precheck_role_shortage(self):
        self.repo.state['activity']['extraRequirements'] = [
            {'type': 'requiredRole', 'teamId': t, 'role': 'dev', 'minimum': 2} for t in ('team_1', 'team_2')]
        check = self.service.invoke('precheck', 'operator', self.body())
        self.assertFalse(check['valid'])
        self.assertIn('dev 역할 희망자는 2명인데 필수 역할 최소 인원 합은 4명입니다', check['conflicts'])

    def test_precheck_scope_seats(self):
        self.publish_initial()
        self.add_applicant('u4', 'design')
        check = self.service.invoke('precheck', 'operator', self.body(kind='partial', scopeTeamIds=['team_1']))
        self.assertFalse(check['valid'])
        self.assertIn('선택한 팀의 남은 자리는 2개인데 새로 배정할 참가자는 3명입니다', check['conflicts'])

    def test_private_values_never_reach_operator_records(self):
        self.repo.state['preferences'] = {'p': {'ownerUid': 'u0', 'targetUid': 'u1', 'status': 'active'}}
        response = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(response['applied'])
        operator_visible = [response] + [v for k, v in self.repo.documents.items() if not k.startswith('serverRuns/')]
        forbidden = ('J_int', "'V'", "'P'", 'private_preferences', 'edges', 'prefVersion', 'targetUid', 'ownerUid')
        for doc in operator_visible:
            text = str(doc)
            for word in forbidden:
                self.assertNotIn(word, text)
        server = str([v for k, v in self.repo.documents.items() if k.startswith('serverRuns/')])
        self.assertIn('J_int', server)
        self.assertIn('private_preferences', server)


if __name__ == '__main__':
    unittest.main()
