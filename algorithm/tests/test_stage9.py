"""Stage 9 (편성학습_v4 11·12장, 개발단계 가이드 9단계): re-extraction after deletion, retraining when dirty, monitoring."""
import os
import unittest
import urllib.request
from datetime import datetime, timezone

from learning.monitor import report, REPORT_AFTER


def row(model, mean, source='ai'):
    return {'modelId': model, 'yOverallMean': mean, 'source': source}


class MonitorReportTests(unittest.TestCase):
    def test_waits_until_a_model_has_enough_activities(self):
        rows = [row(None, 4.0)] * 3 + [row('m1', 4.2)] * (REPORT_AFTER - 1)
        self.assertEqual(report(rows)['status'], 'waiting')
        out = report(rows + [row('m1', 4.4)])
        self.assertEqual(out['status'], 'ready')
        self.assertEqual(out['modelsReady'], ['m1'])
        self.assertEqual(out['groups']['default'], {'activities': 3, 'meanYOverall': 4.0})
        self.assertEqual(out['groups']['m1']['activities'], REPORT_AFTER)

    def test_manual_publications_and_empty_feedback_are_not_compared(self):
        out = report([row('m1', 5.0, source='manual'), row(None, None), row(None, 3.0)])
        self.assertEqual(out['groups'], {'default': {'activities': 1, 'meanYOverall': 3.0}})

    def test_report_never_claims_causation(self):
        self.assertIn('인과로 해석하지 않습니다', report([])['caution'])


EMULATED = bool(os.environ.get('FIRESTORE_EMULATOR_HOST'))
PROJECT = os.environ.get('GCLOUD_PROJECT') or os.environ.get('GOOGLE_CLOUD_PROJECT') or ''


@unittest.skipUnless(EMULATED and PROJECT.startswith('demo-'), 'Firestore 에뮬레이터(demo- 프로젝트)가 필요합니다')
class Stage9EmulatorTests(unittest.TestCase):
    def setUp(self):
        from google.cloud import firestore
        from test_extract import published_store, review, members, STAMP
        self.db = firestore.Client(project=PROJECT)
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        urllib.request.urlopen(urllib.request.Request(
            f'http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents', method='DELETE')).close()
        self.store = published_store()
        for path, value in self.store.items():
            self.db.document(path).set(value)
        self.t1 = [m['uid'] for m in members(self.store, 'team_1')]
        for u in self.t1:
            self.db.document(f'feedback/a_{u}').set(review(u, 'team_1'))
        self.db.document('activities/a/feedbackSummary/current').set({'updatedAt': STAMP})

    def summary_changed(self, day):
        self.db.document('activities/a/feedbackSummary/current').set({'updatedAt': datetime(2026, 11, day, tzinfo=timezone.utc)})

    def test_deleted_review_leaves_the_training_row(self):
        from learning.extract import extract_activity, pending, source_ref
        extract_activity(self.db, 'a')
        path = 'trainingDatasets/fx1/rows/a_v1_team_1'
        self.assertEqual(self.db.document(path).get().to_dict()['n_reviews'], 3)
        gone = self.t1[0]
        self.db.document(f'feedback/a_{gone}').delete()   # what deleteFeedback does, plus the summary update below
        self.summary_changed(2)
        self.assertEqual(pending(self.db), ['a'])
        extract_activity(self.db, 'a')
        row = self.db.document(path).get().to_dict()
        self.assertEqual(row['n_reviews'], 2)
        self.assertNotIn(source_ref(f'feedback/a_{gone}'), row['sourceRefs'])
        self.db.document(f'feedback/a_{self.t1[1]}').delete()
        self.summary_changed(3)
        extract_activity(self.db, 'a')
        self.assertFalse(self.db.document(path).get().exists, '포함 후기 1개 → 행 삭제')

    def test_dirty_dataset_makes_training_due_and_is_cleared(self):
        from learning.train import run_training
        from test_train import synthetic
        for r in synthetic(effect={'time': -2.0}):
            self.db.document(f"trainingDatasets/fx1/rows/{r['activityId']}_v1_{r['teamId']}").set(r)
        day = lambda d: datetime(2026, 11, d, tzinfo=timezone.utc)
        run_training(self.db, now=day(1))
        self.assertEqual(run_training(self.db, now=day(2))['status'], 'not_due')
        self.db.document('trainingDatasets/fx1').set({'dirty': True}, merge=True)
        self.assertNotEqual(run_training(self.db, now=day(3))['status'], 'not_due')
        self.assertFalse(self.db.document('trainingDatasets/fx1').get().to_dict()['dirty'])
        self.assertEqual(run_training(self.db, now=day(4))['status'], 'not_due')

    def test_monitor_records_model_used_and_mean_score(self):
        from learning import monitor
        self.db.document('formationRuns/run9').set({'activityId': 'a', 'modelId': 'm1', 'status': 'OPTIMAL'})
        self.db.document('publications/a_v1').update({'sourceRunId': 'run9'})
        rec = monitor.record_activity(self.db, 'a')
        self.assertEqual((rec['modelId'], rec['source'], rec['respondents'], rec['yOverallMean']), ('m1', 'ai', 3, 4.0))
        self.db.document('publications/a_v1').update({'sourceRunId': None})
        self.assertEqual(monitor.record_activity(self.db, 'a')['source'], 'manual')
        out = monitor.run(self.db)
        self.assertEqual(out['status'], 'waiting')
        saved = self.db.document('learningReports/latest').get().to_dict()
        self.assertEqual(saved['status'], 'waiting')
        self.assertNotIn(self.t1[0], str(saved) + str(self.db.document('learningMonitor/a').get().to_dict()))


if __name__ == '__main__':
    unittest.main()
