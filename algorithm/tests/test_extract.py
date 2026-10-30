"""Stage 6 extraction (편성학습_v3 6장, 개발단계 가이드 6단계 통과 기준)."""
import os
import unittest
import urllib.request
from datetime import datetime, timezone

from formation import assess, prepare
from learning.extract import build_rows, source_ref, extract_activity, pending, DATASET
from repository import build_state
from service import snapshot
import test_main_adapter as adapter
from test_main_adapter import main_docs, collect

STAMP = datetime(2026, 10, 30, tzinfo=timezone.utc)


def published_store(n=6):
    """Real stage-3 run + publish on main documents: 6 people, 2 teams of up to 3."""
    store = main_docs(n=n)
    store['activities/a/settings/matching']['teamCapacities'] = {'team_1': 3, 'team_2': 3}
    for i in range(n):
        store[f'registrations/a_u{i}']['answers']['experience'] = 1 + i % 5
    adapter.MainAdapterTests().run_and_publish(store)
    store['activities/a'].update(status='ended', endedVersion=1, feedbackClosedAt=STAMP)
    return store


def review(uid, team, overall=4, consent=True, ratio=1.0, comment=None, tags=None):
    return {'activityId': 'a', 'groupId': 'g', 'userId': uid, 'teamId': team, 'teamVersion': 1,
            'scores': {'overall': overall, 'schedule': 3, 'roles': 4, 'rejoin': 5}, 'comment': comment,
            'learningConsent': consent, 'membershipRatio': ratio,
            'commentTags': {'status': 'ok', 'tags': tags} if tags is not None else None}


def members(store, team):
    return next(t for t in store['publications/a_v1']['teams'] if t['teamId'] == team)['members']


def rows_for(store, feedback):
    return build_rows('a', store['activities/a'], store['activities/a/settings/matching'], store['publications/a_v1'], feedback)


class ExtractTests(unittest.TestCase):
    def setUp(self):
        self.store = published_store()
        self.t1 = [m['uid'] for m in members(self.store, 'team_1')]
        self.t2 = [m['uid'] for m in members(self.store, 'team_2')]

    def test_losses_equal_publication_and_independent_verifier(self):
        rows = rows_for(self.store, [review(u, 'team_1') for u in self.t1])
        row = rows['a_v1_team_1']
        saved = next(t for t in self.store['publications/a_v1']['teams'] if t['teamId'] == 'team_1')['losses']
        state = build_state('g', 'a', collect(self.store))
        s = prepare(snapshot(state, {'kind': 'republish'}, False))
        recomputed, _ = assess(s, {u: t['teamId'] for t in self.store['publications/a_v1']['teams'] for u in [m['uid'] for m in t['members']]})
        for q in ('time', 'role', 'experience', 'interest', 'size'):
            self.assertEqual(row[f'loss_{q}'], saved[q] / 1000)
            self.assertEqual(row[f'loss_{q}'], recomputed['publicSummary']['team_1']['losses'][q] / 1000)
            self.assertEqual(row[f'active_{q}'], 1)

    def test_unconsented_and_short_membership_reviews_excluded(self):
        a, b, c = self.t1
        rows = rows_for(self.store, [review(a, 'team_1', 5), review(b, 'team_1', 3), review(c, 'team_1', 1, consent=False)])
        self.assertEqual(rows['a_v1_team_1']['n_reviews'], 2)
        self.assertEqual(rows['a_v1_team_1']['y_overall'], 4)
        rows = rows_for(self.store, [review(a, 'team_1'), review(b, 'team_1', ratio=0.49), review(c, 'team_1', consent=False)])
        self.assertNotIn('a_v1_team_1', rows, '포함 후기 1개 → 행 제외')

    def test_rows_need_two_reviews_and_half_response(self):
        self.assertEqual(rows_for(self.store, [review(self.t1[0], 'team_1')]), {})
        rows = rows_for(self.store, [review(u, 'team_1') for u in self.t1[:2]] + [review(u, 'team_2') for u in self.t2])
        self.assertEqual(sorted(rows), ['a_v1_team_1', 'a_v1_team_2'])
        self.assertAlmostEqual(rows['a_v1_team_1']['response_rate'], 2 / 3)

    def test_reviews_of_other_versions_or_teams_ignored(self):
        old = [dict(review(u, 'team_1'), teamVersion=0) for u in self.t1]
        self.assertEqual(rows_for(self.store, old), {})

    def test_no_personal_data_in_rows(self):
        self.store['placementPreferences/g_u0_u1'] = {'groupId': 'g', 'userId': 'u0', 'targetUserId': 'u1', 'active': True}
        feedback = [review(u, 'team_1', comment=f'{u}의 비밀 후기', tags=[{'tag': 'schedule', 'sentiment': 'neg'}]) for u in self.t1]
        rows = rows_for(self.store, feedback)
        text = str(rows)
        for uid in self.t1 + self.t2:
            self.assertNotIn(f"'{uid}'", text)
        for word in ('비밀 후기', 'targetUserId', 'J_int', 'answers', 'displayName'):
            self.assertNotIn(word, text)
        refs = rows['a_v1_team_1']['sourceRefs']
        self.assertEqual(refs, sorted(source_ref(f'feedback/a_{u}') for u in self.t1))

    def test_tag_rates_over_tagged_reviews_only(self):
        a, b, c = self.t1
        feedback = [review(a, 'team_1', comment='x', tags=[{'tag': 'schedule', 'sentiment': 'neg'}]),
                    review(b, 'team_1', comment='y', tags=[{'tag': 'schedule', 'sentiment': 'pos'}, {'tag': 'roles', 'sentiment': 'neg'}]),
                    review(c, 'team_1')]
        row = rows_for(self.store, feedback)['a_v1_team_1']
        self.assertEqual((row['n_comments'], row['n_tagged']), (2, 2))
        self.assertEqual((row['tagrate_schedule_neg'], row['tagrate_schedule_pos'], row['tagrate_roles_neg']), (0.5, 0.5, 0.5))
        self.assertEqual(row['tagrate_atmosphere_pos'], 0)
        untagged = rows_for(self.store, [review(u, 'team_1') for u in self.t1])['a_v1_team_1']
        self.assertIsNone(untagged['tagrate_schedule_neg'])

    def test_unused_criteria_are_zero_and_history_fields(self):
        self.store['activities/a/settings/matching']['priority'] = ['role', 'size']
        row = rows_for(self.store, [review(u, 'team_1') for u in self.t1])['a_v1_team_1']
        self.assertEqual((row['active_time'], row['loss_time'], row['commonSlotCount']), (0, 0.0, 0))
        self.assertEqual((row['active_role'], row['active_size']), (1, 1))
        self.assertEqual((row['republishCount'], row['teamCount'], row['teamSize'], row['formationMode']), (0, 2, 3, 'balanced'))


