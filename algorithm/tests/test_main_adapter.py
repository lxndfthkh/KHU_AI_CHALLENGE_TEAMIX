"""main Firestore schema adapter (docs/FIRESTORE.md) without Firebase: pure translation tests."""
import unittest
from copy import deepcopy
from datetime import datetime, timezone
from repository import build_state, translate
from service import FormationService, Invalid, versions
from formation import digest

STAMP = datetime(2026, 10, 30, tzinfo=timezone.utc)


def main_docs(n=4, target=2):
    """Main-schema documents: question IDs equal criterion names for readability."""
    docs = {
        'activities/a': {'groupId': 'g', 'title': 'demo', 'status': 'closed', 'targetTeamSize': target,
                         'capacity': 30, 'participantCount': n, 'publishedVersion': None},
        'activities/a/settings/matching': {
            'method': 'balanced', 'enabledQuestionIds': ['role', 'time', 'experience', 'interest'],
            'questionCriteria': {'role': 'role', 'time': 'time', 'experience': 'experience', 'interest': 'interest'},
            'priority': ['time', 'role', 'experience', 'interest', 'size'],
            'teamIds': ['team_1', 'team_2'], 'teamCapacities': {'team_1': 2, 'team_2': 2},
            'capacityInitialized': True, 'settingsVersion': 1},
        'activities/a/questions/role': {'type': 'single', 'enabled': True, 'options': [{'id': 'dev', 'label': '개발'}, {'id': 'design', 'label': '디자인'}]},
        'activities/a/questions/time': {'type': 'multiple', 'enabled': True, 'options': [{'id': 'wed', 'label': '수'}]},
        'activities/a/questions/experience': {'type': 'scale', 'enabled': True, 'options': []},
        'activities/a/questions/interest': {'type': 'multiple', 'enabled': True, 'options': [{'id': 'web', 'label': '웹'}]},
        'memberships/g_operator': {'groupId': 'g', 'userId': 'operator', 'displayName': 'O', 'role': 'admin', 'status': 'approved'},
    }
    for i in range(n):
        docs[f'memberships/g_u{i}'] = {'groupId': 'g', 'userId': f'u{i}', 'displayName': f'N{i}', 'role': 'member', 'status': 'approved'}
        docs[f'registrations/a_u{i}'] = {'activityId': 'a', 'groupId': 'g', 'userId': f'u{i}', 'status': 'submitted',
                                          'updatedAt': STAMP, 'answers': {'role': 'dev' if i % 2 else 'design', 'time': ['wed'],
                                                                          'experience': i + 1, 'interest': ['web']}}
    return docs


def collect(store, a='a'):
    def under(prefix):
        return {p.rsplit('/', 1)[1]: deepcopy(v) for p, v in store.items() if p.startswith(prefix) and '/' not in p[len(prefix):]}
    version = (store.get(f'activities/{a}') or {}).get('publishedVersion')
    return {'activity': deepcopy(store.get(f'activities/{a}')), 'settings': deepcopy(store.get(f'activities/{a}/settings/matching')),
            'questions': under(f'activities/{a}/questions/'), 'memberships': under('memberships/'),
            'registrations': under('registrations/'), 'draft': deepcopy(store.get(f'drafts/{a}')),
            'publication': deepcopy(store.get(f'publications/{a}_v{version}')) if version else None,
            'preferences': list(under('placementPreferences/').values()), 'teamViews': under('teamViews/')}


class MemoryMainRepository:
    """Applies translate() output to a dict of main-schema documents, atomically per call."""
    def __init__(self, store):
        self.store = store
    def atomic(self, work):
        repo, pending = self, []
        state = build_state('g', 'a', collect(self.store))
        class Tx:
            def load(self, g, a):
                return deepcopy(state)
            def set(self, path, value, merge=False):
                pending.append((path, deepcopy(value), merge))
        result = work(Tx())
        for op, path, value, merge in translate('g', 'a', state, pending, STAMP):
            if op == 'delete':
                repo.store.pop(path, None)
            else:
                repo.store[path] = {**repo.store.get(path, {}), **value} if merge else value
        return result


