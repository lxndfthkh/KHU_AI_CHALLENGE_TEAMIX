"""Production-boundary regression tests. No Firebase credentials or network."""
import unittest
from copy import deepcopy
from formation import Invalid, solve
from service import Denied, Stale, versions
from validated_service import ValidatedFormationService, checked_solver
import test_main_adapter as adapter_tests


class MemoryRepository:
    def __init__(self, state):
        self.state = deepcopy(state)
        self.documents = {}
    def atomic(self, work):
        repo = self
        pending = []
        class Transaction:
            def load(self, group, activity):
                return deepcopy(repo.state)
            def set(self, path, value, merge=False):
                pending.append((path, deepcopy(value), merge))
        result = work(Transaction())
        for path, value, merge in pending:
            self.documents[path] = ({**self.documents.get(path, {}), **value}
                                    if merge else value)
            if path.endswith('/draft/current'):
                self.state['draft'] = deepcopy(self.documents[path])
            if path == 'groups/g/activities/a':
                self.state['activity'].update(value)
        return result


class Stage3BoundaryTests(unittest.TestCase):
    def setUp(self):
        _, _, state = adapter_tests.MainAdapterTests().adapter()
        self.repo = MemoryRepository(state)
        self.service = ValidatedFormationService(self.repo)
    def body(self, **patch):
        current = versions(self.repo.state)
        return {'groupId':'g', 'activityId':'a', 'kind':'initial', 'limit':0.2,
                'expected':{key:current[key] for key in ('roster','settings','draft')}, **patch}
    def test_login_required_before_storage(self):
        for uid in (None, '', ' '):
            with self.assertRaises(Denied):
                self.service.invoke('run', uid, self.body())
        self.assertEqual(self.repo.documents, {})
    def test_participant_and_inactive_officer_denied(self):
        with self.assertRaises(Denied):
            self.service.invoke('run', 'u0', self.body())
        self.repo.state['members']['operator']['status'] = 'left'
        with self.assertRaises(Denied):
            self.service.invoke('run', 'operator', self.body())
        self.assertEqual(self.repo.documents, {})
    def test_unknown_action_and_invalid_body(self):
        for action, body in [('unknown', self.body()), ('run', [])]:
            with self.assertRaises(Invalid):
                self.service.invoke(action, 'operator', body)
    def test_partial_requires_unique_explicit_scope(self):
        for scope in (None, [], ['team_1', 'team_1'], ['../private']):
            with self.assertRaises(Invalid):
                self.service.invoke('run', 'operator', self.body(kind='partial', scopeTeamIds=scope))
    def test_initial_rejects_ignored_scope(self):
        with self.assertRaises(Invalid):
            self.service.invoke('run', 'operator', self.body(scopeTeamIds=['team_1']))
    def test_republish_requires_publication(self):
        with self.assertRaises(Invalid):
            self.service.invoke('run', 'operator', self.body(kind='republish'))
    def test_expected_version_checked_before_solver(self):
        calls = []
        svc = ValidatedFormationService(self.repo, lambda raw: calls.append(raw))
        body = self.body(); body['expected']['draft'] += 1
        with self.assertRaises(Stale):
            svc.invoke('run', 'operator', body)
        self.assertEqual(calls, [])
        self.assertEqual(self.repo.documents, {})
    def mutate_during_solver(self, mutation):
        def solver(raw):
            result = solve(raw)
            mutation(self.repo.state)
            return result
        response = ValidatedFormationService(self.repo, solver).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'STALE')
        self.assertFalse(response['applied'])
        self.assertNotIn('publicSummary', response)
        self.assertFalse(any(path.endswith('/draft/current') for path in self.repo.documents))
        self.assertTrue(any(path.startswith('serverRuns/') for path in self.repo.documents))
    def test_stale_after_roster_change(self):
        self.mutate_during_solver(lambda s:s['activity'].update(rosterVersion=5))
    def test_stale_after_settings_change(self):
        self.mutate_during_solver(lambda s:s['activity'].update(settingsVersion=2))
    def test_stale_after_draft_change(self):
        self.mutate_during_solver(lambda s:s['draft'].update(version=1))
    def test_stale_after_answer_change(self):
        self.mutate_during_solver(lambda s:s['applications']['u0']['answers']['experience'].update(value=5))
    def test_stale_after_private_preference_change(self):
        self.mutate_during_solver(lambda s:s['preferences'].update(p={'ownerUid':'u0','targetUid':'u1','status':'active'}))
    def test_stale_after_private_counter_change(self):
        self.mutate_during_solver(lambda s:s['meta'].update(prefVersion=1))
    def test_solver_exception_becomes_generic_error(self):
        def bad(raw):
            raise RuntimeError('secret preference: u0 -> u1')
        response = ValidatedFormationService(self.repo, bad).invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'ERROR')
        self.assertNotIn('secret', str(response))
        self.assertFalse(response['applied'])
        self.assertEqual(self.repo.state['draft'], {})
    def test_raw_conflicts_and_proof_cannot_leak(self):
        def bad(raw):
            return {'status':'INFEASIBLE', 'stageProof':{'pub':{'targetUid':'SECRET'}, 'secret':'SECRET'},
                    'conflicts':['SECRET'], 'internal':{'secret':'SECRET'}}
        response = ValidatedFormationService(self.repo, bad).invoke('run', 'operator', self.body())
        public_records = [v for k,v in self.repo.documents.items() if '/formationRuns/' in k]
        self.assertNotIn('SECRET', str(response))
        self.assertNotIn('SECRET', str(public_records))
        self.assertIn('SECRET', str([v for k,v in self.repo.documents.items() if k.startswith('serverRuns/')]))
    def test_invalid_assignments_never_replace_draft(self):
        svc = ValidatedFormationService(self.repo, lambda raw:{'status':'OPTIMAL','assignments':{'u0':'team_1'}})
        response = svc.invoke('run', 'operator', self.body())
        self.assertEqual(response['status'], 'ERROR')
        self.assertEqual(self.repo.state['draft'], {})
    def test_independent_summary_not_solver_summary(self):
        def tampered(raw):
            result = solve(raw)
            result['publicSummary'] = {'secret':'SECRET'}
            result['stageProof']['secret'] = 'SECRET'
            return result
        response = ValidatedFormationService(self.repo, tampered).invoke('run', 'operator', self.body())
        self.assertTrue(response['applied'])
        self.assertNotIn('SECRET', str(response))
        self.assertEqual(set(response['publicSummary']), {'team_1','team_2'})
    def test_run_does_not_publish(self):
        response = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(response['applied'])
        self.assertIsNone(self.repo.state['activity']['publishedVersionId'])
        self.assertFalse(any('/teamVersions/' in path for path in self.repo.documents))
    def test_publish_requires_current_draft_version(self):
        old = self.body()
        response = self.service.invoke('run', 'operator', old)
        self.assertTrue(response['applied'])
        with self.assertRaises(Stale):
            self.service.invoke('publish', 'operator', old)
    def test_settings_rejected_after_publication(self):
        self.repo.state['activity']['publishedVersionId'] = 'p1'
        with self.assertRaises(Invalid):
            self.service.invoke('settings', 'operator', self.body(patch={}))
    def test_settings_allowed_during_recruiting(self):
        self.repo.state['activity']['state'] = 'recruiting'
        result = self.service.invoke('settings', 'operator', self.body(patch={'formationMode':'similar'}))
        self.assertEqual(result['settingsVersion'], 2)
    def test_terminal_states_reject_formation(self):
        for state in ('ended', 'review_closed'):
            self.repo.state['activity']['state'] = state
            with self.assertRaises(Invalid):
                self.service.invoke('run', 'operator', self.body())
    def test_failed_solver_keeps_previous_draft(self):
        first = self.service.invoke('run', 'operator', self.body())
        self.assertTrue(first['applied'])
        draft = deepcopy(self.repo.state['draft'])
        svc = ValidatedFormationService(self.repo, lambda raw:{'status':'LIMIT_NO_CANDIDATE'})
        response = svc.invoke('run', 'operator', self.body())
        self.assertFalse(response['applied'])
        self.assertEqual(draft, self.repo.state['draft'])

if __name__ == '__main__':
    unittest.main()
