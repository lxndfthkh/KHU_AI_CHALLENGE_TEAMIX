import unittest

import demo_compare as D
from formation import solve
from learning_api import teams_of

# The candidate trained from scripts/mock_learning_data.cjs (seed 7, train seed 0).
LEARNED = {'time': 1.5217, 'interest': 0.7239, 'size': 1.0}


def groups(result):
    return [[int(u[-2:]) for u in t['memberIds']] for t in teams_of(result, {})]


class DemoCompareTest(unittest.TestCase):
    def test_default_weights_form_teams_in_order(self):
        r = solve(D.engine_input())
        self.assertEqual(r['status'], 'OPTIMAL')
        self.assertEqual(groups(r), [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16], [17, 18, 19, 20]])

    def test_learned_factors_regroup_by_shared_weekend(self):
        r = solve(D.engine_input(LEARNED))
        self.assertEqual(r['status'], 'OPTIMAL')
        self.assertEqual(groups(r), [[1, 2, 5, 8], [3, 4, 6, 7], [9, 10, 13, 16], [11, 12, 14, 15], [17, 18, 19, 20]])

    def test_seeded_documents_match_engine_input(self):
        docs = D.documents('admin1')
        regs = [d for p, d in docs.items() if p.startswith('registrations/')]
        self.assertEqual(len(regs), 20)
        self.assertEqual(docs['memberships/mock_compare_demo_admin1']['role'], 'admin')
        self.assertEqual({r['userId']: {'time': r['answers']['q_time'], 'interest': r['answers']['q_interest']}
                          for r in regs}, D.answers())


if __name__ == '__main__':
    unittest.main()


class DemoThroughRepositoryTest(unittest.TestCase):
    def test_server_builds_the_same_input_from_the_seeded_documents(self):
        from repository import build_state
        from service import snapshot
        docs = D.documents('admin1')
        a = f'activities/{D.ACTIVITY}'
        state = build_state(D.GROUP, D.ACTIVITY, {
            'activity': docs[a], 'settings': docs[f'{a}/settings/matching'],
            'questions': {p.rsplit('/', 1)[1]: d for p, d in docs.items() if p.startswith(f'{a}/questions/')},
            'memberships': {p: d for p, d in docs.items() if p.startswith('memberships/')},
            'registrations': {p: d for p, d in docs.items() if p.startswith('registrations/')},
            'draft': None, 'publication': None, 'preferences': [], 'teamViews': {}, 'learning': None})
        raw = snapshot(state, {'kind': 'initial'})
        self.assertEqual(groups(solve(raw)), groups(solve(D.engine_input())))
        self.assertEqual(groups(solve({**raw, 'weightFactors': LEARNED})), groups(solve(D.engine_input(LEARNED))))
