import copy
import json
import math
import random
from pathlib import Path
import unittest
from unittest.mock import patch
from teamix_engine import solve, run_precheck, evaluate
from teamix_engine.engine import run_stage, ZERO_MOVE_NOTICE, UNPROVEN_MOVE_NOTICE, GENERIC_ERROR
from teamix_engine.schema import normalize, preflight, upper_bounds, weights
from teamix_engine.scoring import tables, verify, size_loss, TableTooLarge

BASE = json.loads((Path(__file__).resolve().parents[1]/"examples/initial_20.json").read_text())
IDS = [p['id'] for p in BASE['participants']]
TEAMS = [t['id'] for t in BASE['teams']]


def republish_case(new=4, limit=10):
    """16명 공개(팀당 4명, 정원 5) + 신규 4명."""
    s = copy.deepcopy(BASE)
    s['mode'] = 'republish'
    s['published'] = {'team_ids': TEAMS,
                      'assignments': {i: TEAMS[k % 4] for k, i in enumerate(IDS[:20-new])}}
    s['solver']['max_deterministic_time'] = limit
    return s


def tiny(roles, method='balanced', teams=2):
    """역할 질문만 있는 작은 입력."""
    return {'mode': 'initial', 'method': method, 'selected_questions': ['role'],
            'priority': ['role', 'size'], 'categories': {'role': ['기획', '개발']},
            'teams': [{'id': f't{k}', 'capacity': None} for k in range(1, teams+1)],
            'participants': [{'id': f'p{k}', 'answers': {'role': r}} for k, r in enumerate(roles)],
            'solver': {'seed': 42, 'max_deterministic_time': 5}}


def fake_found(s_raw, assignment):
    """Solver-consistent candidate built from the verifier (for injected stage runners)."""
    n = normalize(copy.deepcopy(s_raw))
    v = verify(n, assignment)
    g = math.gcd(*n['weights'].values())  # 솔버는 공약수로 나눈 가중치를 쓴다
    values = {'J': v['J_int']//g, 'V': v['V'], 'F_int': v['F_int']//g, 'M_pub': v['M_pub'],
              'M_draft': v['M_draft'],
              'items': {t: dict(v['losses'][t]['items']) for t in n['tids']}}
    return (assignment, values)


class EngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.demo = solve(BASE)
        cls.republished = solve(republish_case())

    # ---- 13-1 #1 기본 편성
    def test_01_basic_twenty(self):
        r = self.demo
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        ids = [i for t in r['public']['teams'] for i in t['participants']]
        self.assertEqual(len(ids), 20)
        self.assertEqual(len(set(ids)), 20)
        for forbidden in ['"V"', '"P"', '"J_int"', 'private_preferences', 'incumbent']:
            self.assertNotIn(forbidden, json.dumps(r['public']))
        verified = verify(normalize(BASE), r['internal']['assignment'])
        self.assertEqual(verified['J_int'], r['internal']['J_int'])
        self.assertEqual(r['public']['kind'], 'initial')
        self.assertEqual(r['public']['stage_proof']['pub'], None)

    # ---- #2 부분 재편성
    def test_02_partial_keeps_outside_and_manual_locks(self):
        s = copy.deepcopy(BASE)
        draft = {i: TEAMS[k % 4] for k, i in enumerate(IDS)}
        manual = next(i for i in IDS if draft[i] == 'team_3')
        s['draft'] = {'assignments': draft, 'locks': {manual: {'team': 'team_3', 'type': 'manual'}}}
        s['scope_team_ids'] = ['team_3', 'team_4']
        r = solve(s)
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        self.assertEqual(r['public']['kind'], 'partial')
        a = r['internal']['assignment']
        for i in IDS:
            if draft[i] in ('team_1', 'team_2'):
                self.assertEqual(a[i], draft[i])
            else:
                self.assertIn(a[i], ('team_3', 'team_4'))
        self.assertEqual(a[manual], 'team_3')

    # ---- #3·#19 최소 변경 / 이동 0명 정책
    def test_03_19_new_participants_fill_without_moving_others(self):
        r = self.republished
        self.assertEqual(r['public']['status'], 'OPTIMAL')
        self.assertEqual(r['public']['moves'], {'existing_moved': 0, 'due_to_team_deletion': 0})
        self.assertIn(ZERO_MOVE_NOTICE, r['public']['messages'])
        pub = republish_case()['published']['assignments']
        self.assertTrue(all(r['internal']['assignment'][i] == t for i, t in pub.items()))
        self.assertEqual(r['public']['stage_proof'], {'pub': True, 'quality': True, 'draft': True})
        self.assertEqual(r['public']['kind'], 'republish')

    # ---- #4 품질 우선 (초안보다 품질)
    def test_04_quality_before_draft(self):
        s = tiny(['개발', '개발', '기획', '개발', '기획'])
        s['mode'] = 'republish'
        s['published'] = {'team_ids': ['t1', 't2'], 'assignments': {'p0': 't1', 'p1': 't1', 'p2': 't2', 'p3': 't2'}}
        # 초안은 신규 기획 희망자(p4)를 t2에 둠: t1={개발,개발}, t2={기획,개발,기획} → 품질이 더 나쁨
        s['draft'] = {'assignments': {'p0': 't1', 'p1': 't1', 'p2': 't2', 'p3': 't2', 'p4': 't2'}}
        r = solve(s)
        self.assertEqual(r['public']['status'], 'OPTIMAL')
        self.assertEqual(r['internal']['assignment']['p4'], 't1')
        self.assertEqual(r['internal']['M_draft'], 1)

    # ---- #5 초안 존중 (같은 품질이면 덜 되돌림)
    def test_05_draft_respected_on_ties(self):
        s = tiny(['개발']*5)
        s['selected_questions'], s['priority'], s['categories'] = [], ['size'], {}
        for p in s['participants']:
            p['answers'] = {}
        s['mode'] = 'republish'
        s['published'] = {'team_ids': ['t1', 't2'], 'assignments': {'p0': 't1', 'p1': 't1', 'p2': 't2', 'p3': 't2'}}
        for team in ('t1', 't2'):
            s['draft'] = {'assignments': {'p0': 't1', 'p1': 't1', 'p2': 't2', 'p3': 't2', 'p4': team}}
            r = solve(s)
            self.assertEqual(r['internal']['assignment']['p4'], team)
            self.assertEqual(r['internal']['M_draft'], 0)

    # ---- #6 필수 역할 충돌
    def test_06_insufficient_role(self):
        s = copy.deepcopy(BASE)
        for p in s['participants']:
            p['answers']['role'] = '기획'
        for p in s['participants'][:3]:
            p['answers']['role'] = '개발'
        s['required_roles'] = [{'team': t['id'], 'role': '개발', 'minimum': 1} for t in s['teams']]
        r = solve(s)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertTrue(any('3명' in m and '4팀' in m for m in r['public']['messages']))

    # ---- #7 비공개 선호는 확정을 막지 않음
    def test_07_private_preference_never_blocks(self):
        s = copy.deepcopy(BASE)
        s['fixed'] = [{'participant': 'member_01', 'team': 'team_1'},
                      {'participant': 'member_02', 'team': 'team_1'}]
        r = solve(s)
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        self.assertGreaterEqual(r['internal']['V'], 1)
        self.assertNotIn('비공개', json.dumps(r['public'], ensure_ascii=False))

    # ---- #9 탐색 한도: 후보 없음
    def test_09_limit_without_candidate(self):
        runner = lambda s, m, obj, hint: ('UNKNOWN', [], None, 0.0, 1.0)
        r = solve(BASE, stage_runner=runner)
        self.assertEqual(r['public']['status'], 'LIMIT_NO_CANDIDATE')
        self.assertEqual(r['public']['teams'], [])
        self.assertNotIn('assignment', r['internal'])

    # ---- #10 수동 수정 후 같은 공개 지표 계산기
    def test_10_manual_edit_uses_same_public_calculator(self):
        n = normalize(BASE)
        a = dict(self.demo['internal']['assignment'])
        one = next(i for i in IDS if a[i] == 'team_1')
        two = next(i for i in IDS if a[i] == 'team_2')
        a[one], a[two] = 'team_2', 'team_1'  # 맞교환
        e = evaluate(n, a)
        self.assertEqual(e['required_violations'], [])
        self.assertEqual(e['teams'], verify(n, a)['summaries'])
        self.assertNotIn('J_int', json.dumps(e))
        a[one] = None
        kinds = {v['kind'] for v in evaluate(n, a)['required_violations']}
        self.assertIn('unassigned', kinds)

    # ---- #11 정원 기본값
    def test_11_capacity(self):
        self.assertTrue(all(1 <= t['size'] <= 5 for t in self.demo['public']['teams']))
        s = copy.deepcopy(BASE)
        s['fixed'] = [{'participant': i, 'team': 'team_1'} for i in IDS[:6]]
        self.assertEqual(solve(s)['public']['status'], 'INFEASIBLE')

    # ---- #12 정원 자동 변경 금지
    def test_12_capacity_never_changed(self):
        s = copy.deepcopy(BASE)
        s['participants'].append({'id': 'member_21', 'answers': copy.deepcopy(s['participants'][0]['answers'])})
        before = copy.deepcopy(s['teams'])
        r = solve(s)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertIn('참가자는 21명인데 전체 최대 정원은 20명입니다.', r['public']['messages'])
        self.assertEqual(s['teams'], before)

    # ---- #13 재현성
    def test_13_reproducible_without_cache(self):
        other = solve(copy.deepcopy(BASE))
        self.assertEqual(self.demo['public']['status'], other['public']['status'])
        self.assertEqual(self.demo['internal']['assignment'], other['internal']['assignment'])
        self.assertEqual(self.demo['internal']['J_int'], other['internal']['J_int'])

    def test_13b_cache_reuses_same_input(self):
        cache = {}
        first = solve(tiny(['개발', '기획', '개발', '기획']), cache=cache)
        again = solve(tiny(['개발', '기획', '개발', '기획']), cache=cache)
        self.assertTrue(again['internal']['cache_hit'])
        self.assertEqual(first['internal']['assignment'], again['internal']['assignment'])

    # ---- #14 단계별 최적성: 1단계 FEASIBLE이면 OPTIMAL 아님
    def test_14_unproven_first_stage_is_not_optimal(self):
        def runner(s, m, obj, hint):
            status, found, value, bound, dt = run_stage(s, m, obj, hint)
            return ('FEASIBLE' if obj is m['M_pub'] else status), found, value, bound, dt
        r = solve(republish_case(), stage_runner=runner)
        self.assertEqual(r['public']['status'], 'FEASIBLE')
        self.assertFalse(r['public']['stage_proof']['pub'])

    # ---- #15 후보 보존: 뒤 단계가 한도로 끝나도 앞 단계 후보 반환
    def test_15_candidate_kept_when_later_stages_hit_limit(self):
        def runner(s, m, obj, hint):
            if obj is m['M_pub']:
                return run_stage(s, m, obj, hint)
            return ('UNKNOWN', [], None, 0.0, 1.0)
        r = solve(republish_case(), stage_runner=runner)
        self.assertEqual(r['public']['status'], 'FEASIBLE')
        self.assertEqual(r['public']['moves']['existing_moved'], 0)
        self.assertEqual(len(r['internal']['assignment']), 20)

    # ---- #16 비공개 선호 비포화
    def test_16_private_loss_not_saturated(self):
        n = normalize(BASE)
        a = {i: 'team_1' if k < 5 else TEAMS[k % 3 + 1] for k, i in enumerate(IDS)}
        members = [i for i in IDS if a[i] == 'team_1']
        pairs = [(x, y) for k, x in enumerate(members) for y in members[k+1:]]
        n10, n6 = dict(n, edges=pairs[:10]), dict(n, edges=pairs[:6])
        v10, v6 = verify(n10, a), verify(n6, a)
        self.assertEqual((v10['V'], v6['V']), (10, 6))
        self.assertLess(v6['J_int'], v10['J_int'])
        self.assertEqual((v10['P']['numerator'], v6['P']['numerator']), (10000, 6000))

    # ---- #17 진단 분리
    def test_17_model_infeasible_but_diagnostic_feasible_is_error(self):
        runner = lambda s, m, obj, hint: ('INFEASIBLE', [], None, 0.0, 1.0)
        r = solve(BASE, stage_runner=runner)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertEqual(r['public']['messages'], [GENERIC_ERROR])
        self.assertIn('불일치', r['internal']['error'])

    def test_17b_diagnostic_fixed_role_conflict(self):
        s = copy.deepcopy(BASE)
        s['selected_questions'] = ['role']
        s['priority'] = ['role', 'size']
        s['fixed'] = [{'participant': p['id'], 'team': 'team_1'}
                      for p in s['participants'] if p['answers']['role'] == '개발']
        s['required_roles'] = [{'team': 'team_2', 'role': '개발', 'minimum': 1}]
        r = solve(s)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertEqual(r['internal']['diagnostic_status'], 'INFEASIBLE')
        conflicts = r['internal']['conflicts']
        self.assertIn('team_2: 개발 역할 희망자 최소 1명', conflicts)
        self.assertNotIn('team_1: 최대 정원 5명', conflicts)  # 12-2: 불필요한 조건은 뺌

    # ---- #18 후속 단계 비악화
    def test_18_later_stage_never_returns_worse_move_count(self):
        raw = republish_case()
        pub = raw['published']['assignments']
        base = dict(pub)
        new = IDS[16:]
        for k, i in enumerate(new):
            base[i] = TEAMS[k]
        def moved(pairs):
            a = dict(base)
            for x, y in pairs:
                a[x], a[y] = base[y], base[x]
            return a
        t = {team: [i for i in IDS[:16] if pub[i] == team] for team in TEAMS}
        four = moved([(t['team_1'][0], t['team_2'][0]), (t['team_3'][0], t['team_4'][0])])
        three = dict(base)
        three[t['team_1'][0]], three[t['team_2'][0]], three[t['team_3'][0]] = 'team_2', 'team_3', 'team_1'
        seen = []
        def runner(s, m, obj, hint):
            seen.append(obj)
            if obj is m['M_pub']:
                return ('FEASIBLE', [fake_found(raw, four)], 4, 0.0, 1.0)
            if obj is m['J']:
                return ('FEASIBLE', [fake_found(raw, three)], None, 0.0, 1.0)
            return ('UNKNOWN', [], None, 0.0, 1.0)
        r = solve(raw, stage_runner=runner)
        self.assertEqual(len(seen), 3)
        self.assertEqual(r['public']['moves']['existing_moved'], 3)
        self.assertFalse(r['public']['stage_proof']['pub'])
        self.assertIn(UNPROVEN_MOVE_NOTICE, r['public']['messages'])

    # ---- #20 정원 없음
    def test_20_uncapped_team_can_exceed_five(self):
        s = copy.deepcopy(BASE)
        s['selected_questions'] = []
        s['priority'] = ['size']
        s['private_preferences'] = []
        for t in s['teams']:
            t['capacity'] = None
        s['fixed'] = [{'participant': i, 'team': 'team_1'} for i in IDS[:6]]
        n = normalize(s)
        self.assertFalse(preflight(n))
        self.assertEqual(upper_bounds(n)['team_1'], 17)  # 6 고정 + (14 − 다른 빈 팀 3)
        self.assertEqual(len(tables(n, 17)['size']), 17)
        r = solve(s)
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        self.assertGreaterEqual(next(t['size'] for t in r['public']['teams'] if t['team_id'] == 'team_1'), 6)

    def test_20b_table_over_limit_is_linearized_exactly(self):
        s = tiny(['개발', '기획', '개발', '개발', '기획', '기획', '개발'], teams=3)
        s['selected_questions'] = ['role', 'time', 'experience', 'interest']
        s['priority'] = ['time', 'role', 'experience', 'interest', 'size']
        s['categories'] = {'role': ['기획', '개발'], 'time': ['a', 'b'], 'interest': ['x', 'y', 'z']}
        rng = random.Random(7)
        for p in s['participants']:
            p['answers'].update(time=rng.sample(['a', 'b'], rng.randint(1, 2)),
                                experience=rng.randint(1, 5),
                                interest=rng.sample(['x', 'y', 'z'], rng.randint(1, 3)))
        for method in ('balanced', 'similar'):
            s['method'] = method
            with_tables = solve(s)
            with patch('teamix_engine.scoring.TABLE_LIMIT', 1):
                linear = solve(s)
            self.assertEqual(with_tables['public']['status'], 'OPTIMAL')
            self.assertEqual(linear['public']['status'], 'OPTIMAL', linear['internal'].get('error'))
            self.assertEqual(linear['internal']['J_int'], with_tables['internal']['J_int'])
            self.assertEqual(len(linear['internal']['linearized']), 3*5)

    def test_20c_linearized_losses_match_verifier_on_forced_assignments(self):
        rng = random.Random(3)
        for trial in range(6):
            s = copy.deepcopy(BASE)
            s['method'] = 'balanced' if trial % 2 else 'similar'
            s['private_preferences'] = []
            for t in s['teams']:
                t['capacity'] = None
            ids = IDS[:]
            rng.shuffle(ids)
            a = {i: TEAMS[min(3, k // rng.randint(3, 7))] for k, i in enumerate(ids)}
            for team in TEAMS:  # 빈 팀 방지
                if team not in a.values():
                    a[ids[-1-TEAMS.index(team)]] = team
            s['fixed'] = [{'participant': i, 'team': t} for i, t in a.items()]
            with patch('teamix_engine.scoring.TABLE_LIMIT', 1):
                r = solve(s)
            self.assertEqual(r['public']['status'], 'OPTIMAL', r['internal'].get('error'))
            self.assertEqual(r['internal']['J_int'], verify(normalize(s), a)['J_int'])

    def test_real_100001st_row_stops(self):
        from teamix_engine.scoring import add_row
        rows = [()] * 100000
        with self.assertRaises(TableTooLarge):
            add_row(rows, (1,))
        self.assertEqual(len(rows), 100000)

    # ---- #21 오류 구분
    def test_21_abnormal_stage_blocks_even_with_candidate(self):
        def runner(s, m, obj, hint):
            if obj is m['M_pub']:
                return run_stage(s, m, obj, hint)
            raise RuntimeError('solver crashed')
        r = solve(republish_case(), stage_runner=runner)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertEqual(r['public']['teams'], [])

    def test_21b_verifier_mismatch_blocks(self):
        def runner(s, m, obj, hint):
            status, found, value, bound, dt = run_stage(s, m, obj, hint)
            assignment, values = found[-1]
            return status, [(assignment, dict(values, J=values['J']+1))], value, bound, dt
        r = solve(tiny(['개발', '기획', '개발', '기획']), stage_runner=runner)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertIn('검증', r['internal']['error'])

    # ---- #22 팀 수 변경
    def test_22_team_added_and_deleted(self):
        s = republish_case(new=0)
        s['teams'] = [t for t in s['teams'] if t['id'] != 'team_4'] + [{'id': 'team_5', 'capacity': 6}]
        s['deleted_team_ids'] = ['team_4']
        r = solve(s)
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        a = r['internal']['assignment']
        self.assertEqual(set(a.values()), {'team_1', 'team_2', 'team_3', 'team_5'})
        # 20명 모두 공개 배정(팀당 5명) → 삭제된 team_4의 5명은 반드시 이동
        self.assertEqual(r['public']['moves']['due_to_team_deletion'], 5)
        self.assertIn('팀 삭제로 인한 이동 5명', r['public']['messages'])
        # 그 밖의 기존 참가자는 옮기지 않음 (team_5는 삭제 팀 인원으로 채움)
        self.assertEqual(r['public']['moves']['existing_moved'], 5)

    def test_22b_team_change_conflicts(self):
        s = republish_case(new=0)
        s['teams'] = [t for t in s['teams'] if t['id'] != 'team_4'] + [{'id': 'team_5', 'capacity': 6}]
        s['deleted_team_ids'] = ['team_4']
        victim = next(i for i, t in s['published']['assignments'].items() if t == 'team_4')
        s['draft'] = {'assignments': dict(s['published']['assignments']),
                      'locks': {victim: {'team': 'team_4', 'type': 'manual'}}}
        s['scope_team_ids'] = ['team_1', 'team_2', 'team_3']
        messages = [i['message'] for i in run_precheck(s)['issues']]
        self.assertIn('삭제할 team_4에 1명이 수동 고정되어 있습니다.', messages)
        self.assertIn('새로 만든 team_5이 재편성 범위에 없어 채울 수 없습니다.', messages)

    # ---- 4장 응답 누락
    def test_missing_response_not_imputed(self):
        s = copy.deepcopy(BASE)
        for p in s['participants'][:3]:
            del p['answers']['time']
        r = solve(s)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertIn("3명이 '가능 시간'에 응답하지 않았습니다.", r['public']['messages'])
        self.assertFalse(r['public']['teams'])

    # ---- 12-1 사전 검사
    def test_precheck_scope_capacity_and_duplicates(self):
        s = copy.deepcopy(BASE)
        s['draft'] = {'assignments': {i: TEAMS[k % 4] for k, i in enumerate(IDS[:18])}}
        s['participants'].append({'id': 'member_21', 'answers': copy.deepcopy(s['participants'][0]['answers'])})
        for t in s['teams']:
            t['capacity'] = 6
        s['scope_team_ids'] = ['team_1']
        s['fixed'] = [{'participant': 'member_05', 'team': 'team_2'}, {'participant': 'member_05', 'team': 'team_3'}]
        messages = [i['message'] for i in run_precheck(s)['issues']]
        self.assertTrue(any(m.startswith('선택한 1개 팀의 남은 자리는') for m in messages), messages)
        self.assertIn('같은 참가자(member_05)가 두 팀에 고정되어 있습니다.', messages)
        self.assertTrue(run_precheck(BASE)['ok'])

    # ---- 편성학습 9장 가중치
    def test_weights_times_ten_same_result(self):
        self.assertEqual(self.demo['public']['weights_used'],
                         {'time': 50, 'role': 40, 'experience': 30, 'interest': 20, 'size': 10})
        n = normalize(BASE)
        a = self.demo['internal']['assignment']
        original = dict(n, weights={q: 5-k for k, q in enumerate(n['priority'])})
        self.assertEqual(verify(n, a)['J_int'], 10*verify(original, a)['J_int'])
        # 순위 유지: 뒤 순위 보정이 커도 앞 순위를 넘지 않음
        self.assertEqual(weights(['time', 'role', 'size'], {'role': 2}), {'time': 30, 'role': 30, 'size': 10})
        # 모든 보정이 같으면(b=2) 공약수로 나눈 모델이 같아 편성 결과도 같다
        doubled = copy.deepcopy(BASE)
        doubled['learning'] = {'multipliers': {q: 2 for q in n['priority']}}
        r2 = solve(doubled)
        self.assertEqual(r2['public']['weights_used']['time'], 100)
        self.assertEqual(r2['internal']['assignment'], a)
        bad = copy.deepcopy(BASE)
        bad['learning'] = {'multipliers': {'time': 3}}
        self.assertEqual(solve(bad)['public']['status'], 'ERROR')

    def test_verifier_rejects_invalid_assignment(self):
        assignment = dict(self.demo['internal']['assignment'])
        assignment.pop('member_01')
        with self.assertRaises(ValueError):
            verify(normalize(BASE), assignment)

    def test_private_dedup_and_limit(self):
        n = normalize(BASE)
        self.assertEqual(len(n['edges']), 6)
        s = copy.deepcopy(BASE)
        s['private_preferences'].append({'source': 'member_01', 'target': 'member_03', 'confirmed': True})
        r = solve(s)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertEqual(r['public']['messages'], [GENERIC_ERROR])  # 존재를 드러내지 않음

    def test_single_team_and_all_singletons(self):
        for N, K in [(3, 1), (3, 3)]:
            self.assertEqual(size_loss(N if K == 1 else 1, N, K), 0)

    def test_similar_and_common_time(self):
        s = copy.deepcopy(BASE)
        s['participants'] = s['participants'][:4]
        s['teams'] = [{'id': 'a', 'capacity': 2}, {'id': 'b', 'capacity': 2}]
        s['method'] = 'similar'
        s['require_common_time'] = True
        s['private_preferences'] = []
        for p in s['participants']:
            p['answers']['time'] = ['수 저녁']
        r = solve(s)
        self.assertEqual(r['public']['status'], 'OPTIMAL')
        self.assertTrue(all(t['common_times'] == ['수 저녁'] for t in r['public']['teams']))

    def test_unknown_mode_rejected(self):
        s = copy.deepcopy(BASE)
        s['mode'] = 'reformation'
        self.assertEqual(solve(s)['public']['status'], 'ERROR')


if __name__ == '__main__':
    unittest.main(verbosity=2)
