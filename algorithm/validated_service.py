"""Defence-in-depth boundary for the production formation service.

Keep the main-schema adapter and the existing engine intact. Do not use the
legacy FormationService directly from a production entry point.
"""
from copy import deepcopy
from formation import Invalid, VALID, prepare, assess
from service import FormationService, Denied, path_id

ACTIONS = frozenset({'precheck', 'run', 'edit', 'publish', 'discard', 'close', 'settings'})
KINDS = frozenset({'initial', 'republish', 'partial'})


def clean_proof(value):
    value = value if isinstance(value, dict) else {}
    return {key: value.get(key) is True for key in ('pub', 'quality', 'draft')}


def checked_solver(solver):
    """Only independently verified public fields may reach formationRuns.

    A malformed solver result becomes a generic ERROR. Exception messages and
    raw diagnostics are retained exclusively in the server-only internal log.
    """
    def execute(raw):
        try:
            result = solver(deepcopy(raw))
            if not isinstance(result, dict):
                raise Invalid('Invalid engine result')
            status = result.get('status')
            if status not in VALID | {'INFEASIBLE', 'LIMIT_NO_CANDIDATE', 'ERROR'}:
                raise Invalid('Invalid engine status')
            internal = result.get('internal', {})
            if not isinstance(internal, dict):
                internal = {'diagnostic': internal}
            out = {'status': status, 'stageProof': clean_proof(result.get('stageProof')),
                   'conflicts': [], 'internal': deepcopy(internal)}
            if status in VALID:
                assignments = result.get('assignments')
                if not isinstance(assignments, dict):
                    raise Invalid('Invalid assignments')
                public, verified = assess(prepare(raw), assignments)
                if verified is None:
                    raise Invalid('Independent verification failed')
                out.update(public)
                out['assignments'] = deepcopy(assignments)
            elif status == 'INFEASIBLE':
                # Use a generic public diagnostic. Never copy raw solver
                # conflict text to an operator-visible record.
                out['conflicts'] = ['필수 조건을 함께 충족할 수 없습니다. 공개 조건을 확인해 주세요.']
            return out
        except Exception as exc:
            return {'status': 'ERROR', 'stageProof': clean_proof(None), 'conflicts': [],
                    'internal': {'errorType': type(exc).__name__}}
    return execute


class ValidatedFormationService(FormationService):
    def __init__(self, repository, solver=None):
        if solver is None:
            from formation import solve
            solver = solve
        super().__init__(repository, checked_solver(solver))

    def invoke(self, action, uid, body):
        if not isinstance(uid, str) or not uid.strip():
            raise Denied()
        if action not in ACTIONS:
            raise Invalid('지원하지 않는 작업')
        if not isinstance(body, dict):
            raise Invalid('요청 객체가 필요합니다')
        path_id(body.get('groupId'))
        path_id(body.get('activityId'))
        body = deepcopy(body)
        if action == 'run':
            kind = body.setdefault('kind', 'initial')
            if kind not in KINDS:
                raise Invalid('실행 종류를 확인해 주세요')
            if kind == 'partial':
                scope = body.get('scopeTeamIds')
                if not isinstance(scope, list) or not scope:
                    raise Invalid('부분 재편성 범위가 필요합니다')
                for team_id in scope:
                    path_id(team_id)
                if len(scope) != len(set(scope)):
                    raise Invalid('재편성 범위가 중복되었습니다')
            elif 'scopeTeamIds' in body:
                raise Invalid('부분 재편성에서만 범위를 지정할 수 있습니다')
        service = self
        class GuardedTransaction:
            def __init__(self, tx):
                self.tx = tx
            def load(self, g, a):
                s = self.tx.load(g, a)
                # Enforce role before inspecting settings or publication state.
                member = s['members'].get(uid, {})
                if member.get('status') != 'active' or member.get('role') != 'officer':
                    raise Denied()
                activity = s['activity']
                if action == 'settings' and (activity.get('state') not in ('recruiting', 'forming')
                                            or activity.get('publishedVersionId')):
                    raise Invalid('공개 이후에는 설정을 변경할 수 없습니다')
                if action == 'run' and body['kind'] != 'initial' and not activity.get('publishedVersionId'):
                    raise Invalid('공개 전에는 처음 편성을 선택해 주세요')
                return s
            def __getattr__(self, name):
                return getattr(self.tx, name)
        class GuardedRepository:
            def atomic(self, fn):
                return service.repo.atomic(lambda tx: fn(GuardedTransaction(tx)))
        class RequestService(FormationService):
            def state(self, tx, actor, g, a, forming=True):
                return super().state(tx, actor, g, a, forming=False if action == 'settings' else forming)
        return RequestService(GuardedRepository(), self.solver).invoke(action, uid, body)
