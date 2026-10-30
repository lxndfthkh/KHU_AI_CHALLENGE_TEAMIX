"""실제 Firestore·Auth 에뮬레이터 검증: main 스키마(docs/FIRESTORE.md) 위에서 3단계 서버 명령.

에뮬레이터가 없으면 건너뛴다. 실행 (저장소 루트):
  npx firebase emulators:exec --only firestore,auth --project demo-teamix-stage3 \
    "cd algorithm && .venv/bin/python -m unittest discover -s tests -p 'test_firestore_emulator.py' -v"
demo- 프로젝트 ID만 허용하므로 실제 Firebase 프로젝트에는 접근하지 않는다.
"""
import json
import os
import unittest
import urllib.error
import urllib.request

from test_main_adapter import main_docs

EMULATED = bool(os.environ.get('FIRESTORE_EMULATOR_HOST') and os.environ.get('FIREBASE_AUTH_EMULATOR_HOST'))
PROJECT = os.environ.get('GCLOUD_PROJECT') or os.environ.get('GOOGLE_CLOUD_PROJECT') or ''


@unittest.skipUnless(EMULATED and PROJECT.startswith('demo-'), 'Firestore/Auth 에뮬레이터(demo- 프로젝트)가 필요합니다')
class FirestoreEmulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import firebase_admin
        from firebase_admin import auth
        from google.cloud import firestore
        if not firebase_admin._apps:
            firebase_admin.initialize_app(options={'projectId': PROJECT})
        # 에뮬레이터 전용: firebase_admin.firestore.client()는 ADC를 요구하므로 자격 증명 없는 클라이언트를 쓴다.
        cls.auth, cls.db = auth, firestore.Client(project=PROJECT)

    def seed(self, docs):
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        req = urllib.request.Request(f'http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents', method='DELETE')
        urllib.request.urlopen(req).close()
        for path, value in docs.items():
            self.db.document(path).set(value)

    def setUp(self):
        docs = main_docs()
        docs['placementPreferences/g_u0_u1'] = {'groupId': 'g', 'userId': 'u0', 'targetUserId': 'u1', 'active': True}
        self.seed(docs)

    def service(self, solver=None):
        from repository import FirestoreRepository
        from validated_service import ValidatedFormationService
        return ValidatedFormationService(FirestoreRepository(self.db), solver)

    def body(self, **patch):
        versions = self.service().invoke('precheck', 'operator', {'groupId': 'g', 'activityId': 'a'})['versions']
        return {'groupId': 'g', 'activityId': 'a', 'kind': 'initial', 'limit': 2,
                'expected': {k: versions[k] for k in ('roster', 'settings', 'draft')}, **patch}

    def get(self, path):
        snap = self.db.document(path).get()
        return snap.to_dict() if snap.exists else None

    def test_generate_draft_writes_main_draft_and_keeps_private_values_server_only(self):
        response = self.service().invoke('run', 'operator', self.body())
        self.assertTrue(response['applied'], response)
        draft = self.get('drafts/a')
        self.assertEqual((draft['activityId'], draft['groupId'], draft['status']), ('a', 'g', 'ready'))
        team_of = {u: t['teamId'] for t in draft['teams'] for u in t['members']}
        self.assertEqual(sorted(team_of), ['u0', 'u1', 'u2', 'u3'])
        self.assertNotEqual(team_of['u0'], team_of['u1'])
        shared = [response, draft] + [d.to_dict() for d in self.db.collection('formationRuns').stream()]
        for word in ('J_int', 'private_preferences', 'targetUserId', 'targetUid'):
            self.assertNotIn(word, str(shared))
        runs = [d.to_dict() for d in self.db.collection('serverRuns').stream()]
        self.assertEqual(len(runs), 1)
        self.assertIn('J_int', str(runs[0]['internal']))

    def test_answer_change_during_solve_is_stale_in_real_transaction(self):
        from formation import solve
        db = self.db

        def solver(raw):
            result = solve(raw)
            db.document('registrations/a_u0').update({'answers.experience': 5})
            return result

        response = self.service(solver).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'STALE')
        self.assertFalse(response['applied'])
        self.assertIsNone(self.get('drafts/a'))
        self.assertEqual([d.to_dict()['status'] for d in db.collection('serverRuns').stream()], ['STALE'])

    def test_preference_revoked_during_solve_is_stale(self):
        from formation import solve
        db = self.db

        def solver(raw):
            result = solve(raw)
            db.document('placementPreferences/g_u0_u1').update({'active': False})
            return result

        response = self.service(solver).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'STALE')
        self.assertIsNone(self.get('drafts/a'))

    def test_close_recruitment_sets_team_ids_and_default_capacity(self):
        docs = main_docs(n=5, target=2)
        docs['activities/a']['status'] = 'recruiting'
        settings = docs['activities/a/settings/matching']
        del settings['teamIds'], settings['teamCapacities']
        settings['capacityInitialized'] = False
        self.seed(docs)
        self.service().invoke('close', 'operator', self.body())
        self.assertEqual(self.get('activities/a')['status'], 'closed')
        s = self.get('activities/a/settings/matching')
        self.assertEqual(s['teamIds'], ['team_1', 'team_2', 'team_3'])
        self.assertEqual(s['teamCapacities'], {'team_1': 2, 'team_2': 2, 'team_3': 2})
        self.assertTrue(s['capacityInitialized'])
        self.assertEqual(s['settingsVersion'], 2)
        self.assertEqual(s['enabledQuestionIds'], docs['activities/a/settings/matching']['enabledQuestionIds'])

    def test_publish_teams_writes_publication_team_views_and_notifications(self):
        svc = self.service()
        self.assertTrue(svc.invoke('run', 'operator', self.body())['applied'])
        published = svc.invoke('publish', 'operator', self.body())
        self.assertEqual(published['seq'], 1)
        self.assertEqual(self.get('activities/a')['publishedVersion'], 1)
        pub = self.get('publications/a_v1')
        self.assertEqual(sorted(m['uid'] for t in pub['teams'] for m in t['members']), ['u0', 'u1', 'u2', 'u3'])
        for i in range(4):
            view = self.get(f'teamViews/a_u{i}')
            self.assertEqual((view['userId'], view['version'], view['groupId']), (f'u{i}', 1, 'g'))
            self.assertEqual(self.get(f'notifications/a_v1_u{i}')['type'], 'teamPublished')
        self.assertTrue(self.get('drafts/a')['discarded'])

    def id_token(self, uid):
        try:
            self.auth.get_user(uid)
        except self.auth.UserNotFoundError:
            self.auth.create_user(uid=uid, email=f'{uid}@example.test', password='password-123')
        host = os.environ['FIREBASE_AUTH_EMULATOR_HOST']
        url = f'http://{host}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake'
        data = json.dumps({'email': f'{uid}@example.test', 'password': 'password-123', 'returnSecureToken': True}).encode()
        with urllib.request.urlopen(urllib.request.Request(url, data, {'Content-Type': 'application/json'})) as r:
            return json.load(r)['idToken']

    def client_get(self, path, uid):
        """Read as a signed-in app user, so firestore.rules apply (Admin clients bypass them)."""
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        url = f'http://{host}/v1/projects/{PROJECT}/databases/(default)/documents/{path}'
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {self.id_token(uid)}'})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status
        except urllib.error.HTTPError as e:
            return e.code

    def test_main_rules_expose_results_only_to_the_right_people(self):
        svc = self.service()
        self.assertTrue(svc.invoke('run', 'operator', self.body())['applied'])
        svc.invoke('publish', 'operator', self.body())
        run_id = next(self.db.collection('serverRuns').stream()).id
        self.assertEqual(self.client_get('teamViews/a_u0', 'u0'), 200)
        self.assertEqual(self.client_get('teamViews/a_u1', 'u0'), 403)
        self.assertEqual(self.client_get('notifications/a_v1_u0', 'u0'), 200)
        self.assertEqual(self.client_get('notifications/a_v1_u0', 'u1'), 403)
        for path in ('drafts/a', 'publications/a_v1', 'activities/a/settings/matching'):
            self.assertEqual(self.client_get(path, 'operator'), 200, path)
            self.assertEqual(self.client_get(path, 'u0'), 403, path)
        for path in (f'serverRuns/{run_id}', f'formationRuns/{run_id}', 'placementPreferences/g_u0_u1'):
            self.assertEqual(self.client_get(path, 'operator'), 403, path)
        self.assertEqual(self.client_get('placementPreferences/g_u0_u1', 'u0'), 200)

    def test_http_commands_require_valid_admin_token(self):
        from fastapi.testclient import TestClient
        import server_v3
        app = server_v3.create_app()
        app.dependency_overrides[server_v3.get_service] = self.service
        client = TestClient(app)
        body = self.body()
        self.assertEqual(client.post('/generateDraft', json=body).status_code, 401)
        self.assertEqual(client.post('/generateDraft', json=body, headers={'Authorization': 'Bearer garbage'}).status_code, 401)
        member = client.post('/generateDraft', json=body, headers={'Authorization': f'Bearer {self.id_token("u0")}'})
        self.assertEqual(member.status_code, 403)
        admin = {'Authorization': f'Bearer {self.id_token("operator")}'}
        ok = client.post('/generateDraft', json=body, headers=admin)
        self.assertEqual(ok.status_code, 200, ok.text)
        self.assertTrue(ok.json()['applied'])
        self.assertNotIn('J_int', ok.text)
        self.assertEqual(client.post('/generateDraft', json=body, headers=admin).json(), {'status': 'STALE', 'applied': False})
        self.assertEqual(client.post('/run', json=body, headers=admin).status_code, 404)


if __name__ == '__main__':
    unittest.main()
