import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from teamix_engine import solve
from teamix_engine.schema import normalize, preflight
from teamix_engine.scoring import tables, verify, size_loss, category_loss

BASE = json.loads((Path(__file__).resolve().parents[1]/"examples/initial_20.json").read_text())

class EngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.demo = solve(BASE)

    def test_01_basic_twenty(self):
        r = self.demo
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        ids = [i for t in r['public']['teams'] for i in t['participants']]
        self.assertEqual(len(ids), 20)
        self.assertEqual(len(set(ids)), 20)
        for forbidden in ['"V"', '"P"', '"J_int"', 'private_preferences']:
            self.assertNotIn(forbidden, json.dumps(r['public']))
        verified = verify(normalize(BASE), r['internal']['assignment'])
        self.assertEqual(verified['J_int'], r['internal']['J_int'])

    def test_06_insufficient_role(self):
        s = copy.deepcopy(BASE)
        for p in s['participants']:
            p['answers']['role'] = '기획'
        for p in s['participants'][:3]:
            p['answers']['role'] = '개발'
        s['required_roles'] = [{'team':t['id'], 'role':'개발', 'minimum':1} for t in s['teams']]
        r = solve(s)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertTrue(any('3명' in m and '4명' in m for m in r['public']['messages']))

    def test_11_capacity(self):
        self.assertTrue(all(1 <= t['size'] <= 5 for t in self.demo['public']['teams']))
        s = copy.deepcopy(BASE)
        s['fixed'] = [{'participant':p['id'], 'team':'team_1'} for p in s['participants'][:6]]
        self.assertEqual(solve(s)['public']['status'], 'INFEASIBLE')

    def test_13_reproducible_without_cache(self):
        # A real second solve, not a cached replay. Ignore wall time and search telemetry.
        other = solve(copy.deepcopy(BASE))
        self.assertEqual(self.demo['public']['status'], other['public']['status'])
        self.assertEqual(self.demo['internal']['assignment'], other['internal']['assignment'])
        self.assertEqual(self.demo['internal']['J_int'], other['internal']['J_int'])

    def test_20_uncapped_team_can_exceed_five(self):
        s = copy.deepcopy(BASE)
        s['selected_questions'] = []
        s['priority'] = ['size']
        s['private_preferences'] = []
        for t in s['teams']:
            t['capacity'] = None
        # Team 1 must accept six: no stale score-table capacity of five.
        s['fixed'] = [{'participant':p['id'], 'team':'team_1'} for p in s['participants'][:6]]
        n = normalize(s)
        self.assertFalse(preflight(n))
        self.assertEqual(len(tables(n, 17)['size']), 17)
        r = solve(s)
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        self.assertGreaterEqual(next(t['size'] for t in r['public']['teams'] if t['team_id']=='team_1'), 6)

    def test_missing_response_not_imputed(self):
        s = copy.deepcopy(BASE)
        del s['participants'][0]['answers']['experience']
        r = solve(s)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertIn('응답 누락', ' '.join(r['public']['messages']))
        self.assertFalse(r['public']['teams'])

    def test_table_limit(self):
        with patch('teamix_engine.scoring.TABLE_LIMIT', 1):
            r = solve(BASE)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertIn('점수표', r['internal']['error'])

    def test_real_100001st_row_stops(self):
        from teamix_engine.scoring import add_row
        rows = [()] * 100000
        with self.assertRaises(ValueError):
            add_row(rows, (1,))
        self.assertEqual(len(rows), 100000)

    def test_verifier_rejects_invalid_assignment(self):
        assignment = dict(self.demo['internal']['assignment'])
        assignment.pop('member_01')
        with self.assertRaises(ValueError):
            verify(normalize(BASE), assignment)

    def test_private_dedup_and_limit(self):
        n = normalize(BASE)
        self.assertEqual(len(n['edges']), 6)
        s = copy.deepcopy(BASE)
        s['private_preferences'].append({'source':'member_01','target':'member_03','confirmed':True})
        self.assertEqual(solve(s)['public']['status'], 'ERROR')

    def test_single_team_and_all_singletons(self):
        for N, K in [(3,1), (3,3)]:
            self.assertEqual(size_loss(N if K==1 else 1, N, K), 0)

    def test_diagnostic_fixed_role_conflict(self):
        s = copy.deepcopy(BASE)
        s['selected_questions'] = ['role']
        s['priority'] = ['role','size']
        s['fixed'] = [{'participant':p['id'],'team':'team_1'} for p in s['participants'] if p['answers']['role']=='개발']
        s['required_roles'] = [{'team':'team_2','role':'개발','minimum':1}]
        r = solve(s)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertEqual(r['internal']['diagnostic_status'], 'INFEASIBLE')
        self.assertTrue(r['internal']['conflicts'])

    def test_similar_and_common_time(self):
        s = copy.deepcopy(BASE)
        s['participants'] = s['participants'][:4]
        s['teams'] = [{'id':'a','capacity':2},{'id':'b','capacity':2}]
        s['method'] = 'similar'
        s['require_common_time'] = True
        for p in s['participants']:
            p['answers']['time'] = ['수 저녁']
        r = solve(s)
        self.assertEqual(r['public']['status'], 'OPTIMAL')
        self.assertTrue(all(t['common_times']==['수 저녁'] for t in r['public']['teams']))

    def test_public_reformation_rejected(self):
        s = copy.deepcopy(BASE)
        s['mode'] = 'reformation'
        self.assertEqual(solve(s)['public']['status'], 'ERROR')

if __name__ == '__main__':
    unittest.main(verbosity=2)