class MainAdapterTests(unittest.TestCase):
    def adapter(self):
        """Internal service state built from main documents (shared fixture for other test files)."""
        return None, None, build_state('g', 'a', collect(main_docs()))

    def test_roles_and_status_from_flat_memberships(self):
        docs = main_docs()
        docs['memberships/g_u3']['status'] = 'pending'
        docs['memberships/other_x'] = {'groupId': 'other', 'userId': 'x', 'role': 'admin', 'status': 'approved'}
        s = build_state('g', 'a', collect(docs))
        self.assertEqual(s['members']['operator']['role'], 'officer')
        self.assertEqual(s['members']['u0']['role'], 'participant')
        self.assertEqual(s['members']['u3']['status'], 'pending')
        self.assertNotIn('x', s['members'])

    def test_activity_status_mapping(self):
        for status, version, state in [('recruiting', None, 'recruiting'), ('closed', None, 'forming'),
                                       ('closed', 1, 'published'), ('active', 1, 'in_progress'),
                                       ('ended', 1, 'ended'), ('cancelled', None, 'cancelled')]:
            docs = main_docs()
            docs['activities/a'].update(status=status, publishedVersion=version)
            if version:
                docs['publications/a_v1'] = {'teams': []}
            self.assertEqual(build_state('g', 'a', collect(docs))['activity']['state'], state)

    def test_team_count_from_target_team_size_before_close(self):
        docs = main_docs(n=5, target=2)
        settings = docs['activities/a/settings/matching']
        del settings['teamIds'], settings['teamCapacities']
        settings['capacityInitialized'] = False
        s = build_state('g', 'a', collect(docs))
        self.assertEqual(s['activity']['teamIds'], ['team_1', 'team_2', 'team_3'])
        self.assertEqual(s['activity']['capacity'], {'team_1': None, 'team_2': None, 'team_3': None})

    def test_saved_team_ids_are_never_recomputed(self):
        docs = main_docs(n=4, target=1)
        self.assertEqual(build_state('g', 'a', collect(docs))['activity']['teamIds'], ['team_1', 'team_2'])

    def test_question_type_must_match_criterion(self):
        docs = main_docs()
        docs['activities/a/questions/role']['type'] = 'multiple'
        with self.assertRaises(Invalid):
            build_state('g', 'a', collect(docs))
        docs = main_docs()
        del docs['activities/a/settings/matching']['questionCriteria']['time']
        with self.assertRaises(Invalid):
            build_state('g', 'a', collect(docs))

    def test_cancelled_registration_and_inactive_preference_excluded(self):
        docs = main_docs()
        docs['registrations/a_u3']['status'] = 'cancelled'
        docs['placementPreferences/g_u0_u1'] = {'groupId': 'g', 'userId': 'u0', 'targetUserId': 'u1', 'active': True}
        docs['placementPreferences/g_u1_u2'] = {'groupId': 'g', 'userId': 'u1', 'targetUserId': 'u2', 'active': False}
        docs['placementPreferences/h_u2_u3'] = {'groupId': 'h', 'userId': 'u2', 'targetUserId': 'u3', 'active': True}
        s = build_state('g', 'a', collect(docs))
        self.assertEqual(s['applications']['u3']['status'], 'cancelled')
        self.assertEqual([(p['ownerUid'], p['targetUid']) for p in s['preferences'].values()], [('u0', 'u1')])

    def test_roster_token_changes_with_answers(self):
        docs = main_docs()
        before = build_state('g', 'a', collect(docs))['activity']['rosterVersion']
        docs['registrations/a_u0']['updatedAt'] = datetime(2026, 10, 31, tzinfo=timezone.utc)
        self.assertNotEqual(before, build_state('g', 'a', collect(docs))['activity']['rosterVersion'])

    def test_settings_patch_written_to_settings_matching(self):
        s = build_state('g', 'a', collect(main_docs()))
        ops = translate('g', 'a', s, [('groups/g/activities/a', {
            'teamIds': ['team_1', 'team_2'], 'capacity': {'team_1': 3, 'team_2': 2}, 'formationMode': 'similar',
            'criteria': [{'key': k, 'priority': i + 1} for i, k in enumerate(['role', 'time', 'experience', 'interest', 'size'])],
            'extraRequirements': [{'type': 'requiredRole', 'teamId': 'team_1', 'role': 'dev', 'minimum': 1}],
            'settingsVersion': 2}, True)], STAMP)
        (op, path, value, merge), = ops
        self.assertEqual((op, path, merge), ('set', 'activities/a/settings/matching', True))
        self.assertEqual(value['priority'][0], 'role')
        self.assertEqual(value['requiredRoles'], [{'teamId': 'team_1', 'optionId': 'dev', 'minimum': 1}])
        self.assertEqual(value['teamCapacities'], {'team_1': 3, 'team_2': 2})
        self.assertFalse(value['requireCommonTime'])

    def test_question_change_in_formation_rejected(self):
        s = build_state('g', 'a', collect(main_docs()))
        with self.assertRaises(Invalid):
            translate('g', 'a', s, [('groups/g/activities/a', {'criteria': [{'key': 'size', 'priority': 1}]}, True)], STAMP)

    def run_and_publish(self, store):
        svc = FormationService(MemoryMainRepository(store))
        def body():
            v = versions(build_state('g', 'a', collect(store)))
            return {'groupId': 'g', 'activityId': 'a', 'kind': 'republish' if store['activities/a'].get('publishedVersion') else 'initial',
                    'limit': 2, 'expected': {k: v[k] for k in ('roster', 'settings', 'draft')}}
        out = svc.invoke('run', 'operator', body())
        self.assertTrue(out['applied'], out)
        return svc.invoke('publish', 'operator', body())

    def test_full_run_publish_roundtrip_in_main_layout(self):
        store = main_docs()
        self.run_and_publish(store)
        self.assertEqual(store['activities/a']['publishedVersion'], 1)
        self.assertEqual(store['activities/a']['status'], 'closed')
        pub = store['publications/a_v1']
        self.assertEqual((pub['activityId'], pub['groupId'], pub['version'], pub['publishedBy']), ('a', 'g', 1, 'operator'))
        self.assertEqual(sorted(m['uid'] for t in pub['teams'] for m in t['members']), ['u0', 'u1', 'u2', 'u3'])
        draft = store['drafts/a']
        self.assertEqual((draft['activityId'], draft['groupId'], draft['status']), ('a', 'g', 'ready'))
        self.assertEqual([t['teamId'] for t in draft['teams']], ['team_1', 'team_2'])
        for i in range(4):
            view = store[f'teamViews/a_u{i}']
            self.assertEqual((view['userId'], view['version'], view['compositionChanged']), (f'u{i}', 1, False))
            self.assertIn(f'u{i}', [m['uid'] for m in view['members']])
            self.assertEqual(view['commonTimes'], ['wed'])
            self.assertEqual(store[f'notifications/a_v1_u{i}']['type'], 'teamPublished')
        self.assertNotIn('teamViews/a_operator', store)
        self.assertFalse(any(p.startswith(('groups/', 'activities/a/drafts', 'activities/a/publications')) for p in store))

    def test_republish_notifies_only_changed_and_removes_cancelled_view(self):
        store = main_docs(n=4)
        self.run_and_publish(store)
        teams = {v['userId']: v['teamId'] for k, v in store.items() if k.startswith('teamViews/')}
        mate = next(u for u, t in teams.items() if t == teams['u0'] and u != 'u0')
        store['registrations/a_u0']['status'] = 'cancelled'
        store['activities/a/settings/matching']['teamCapacities'] = {'team_1': 3, 'team_2': 3}
        self.run_and_publish(store)
        self.assertNotIn('teamViews/a_u0', store)
        changed = sorted(k for k in store if k.startswith('notifications/a_v2_'))
        self.assertEqual(changed, [f'notifications/a_v2_{mate}'])
        self.assertEqual(store[f'notifications/a_v2_{mate}']['type'], 'teamChanged')
        self.assertTrue(store[f'teamViews/a_{mate}']['compositionChanged'])

    def test_private_preferences_never_copied_to_shared_documents(self):
        store = main_docs()
        store['placementPreferences/g_u0_u1'] = {'groupId': 'g', 'userId': 'u0', 'targetUserId': 'u1', 'active': True}
        self.run_and_publish(store)
        shared = {k: v for k, v in store.items() if k.startswith(('drafts/', 'publications/', 'teamViews/', 'notifications/', 'activities/', 'formationRuns/'))}
        for word in ('targetUserId', 'targetUid', 'J_int', 'private_preferences'):
            self.assertNotIn(word, str(shared))
        self.assertIn('private_preferences', str({k: v for k, v in store.items() if k.startswith('serverRuns/')}))

    def test_fingerprint_catches_private_and_answer_edit(self):
        docs = main_docs()
        before = digest(build_state('g', 'a', collect(docs)))
        docs['placementPreferences/g_u0_u1'] = {'groupId': 'g', 'userId': 'u0', 'targetUserId': 'u1', 'active': True}
        after_pref = digest(build_state('g', 'a', collect(docs)))
        self.assertNotEqual(before, after_pref)
        docs['registrations/a_u0']['answers']['experience'] = 5
        self.assertNotEqual(after_pref, digest(build_state('g', 'a', collect(docs))))


if __name__ == '__main__':
    unittest.main()
