"""Stage 7 training on synthetic rows (편성학습_v4 8·10·13장, 개발단계 가이드 7단계).

These show that the pipeline works, not that it improves satisfaction (13장 가상 데이터 검증).
"""
import os
import unittest
import urllib.request
from datetime import datetime, timezone

import numpy as np

from learning.train import train, should_train, run_training, corrections, CRITERIA, MIN_ROWS

PRIORITY_W = {'time': 5, 'role': 4, 'experience': 3, 'interest': 2, 'size': 1}


def synthetic(activities=8, teams=5, effect=None, seed=1, noise=0.1):
    """effect: criterion -> slope on y_overall (negative = more loss, less satisfaction)."""
    rng = np.random.default_rng(seed)
    rows = []
    for a in range(activities):
        for t in range(teams):
            loss = {q: float(rng.uniform(0, 1)) for q in CRITERIA}
            y = 4.0 + sum(s * (loss[q] - 0.5) for q, s in (effect or {}).items()) + rng.normal(0, noise)
            row = {'activityId': f'a{a}', 'teamVersion': 1, 'teamId': f'team_{t}', 'activityType': None,
                   'formationMode': 'balanced' if a % 2 else 'similar', 'teamSize': 4, 'n_reviews': 3,
                   'y_overall': float(min(5, max(1, y))), 'y_schedule': 3.0, 'y_roles': 3.0, 'y_rejoin': 3.0}
            for q in CRITERIA:
                row.update({f'loss_{q}': loss[q], f'active_{q}': 1, f'weight_{q}': PRIORITY_W[q]})
            rows.append(row)
    return rows


class TrainTests(unittest.TestCase):
    def test_planted_time_effect_gives_b_time_above_one(self):
        result = train(synthetic(effect={'time': -2.0}))
        self.assertEqual(result['status'], 'candidate', result['validation']['rmse'])
        self.assertGreater(result['b']['time'], 1)
        self.assertEqual(max(result['b'], key=result['b'].get), 'time')
        self.assertLess(result['coefficients']['loss_time'], 0)
        self.assertNotIn('time', result['uncertain'])
        for q in CRITERIA:
            self.assertTrue(0.5 <= result['b'][q] <= 2.0)

    def test_no_relationship_is_never_a_candidate(self):
        # An 80% interval excludes 0 by chance about 1 time in 5, so a b_q can move on pure noise.
        # The RMSE gate is what keeps such a result from ever being approved or applied.
        for seed in range(5):
            result = train(synthetic(effect={}, noise=0.5, seed=seed))
            self.assertEqual(result['status'], 'not_better_than_baselines', seed)
            for q in result['uncertain']:
                self.assertEqual(result['b'][q], 1.0)

    def test_too_little_data_does_not_train(self):
        few_rows = synthetic(activities=5, teams=5)[:MIN_ROWS - 1]
        self.assertEqual(train(few_rows)['status'], 'insufficient_data')
        few_activities = synthetic(activities=4, teams=10)
        self.assertEqual(train(few_activities)['status'], 'insufficient_data')
        self.assertEqual(train(synthetic(activities=5, teams=6, effect={'time': -2.0}))['rowCount'], 30)

    def test_reproducible_with_same_seed(self):
        rows = synthetic(effect={'time': -2.0, 'role': -1.0})
        first, second = train(rows, seed=3), train(list(reversed(rows)), seed=3)
        self.assertEqual(first['b'], second['b'])
        self.assertEqual(first['alpha'], second['alpha'])
        self.assertEqual(first['datasetHash'], second['datasetHash'])

    def test_corrections_formula(self):
        beta = {'time': -0.4, 'role': -0.1, 'experience': 0.2, 'interest': 0.0, 'size': -0.0}
        b, s, lam = corrections(beta, uncertain={'role'}, n_rows=50)
        self.assertEqual(lam, 0.5)
        # mean(s) = 0.1; raw_time = 4 -> 1 + 0.5*3 = 2.5 -> clip 2.0; experience raw 0 -> 0.5; role uncertain -> 1
        self.assertEqual((b['time'], b['role'], b['experience'], b['interest']), (2.0, 1.0, 0.5, 0.5))
        self.assertEqual(corrections({q: 0.3 for q in CRITERIA}, set(), 100)[0], {q: 1.0 for q in CRITERIA})

    def test_auxiliary_score_models_are_report_only(self):
        result = train(synthetic(effect={'time': -2.0}))
        aux = result['validation']['auxiliary']
        self.assertEqual(sorted(aux), ['y_rejoin', 'y_roles', 'y_schedule'])
        self.assertTrue(all(a['status'] == 'ok' for a in aux.values()))

    def test_schedule(self):
        june = datetime(2026, 6, 3, tzinfo=timezone.utc)
        self.assertTrue(should_train(5, None, june))
        self.assertFalse(should_train(39, {'trainedAt': june, 'rowCount': 30}, datetime(2026, 6, 20, tzinfo=timezone.utc)))
        self.assertTrue(should_train(40, {'trainedAt': june, 'rowCount': 30}, datetime(2026, 6, 20, tzinfo=timezone.utc)))
        self.assertTrue(should_train(30, {'trainedAt': june, 'rowCount': 30}, datetime(2026, 7, 1, tzinfo=timezone.utc)))


EMULATED = bool(os.environ.get('FIRESTORE_EMULATOR_HOST'))
PROJECT = os.environ.get('GCLOUD_PROJECT') or os.environ.get('GOOGLE_CLOUD_PROJECT') or ''


@unittest.skipUnless(EMULATED and PROJECT.startswith('demo-'), 'Firestore 에뮬레이터(demo- 프로젝트)가 필요합니다')
class TrainEmulatorTests(unittest.TestCase):
    def setUp(self):
        from google.cloud import firestore
        self.db = firestore.Client(project=PROJECT)
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        urllib.request.urlopen(urllib.request.Request(
            f'http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents', method='DELETE')).close()

    def put_rows(self, rows):
        for r in rows:
            self.db.document(f"trainingDatasets/fx1/rows/{r['activityId']}_v1_{r['teamId']}").set(r)

    def test_candidate_written_with_report_and_run_log(self):
        self.put_rows(synthetic(effect={'time': -2.0}))
        now = datetime(2026, 11, 1, tzinfo=timezone.utc)
        out = run_training(self.db, now=now)
        self.assertEqual(out['status'], 'candidate')
        model = self.db.document(f"modelVersions/{out['runId']}").get().to_dict()
        self.assertEqual((model['status'], model['approvedBy'], model['datasetId'], model['extractorVersion']), ('candidate', None, 'fx1', 'fx1'))
        self.assertGreater(model['b']['time'], 1)
        self.assertIn('baseline_mean', model['validation']['rmse'])
        self.assertEqual(run_training(self.db, now=now)['status'], 'not_due')

    def test_insufficient_data_is_logged_without_a_model(self):
        self.put_rows(synthetic(activities=3, teams=5))
        out = run_training(self.db, now=datetime(2026, 11, 1, tzinfo=timezone.utc))
        self.assertEqual(out['status'], 'insufficient_data')
        self.assertEqual(list(self.db.collection('modelVersions').stream()), [])
        self.assertEqual(self.db.document(f"trainingRuns/{out['runId']}").get().to_dict()['modelId'], None)


if __name__ == '__main__':
    unittest.main()
