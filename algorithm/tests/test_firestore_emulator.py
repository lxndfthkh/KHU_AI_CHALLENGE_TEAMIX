"""실제 Firestore·Auth 에뮬레이터 검증 (편성알고리즘 v3 13-1 8번, 개발단계 가이드 3단계).

에뮬레이터가 없으면 건너뛴다. 실행:
  cd algorithm && npx firebase emulators:exec --only firestore,auth --project demo-teamix-stage3 \
    ".venv/bin/python -m unittest discover -s tests -p 'test_firestore_emulator.py' -v"
demo- 프로젝트 ID만 허용하므로 실제 Firebase 프로젝트에는 접근하지 않는다.
"""
import json
import os
import unittest
import urllib.request
from datetime import datetime, timezone

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

    def setUp(self):
        host = os.environ['FIRESTORE_EMULATOR_HOST']
        req = urllib.request.Request(f'http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents',
                                     method='DELETE')
        urllib.request.urlopen(req).close()
        db = self.db
        db.document('activities/a').set({
            'groupId': 'g', 'title': 'demo', 'status': 'closed', 'responseVersion': 4, 'settingsVersion': 1,
            'currentPublicationId': None, 'publicationVersion': 0,
            'questions': {'selected': ['role', 'time', 'experience', 'interest'], 'roleOptions': ['dev', 'design'],
                          'timeOptions': ['wed'], 'interestOptions': ['web']},
            'matchingSettings': {'teamCount': 2, 'teamCapacities': [2, 2], 'method': 'balanced',
                                 'priority': ['time', 'role', 'experience', 'interest', 'size'],
                                 'requireCommonTime': False}})
        db.document('groups/g/memberships/operator').set({'role': 'owner', 'nickname': 'O'})
        for i in range(4):
            db.document(f'groups/g/memberships/u{i}').set({'role': 'member', 'nickname': f'N{i}'})
            db.document(f'activities/a/applications/u{i}').set({
                'status': 'submitted', 'updatedAt': datetime(2026, 10, 30, tzinfo=timezone.utc),
                'answers': {'role': 'dev' if i % 2 else 'design', 'time': ['wed'], 'experience': i + 1,
                            'interest': ['web']}})
        db.document('privatePreferences/u0/groups/g').set({
            'groupId': 'g', 'authorUid': 'u0', 'targets': [{'targetUid': 'u1', 'confirmed': True}]})

    def service(self, solver=None):
        from repository import FirestoreRepository
        from validated_service import ValidatedFormationService
        return ValidatedFormationService(FirestoreRepository(self.db), solver)

    def body(self, **patch):
        return {'groupId': 'g', 'activityId': 'a', 'kind': 'initial', 'limit': 2,
                'expected': {'roster': 4, 'settings': 1, 'draft': 0}, **patch}

    def operator_visible(self):
        docs = [d.to_dict() for d in self.db.collection('activities/a/formationRuns').stream()]
        draft = self.db.document('activities/a/drafts/current').get()
        return docs + ([draft.to_dict()] if draft.exists else [])

    def test_run_writes_draft_and_keeps_private_values_server_only(self):
        response = self.service().invoke('run', 'operator', self.body())
        self.assertTrue(response['applied'], response)
        draft = self.db.document('activities/a/drafts/current').get().to_dict()
        self.assertEqual(sorted(draft['assignments']), ['u0', 'u1', 'u2', 'u3'])
        self.assertNotEqual(draft['assignments']['u0'], draft['assignments']['u1'])
        for doc in self.operator_visible() + [response]:
            text = str(doc)
            for word in ('J_int', 'private_preferences', 'targetUid', 'prefVersion'):
                self.assertNotIn(word, text)
        runs = [d.to_dict() for d in self.db.collection('serverRuns').stream()]
        self.assertEqual(len(runs), 1)
        self.assertIn('J_int', str(runs[0]['internal']))

    def test_answer_change_during_solve_is_stale_in_real_transaction(self):
        from formation import solve
        db = self.db

        def solver(raw):
            result = solve(raw)
            db.document('activities/a/applications/u0').update({'answers.experience': 5})
            db.document('activities/a').update({'responseVersion': 5})
            return result

        response = self.service(solver).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'STALE')
        self.assertFalse(response['applied'])
        self.assertFalse(db.document('activities/a/drafts/current').get().exists)
        statuses = [d.to_dict()['status'] for d in db.collection('serverRuns').stream()]
        self.assertEqual(statuses, ['STALE'])

    def test_private_preference_change_during_solve_is_stale(self):
        from formation import solve
        db = self.db

        def solver(raw):
            result = solve(raw)
            db.document('privatePreferences/u0/groups/g').update({'targets': []})
            return result

        response = self.service(solver).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'STALE')
        self.assertFalse(db.document('activities/a/drafts/current').get().exists)

    def test_publish_after_run_in_real_transaction(self):
        svc = self.service()
        run = svc.invoke('run', 'operator', self.body())
        self.assertTrue(run['applied'])
        published = svc.invoke('publish', 'operator', self.body(expected={'roster': 4, 'settings': 1, 'draft': run['draftVersion']}))
        activity = self.db.document('activities/a').get().to_dict()
        self.assertEqual(activity['currentPublicationId'], published['publishedVersionId'])
        pub = self.db.document(f"activities/a/publications/{published['publishedVersionId']}").get().to_dict()
        self.assertEqual(sorted(u for t in pub['teams'] for u in t['participants']), ['u0', 'u1', 'u2', 'u3'])

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

    def test_http_api_requires_valid_officer_token(self):
        from fastapi.testclient import TestClient
        import server_v3
        app = server_v3.create_app()
        app.dependency_overrides[server_v3.get_service] = self.service
        client = TestClient(app)
        self.assertEqual(client.post('/run', json=self.body()).status_code, 401)
        self.assertEqual(client.post('/run', json=self.body(), headers={'Authorization': 'Bearer garbage'}).status_code, 401)
        participant = client.post('/run', json=self.body(), headers={'Authorization': f'Bearer {self.id_token("u0")}'})
        self.assertEqual(participant.status_code, 403)
        officer = client.post('/run', json=self.body(), headers={'Authorization': f'Bearer {self.id_token("operator")}'})
        self.assertEqual(officer.status_code, 200, officer.text)
        self.assertTrue(officer.json()['applied'])
        self.assertNotIn('J_int', officer.text)
        stale = client.post('/run', json=self.body(), headers={'Authorization': f'Bearer {self.id_token("operator")}'})
        self.assertEqual(stale.json(), {'status': 'STALE', 'applied': False})


if __name__ == '__main__':
    unittest.main()
