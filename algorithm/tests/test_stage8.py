"""Stage 8: learned correction factors in the formation engine (편성학습_v4 9장, 개발단계 가이드 8단계)."""
import os
import random
import unittest
import urllib.request
from copy import deepcopy
from datetime import datetime, timezone, timedelta
from unittest import mock

import formation
from formation import learned_weights, prepare, solve, Invalid
from service import versions
from validated_service import ValidatedFormationService
from repository import translate, build_state
import test_main_adapter as adapter
from test_main_adapter import main_docs, collect, STAMP
from test_spec_13_1 import person, raw, twenty
from test_stage3_boundary import MemoryRepository

PRIORITY = ['time', 'role', 'experience', 'interest', 'size']
MODEL = {'enabled': True, 'modelId': 'm1', 'b': {'time': 2.0, 'role': 0.5, 'experience': 1.0, 'interest': 1.3, 'size': 0.8}}


def trade_off():
    """Found by search: default weights favour role balance, lowering role (b=0.5) favours common time."""
    roles = ['dev', 'dev', 'dev', 'design', 'dev', 'design', 'design', 'design']
    times = ['mon', 'mon', 'wed', 'wed', 'mon', 'wed', 'mon', 'wed']
    r = raw([person(f'p{i}', roles[i], [times[i]]) for i in range(8)], [4, 4], selected=['role', 'time'], limit=2)
    r['priority'] = ['role', 'time', 'size']
    return r


def total(result, q):
    return sum(t['losses'][q] for t in result['publicSummary'].values())


class EngineWeightTests(unittest.TestCase):
    def test_without_model_weights_are_ten_times_v3_and_result_is_the_same(self):
        self.assertEqual(learned_weights(PRIORITY), {q: 10 * (5 - r) for r, q in enumerate(PRIORITY)})
        r = raw(twenty(), [5, 5, 5, 5])
        with_learning = solve(deepcopy(r))
        v3 = lambda priority, factors=None: {q: len(priority) - i for i, q in enumerate(priority)}
        with mock.patch.object(formation, 'learned_weights', v3):
            original = solve(deepcopy(r))
        self.assertEqual(with_learning['assignments'], original['assignments'])
        self.assertEqual(with_learning['internal']['J_int'], 10 * original['internal']['J_int'])

    def test_priority_order_is_never_reversed(self):
        rng = random.Random(7)
        for _ in range(2000):
            k = rng.randint(1, 5)
            priority = rng.sample(PRIORITY, k)
            factors = {q: round(rng.uniform(0.5, 2.0), 3) for q in priority if rng.random() < 0.8}
            w = learned_weights(priority, factors)
            values = [w[q] for q in priority]
            self.assertEqual(values, sorted(values, reverse=True), (priority, factors, w))
            self.assertTrue(all(v >= 1 for v in values))
            for q in priority:
                self.assertLessEqual(w[q], round(10 * (len(priority) - priority.index(q)) * factors.get(q, 1) + 0.5))

    def test_spec_examples(self):
        self.assertEqual(learned_weights(PRIORITY, {'role': 2.0})['role'], 50)  # capped at time's 50
        self.assertEqual(learned_weights(PRIORITY, {'time': 0.5, 'size': 2.0}),
                         {'time': 25, 'role': 25, 'experience': 25, 'interest': 20, 'size': 20})
        self.assertEqual(learned_weights(['size'], {'size': 0.5}), {'size': 5})

    def test_factors_change_the_trade_off(self):
        default, corrected = solve(trade_off()), solve({**trade_off(), 'weightFactors': {'role': 0.5}})
        self.assertEqual((total(default, 'role'), total(default, 'time')), (0, 500))
        self.assertEqual((total(corrected, 'role'), total(corrected, 'time')), (500, 0))

    def test_invalid_factors_rejected(self):
        for bad in ({'time': 3.0}, {'time': 0.1}, {'mbti': 1.0}, {'time': float('nan')}, ['time']):
            with self.assertRaises(Invalid):
                prepare({**raw(twenty(), [5, 5, 5, 5]), 'weightFactors': bad})
        self.assertEqual(solve({**raw(twenty(), [5, 5, 5, 5]), 'weightFactors': {'time': 3.0}})['status'], 'ERROR')


