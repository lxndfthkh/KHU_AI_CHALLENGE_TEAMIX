import copy
import json
from pathlib import Path
import unittest
from teamix_engine import solve, run_precheck
from teamix_engine.schema import normalize, InputError

BASE = json.loads((Path(__file__).resolve().parents[1]/"examples/initial_20.json").read_text())


def roles(n, teams=None, **setup):
    """역할 질문만 있는 n명 입력 + 편성 설정 ①."""
    raw = {'mode': 'initial', 'method': 'balanced', 'selected_questions': ['role'],
           'priority': ['role', 'size'], 'categories': {'role': ['기획', '개발']},
           'participants': [{'id': f'p{k:02d}', 'answers': {'role': ['기획', '개발'][k % 2]}}
                            for k in range(n)],
           'setup': setup, 'solver': {'seed': 42, 'max_deterministic_time': 5}}
    if teams is not None:
        raw['teams'] = teams
    return raw


class SetupTests(unittest.TestCase):
    def input_error(self, raw, text):
        with self.assertRaises(InputError) as e:
            normalize(copy.deepcopy(raw))
        self.assertIn(text, str(e.exception))
        r = solve(raw)
        self.assertEqual(r['public']['status'], 'ERROR')
        self.assertIn(text, r['public']['messages'][0])

    def test_generates_teams_from_count_and_max(self):
        r = solve(roles(10, team_count=3, max_per_team=4, total_invites=12))
        self.assertIn(r['public']['status'], ['OPTIMAL', 'FEASIBLE'])
        self.assertEqual(sorted(t['team_id'] for t in r['public']['teams']), ['team_1', 'team_2', 'team_3'])
        self.assertTrue(all(len(t['participants']) <= 4 for t in r['public']['teams']))
        self.assertEqual(r['public']['setup'],
                         {'team_count': 3, 'max_per_team': 4, 'total_invites': 12})

    def test_no_max_means_uncapped(self):
        s = normalize(roles(6, team_count=2))
        self.assertEqual(s['capacity'], {'team_1': None, 'team_2': None})
        self.assertEqual(s['setup'], {'team_count': 2, 'max_per_team': None, 'total_invites': None})

    def test_existing_teams_filled_and_checked(self):
        s = normalize(roles(6, teams=[{'id': 'a', 'capacity': None}, {'id': 'b', 'capacity': 2}],
                            team_count=2, max_per_team=4))
        self.assertEqual(s['capacity'], {'a': 4, 'b': 2})
        self.input_error(roles(6, teams=[{'id': 'a', 'capacity': 5}, {'id': 'b'}],
                               team_count=2, max_per_team=4), '팀별 최대 인원')
        self.input_error(roles(6, teams=[{'id': 'a'}], team_count=2), '팀 목록')

    def test_setup_values_validated(self):
        self.input_error(roles(6, team_count=0), '팀 수')
        self.input_error(roles(6, team_count=True), '팀 수')
        self.input_error(roles(6, team_count=2, max_per_team=0), '팀별 최대 인원')
        self.input_error(roles(6, team_count=2, total_invites='10'), '총 초대 인원')
        self.input_error(roles(6, team_count=3, total_invites=2), '빈 팀')
        self.input_error(roles(6, team_count=2, max_per_team=3, total_invites=7), '2×3=6명')
        self.input_error(roles(6, team_count=2, capacity=3), 'team_count')

    def test_participants_over_total_invites(self):
        raw = roles(9, team_count=2, max_per_team=5, total_invites=8)
        issues = run_precheck(raw)['issues']
        self.assertEqual([i['kind'] for i in issues], ['invite_total'])
        r = solve(raw)
        self.assertEqual(r['public']['status'], 'INFEASIBLE')
        self.assertIn('총 초대 인원은 8명', r['public']['messages'][0])

    def test_without_setup_unchanged(self):
        self.assertIsNone(normalize(BASE)['setup'])
        self.assertNotIn('setup', solve(roles(4, teams=[{'id': 'a'}, {'id': 'b'}]) | {'setup': None})['public'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
