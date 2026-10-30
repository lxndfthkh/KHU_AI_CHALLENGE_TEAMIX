"""Personality axes (traits): engine scoring, verifier agreement and server snapshot."""
import random
import unittest

from formation import solve, prepare, assess
from repository import build_state
from service import snapshot

ROLES, TIMES, INTERESTS = ['plan', 'dev', 'design', 'ops'], ['wed', 'fri', 'sat'], ['web', 'app', 'content']
TRAITS = [{'id': 'ext', 'label': '외향성', 'size': 2}, {'id': 'lead', 'label': '리더십', 'size': 2}]


def raw(method='balanced', n=12, seed=7):
    rnd = random.Random(seed)
    people = [{'id': f'u{i:02d}', 'answers': {
        'role': rnd.choice(ROLES), 'time': rnd.sample(TIMES, rnd.randint(1, 3)),
        'personality': {'ext': rnd.randint(2, 10), 'lead': rnd.randint(2, 10)}}} for i in range(n)]
    return {'participants': people, 'teams': [{'id': f't{j}', 'capacity': 4} for j in range(3)],
            'selected_questions': ['time', 'role', 'personality'], 'priority': ['personality', 'time', 'role', 'size'],
            'method': method, 'categories': {'role': ROLES, 'time': TIMES}, 'traits': TRAITS, 'limit': 5}


class PersonalityEngine(unittest.TestCase):
    def test_balanced_and_similar_pass_independent_verification(self):
        for method in ('balanced', 'similar'):
            r = solve(raw(method))
            self.assertIn(r['status'], ('OPTIMAL', 'FEASIBLE'), r['internal'])
            for item in r['publicSummary'].values():
                self.assertEqual(set(item['personality']), {'ext', 'lead'})
                self.assertIn('personality', item['losses'])

    def test_balanced_is_better_than_a_skewed_assignment(self):
        s = prepare(raw())
        ranked = sorted(s['participants'], key=lambda p: p['answers']['personality']['ext'])
        skewed = {p['id']: f't{i // 4}' for i, p in enumerate(ranked)}
        best = solve(raw())
        _, a = assess(s, best['assignments'])
        _, b = assess(s, skewed)
        self.assertLessEqual(a['J_int'], b['J_int'])

    def test_rejects_out_of_range_and_missing_axes(self):
        bad = raw(); bad['participants'][0]['answers']['personality']['ext'] = 11
        self.assertEqual(solve(bad)['status'], 'ERROR')
        bad = raw(); del bad['participants'][0]['answers']['personality']['lead']
        self.assertEqual(solve(bad)['status'], 'ERROR')
        bad = raw(); bad['traits'] = []
        self.assertEqual(solve(bad)['status'], 'ERROR')

    def test_without_personality_is_unchanged(self):
        r = raw(); r['selected_questions'] = ['time', 'role']; r['priority'] = ['time', 'role', 'size']
        r.pop('traits')
        for p in r['participants']:
            p['answers'].pop('personality')
        self.assertIn(solve(r)['status'], ('OPTIMAL', 'FEASIBLE'))


class PersonalitySnapshot(unittest.TestCase):
    def docs(self):
        qs = {'qrole': {'type': 'single', 'options': [{'id': o} for o in ROLES], 'enabled': True},
              'qe1': {'type': 'scale', 'enabled': True}, 'qe2': {'type': 'scale', 'enabled': True},
              'ql1': {'type': 'scale', 'enabled': True}}
        settings = {'method': 'balanced', 'enabledQuestionIds': ['qrole'], 'questionCriteria': {'qrole': 'role'},
                    'traits': [{'id': 'ext', 'label': '외향성', 'items': [{'questionId': 'qe1'},
                                                                        {'questionId': 'qe2', 'reverse': True}]},
                               {'id': 'lead', 'label': '리더십', 'items': [{'questionId': 'ql1'}]}],
                    'priority': ['personality', 'role', 'size']}
        mem, reg = {}, {}
        for i in range(6):
            u = f'u{i}'
            mem[f'g_{u}'] = {'groupId': 'g', 'userId': u, 'role': 'admin' if i == 0 else 'member', 'status': 'approved'}
            reg[f'a_{u}'] = {'activityId': 'a', 'groupId': 'g', 'userId': u, 'status': 'submitted', 'updatedAt': 1,
                             'answers': {'qrole': ROLES[i % 4], 'qe1': 5, 'qe2': 1 + i % 5, 'ql1': 1 + i % 5}}
        return {'activity': {'groupId': 'g', 'status': 'closed', 'targetTeamSize': 3}, 'settings': settings,
                'questions': qs, 'memberships': mem, 'registrations': reg, 'draft': None, 'publication': None,
                'preferences': [], 'teamViews': {}, 'learning': None}

    def test_reverse_items_and_axis_sizes(self):
        raw_input = snapshot(build_state('g', 'a', self.docs()), {'kind': 'initial'})
        self.assertEqual(raw_input['traits'], [{'id': 'ext', 'label': '외향성', 'size': 2},
                                               {'id': 'lead', 'label': '리더십', 'size': 1}])
        u1 = next(p for p in raw_input['participants'] if p['id'] == 'u1')
        self.assertEqual(u1['answers']['personality'], {'ext': 5 + (6 - 2), 'lead': 2})
        self.assertIn(solve(raw_input)['status'], ('OPTIMAL', 'FEASIBLE'))

    def test_trait_question_cannot_be_a_choice_question(self):
        docs = self.docs(); docs['settings']['traits'][1]['items'] = [{'questionId': 'qrole'}]
        with self.assertRaises(Exception):
            build_state('g', 'a', docs)


if __name__ == '__main__':
    unittest.main()