EMULATED = bool(os.environ.get('FIRESTORE_EMULATOR_HOST'))
PROJECT = os.environ.get('GCLOUD_PROJECT') or os.environ.get('GOOGLE_CLOUD_PROJECT') or ''


@unittest.skipUnless(EMULATED and PROJECT.startswith('demo-'), 'Firestore 에뮬레이터(demo- 프로젝트)가 필요합니다')
class ExtractEmulatorTests(unittest.TestCase):
    def setUp(self):
        from google.cloud import firestore
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

    def test_extract_writes_rows_and_marker_then_is_not_pending(self):
        self.assertEqual(pending(self.db), ['a'])
        self.assertEqual(extract_activity(self.db, 'a'), {'status': 'done', 'rows': 1})
        row = self.db.document(f'trainingDatasets/{DATASET}/rows/a_v1_team_1').get().to_dict()
        self.assertEqual(row['n_reviews'], 3)
        self.assertEqual(self.db.document(f'trainingDatasets/{DATASET}').get().to_dict()['extractorVersion'], 'fx1')
        self.assertEqual(pending(self.db), [])

    def test_summary_change_re_extracts_and_removes_rows_that_no_longer_qualify(self):
        extract_activity(self.db, 'a')
        for u in self.t1[1:]:
            self.db.document(f'feedback/a_{u}').update({'learningConsent': False})
        self.db.document('activities/a/feedbackSummary/current').set({'updatedAt': datetime(2026, 10, 31, tzinfo=timezone.utc)})
        self.assertEqual(pending(self.db), ['a'])
        self.assertEqual(extract_activity(self.db, 'a')['rows'], 0)
        self.assertFalse(self.db.document(f'trainingDatasets/{DATASET}/rows/a_v1_team_1').get().exists)

    def test_open_feedback_is_not_extracted(self):
        self.db.document('activities/a').update({'feedbackClosedAt': None})
        self.assertEqual(pending(self.db), [])
        self.assertEqual(extract_activity(self.db, 'a')['status'], 'not_closed')


if __name__ == '__main__':
    unittest.main()