class ServiceLearningTests(unittest.TestCase):
    def setUp(self):
        _, _, state = adapter.MainAdapterTests().adapter()
        self.repo = MemoryRepository(state)
        self.service = ValidatedFormationService(self.repo)

    def body(self, **patch):
        v = versions(self.repo.state)
        return {'groupId': 'g', 'activityId': 'a', 'kind': 'initial', 'limit': 2,
                'expected': {k: v[k] for k in ('roster', 'settings', 'draft')}, **patch}

    def runs(self, prefix):
        return [v for k, v in self.repo.documents.items() if k.startswith(prefix)]

    def test_run_records_weights_used_and_model_id(self):
        self.repo.state['learning'] = deepcopy(MODEL)
        self.assertTrue(self.service.invoke('run', 'operator', self.body())['applied'])
        record, = self.runs('groups/g/activities/a/formationRuns/')
        self.assertEqual(record['modelId'], 'm1')
        self.assertEqual(record['weightsUsed'], learned_weights(PRIORITY, MODEL['b']))  # fixture priority = PRIORITY
        server, = self.runs('serverRuns/')
        self.assertEqual(server['snapshot']['weightFactors'], MODEL['b'])

    def test_activity_switch_off_uses_default_weights(self):
        self.repo.state['learning'] = {**deepcopy(MODEL), 'enabled': False}
        self.service.invoke('run', 'operator', self.body())
        record, = self.runs('groups/g/activities/a/formationRuns/')
        self.assertIsNone(record['modelId'])
        self.assertEqual(record['weightsUsed'], learned_weights(PRIORITY))

    def test_no_active_model_uses_default_weights(self):
        self.repo.state['learning'] = {'enabled': True, 'modelId': None, 'b': None}
        self.service.invoke('run', 'operator', self.body())
        record, = self.runs('groups/g/activities/a/formationRuns/')
        self.assertIsNone(record['modelId'])

    def test_precheck_shows_directions_only(self):
        self.repo.state['learning'] = deepcopy(MODEL)
        out = self.service.invoke('precheck', 'operator', self.body())
        self.assertEqual(out['learning'], {'enabled': True, 'modelId': 'm1', 'directions':
                         {'time': 'up', 'role': 'down', 'experience': 'same', 'interest': 'up', 'size': 'down'}})
        self.assertNotIn('2.0', str(out))

    def test_switch_is_an_officer_setting(self):
        self.repo.state['activity']['state'] = 'recruiting'
        self.service.invoke('settings', 'operator', self.body(patch={'learningEnabled': False}))
        self.assertFalse(self.repo.documents['groups/g/activities/a']['learningEnabled'])
        with self.assertRaises(Invalid):
            self.service.invoke('settings', 'operator', self.body(patch={'learningEnabled': 'no'}))

    def test_switch_written_to_settings_matching(self):
        s = build_state('g', 'a', collect(main_docs()))
        (op, path, value, merge), = translate('g', 'a', s, [('groups/g/activities/a', {'learningEnabled': False}, True)], STAMP)
        self.assertEqual((path, value['learningEnabled']), ('activities/a/settings/matching', False))

    def test_published_teams_are_not_re_formed_when_a_model_arrives(self):
        store = main_docs(n=4)
        adapter.MainAdapterTests().run_and_publish(store)
        before = deepcopy(store['publications/a_v1'])
        store['appConfig/learning'] = {'activeModelId': 'm1', 'b': MODEL['b']}
        self.assertEqual(store['publications/a_v1'], before)
        state = build_state('g', 'a', collect(store))
        self.assertEqual(state['learning']['modelId'], 'm1')
        # A later re-formation keeps every published member in place (zero-move policy) even with the model.
        repo = adapter.MemoryMainRepository(store)
        svc = ValidatedFormationService(repo)
        v = versions(state)
        out = svc.invoke('run', 'operator', {'groupId': 'g', 'activityId': 'a', 'kind': 'republish', 'limit': 2,
                                              'expected': {k: v[k] for k in ('roster', 'settings', 'draft')}})
        self.assertTrue(out['applied'])
        self.assertEqual(out['movementSummary']['publishedMoved'], 0)


EMULATED = bool(os.environ.get('FIRESTORE_EMULATOR_HOST'))
PROJECT = os.environ.get('GCLOUD_PROJECT') or os.environ.get('GOOGLE_CLOUD_PROJECT') or ''


@unittest.skipUnless(EMULATED and PROJECT.startswith('demo-'), 'Firestore 에뮬레이터(demo- 프로젝트)가 필요합니다')
class ReformationCheckTests(unittest.TestCase):
    def setUp(self):
        from google.cloud import firestore
        self.db = firestore.Client(project=PROJECT)
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        urllib.request.urlopen(urllib.request.Request(
            f'http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents', method='DELETE')).close()
        base = datetime(2026, 10, 1, tzinfo=timezone.utc)
        for i, a in enumerate(['a1', 'a2', 'a3', 'a4', 'a1']):
            run = f'r{i}'
            self.db.document(f'formationRuns/{run}').set({'activityId': a, 'status': 'FEASIBLE', 'createdAt': base + timedelta(hours=i)})
            self.db.document(f'serverRuns/{run}').set({'snapshot': {**raw(twenty(), [5, 5, 5, 5]), 'published': {'p00': 'team_1'}}})

    def test_latest_run_of_three_recent_activities_re_formed_with_b(self):
        from learning.train import reformation_check
        out = reformation_check(self.db, MODEL['b'])
        self.assertEqual(out['status'], 'passed')
        self.assertEqual([c['activityId'] for c in out['activities']], ['a1', 'a4', 'a3'])
        self.assertTrue(all(c['teamSizes'] == [5, 5, 5, 5] and c['requiredValid'] for c in out['activities']))
        self.assertNotIn('p00', str(out))

    def test_failed_re_formation_blocks_the_candidate(self):
        from learning import train as T
        from test_train import synthetic
        for r in synthetic(effect={'time': -2.0}):
            self.db.document(f"trainingDatasets/fx1/rows/{r['activityId']}_v1_{r['teamId']}").set(r)
        with mock.patch.object(formation, 'solve', return_value={'status': 'ERROR'}):
            out = T.run_training(self.db, now=datetime(2026, 11, 1, tzinfo=timezone.utc))
        self.assertEqual(out['status'], 'failed_reformation_check')
        self.assertEqual(list(self.db.collection('modelVersions').stream()), [])


if __name__ == '__main__':
    unittest.main()
