import unittest
from datetime import datetime, timezone

import learning_api as L


class LearningApiTest(unittest.TestCase):
    def test_only_service_admin(self):
        with self.assertRaises(L.NotAdmin):
            L.require_admin({'uid': 'u1'})
        with self.assertRaises(L.NotAdmin):
            L.require_admin(None)
        L.require_admin({'uid': 'u1', 'admin': True})

    def test_summary_of_candidate_and_insufficient_runs(self):
        at = datetime(2026, 10, 30, tzinfo=timezone.utc)
        run = {'runId': 'r1', 'status': 'candidate', 'rowCount': 36, 'activityCount': 6, 'trainedAt': at, 'modelId': 'r1'}
        model = {'status': 'candidate', 'b': {'time': 1.5}, 'validation': {'rmse': {'model': 0.28}}}
        s = L.summarize(run, model)
        self.assertEqual(s['trainedAt'], at.isoformat())
        self.assertEqual((s['modelStatus'], s['b'], s['rmse']), ('candidate', {'time': 1.5}, {'model': 0.28}))
        s = L.summarize({**run, 'status': 'insufficient_data', 'modelId': None, 'rowCount': 4}, None)
        self.assertEqual((s['status'], s['b'], s['rowCount']), ('insufficient_data', None, 4))
        self.assertIsNone(L.summarize(None, None))

    def test_routes_refuse_non_admin(self):
        try:
            from fastapi.testclient import TestClient
            import server_v3
        except Exception as e:  # httpx/firebase_admin missing locally
            self.skipTest(str(e))
        app = server_v3.create_app()
        app.dependency_overrides[server_v3.current_token] = lambda: {'uid': 'u1'}
        app.dependency_overrides[server_v3.get_db] = lambda: None
        client = TestClient(app)
        for route in ('/learning/status', '/learning/train'):
            self.assertEqual(client.post(route).status_code, 403)


if __name__ == '__main__':
    unittest.main()
