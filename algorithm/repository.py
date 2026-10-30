"""main Firestore schema adapter (docs/FIRESTORE.md, firestore.schema.json).

The formation service keeps its internal names (officer/applied/teamVersions);
this module is the only place that knows main's storage layout:

  memberships/{g}_{uid}                     role admin|member, status approved|...
  activities/{a}                            status, targetTeamSize, publishedVersion
  activities/{a}/settings/matching          admin-only engine contract (fields below)
  activities/{a}/questions/{qid}            single|multiple|scale, options [{id,label}]
  registrations/{a}_{uid}                   submitted|cancelled, answers keyed by qid
  placementPreferences/{g}_{uid}_{target}   active; server-only input
  drafts/{a}                                one working draft per activity (admin read)
  publications/{a}_v{n}                     publication (admin read); only validTo is set later
  teamViews/{a}_{uid}                       participant's own team
  notifications/{a}_v{n}_{uid}              teamPublished | teamChanged
  formationRuns/{run}, serverRuns/{run}     server-only (default-deny paths)
  appConfig/learning                        active model {activeModelId, b} (stage 7-8)

settings/matching engine fields, added next to main's method/enabledQuestionIds:
  questionCriteria {qid: role|time|experience|interest}, priority [criteria..., 'size'],
  requireCommonTime, requiredRoles [{teamId, optionId, minimum}],
  teamIds, teamCapacities {teamId: int|null}, capacityInitialized, settingsVersion,
  learningEnabled (default true; per-activity switch for learned correction factors).
Reads precede buffered writes; Admin SDK bypasses rules, so the service checks roles.
"""
from copy import deepcopy
from datetime import datetime, timezone
import math
from service import Missing, Invalid
from formation import digest

CRITERIA = {'role': 'single', 'time': 'multiple', 'interest': 'multiple', 'experience': 'scale'}
STATE = {'recruiting': 'recruiting', 'active': 'in_progress', 'ended': 'ended', 'cancelled': 'cancelled'}
STATUS = {'recruiting': 'recruiting', 'forming': 'closed', 'published': 'closed', 'in_progress': 'active', 'ended': 'ended'}


def team_ids(settings, roster_size, target):
    """Saved team IDs win; before closing, K = ceil(N / targetTeamSize)."""
    if settings.get('teamIds'):
        return list(settings['teamIds'])
    if type(target) is not int or target < 1:
        raise Invalid('팀당 목표 인원을 확인해 주세요')
    return [f'team_{i+1}' for i in range(max(1, math.ceil(roster_size / target)))]


def build_state(g, a, docs):
    """Main documents -> internal service state. Pure; also used by memory tests."""
    source = docs['activity']
    if source is None or source.get('groupId') != g:
        raise Missing()
    settings = docs.get('settings') or {}
    members = {}
    for m in docs['memberships'].values():
        if m.get('groupId') != g or not isinstance(m.get('userId'), str):
            continue
        members[m['userId']] = {'role': 'officer' if m.get('role') == 'admin' else 'participant',
                                'status': 'active' if m.get('status') == 'approved' else m.get('status'),
                                'displayName': m.get('displayName') or m['userId']}
    registrations = {r['userId']: r for r in docs['registrations'].values()
                     if r.get('activityId') == a and r.get('groupId') == g and isinstance(r.get('userId'), str)}
    criteria_of = settings.get('questionCriteria', {})
    questions = {}
    for qid in settings.get('enabledQuestionIds', []):
        q = docs['questions'].get(qid)
        key = criteria_of.get(qid)
        if q is None or not q.get('enabled', True) or key not in CRITERIA or q.get('type') != CRITERIA[key]:
            raise Invalid('편성 기준 질문 설정을 확인해 주세요')
        scale = [1, 2, 3, 4, 5] if key == 'experience' else [o['id'] for o in q.get('options', [])]
        questions[qid] = {'id': qid, 'key': key, 'questionVersion': 1, 'scale': scale}
    if len({q['key'] for q in questions.values()}) != len(questions):
        raise Invalid('같은 편성 기준에 질문이 두 개 연결되어 있습니다')
    applications = {uid: {'status': 'applied' if r.get('status') == 'submitted' else r.get('status'),
                          'answerVersion': r.get('updatedAt'),
                          'answers': {qid: {'questionVersion': 1, 'value': v} for qid, v in (r.get('answers') or {}).items()}}
                    for uid, r in registrations.items()}
    roster = [u for u, r in applications.items() if r['status'] == 'applied' and members.get(u, {}).get('status') == 'active']
    tids = team_ids(settings, len(roster), source.get('targetTeamSize'))
    caps = settings.get('teamCapacities') or {}
    if set(caps) - set(tids):
        raise Invalid('삭제된 팀 정원을 제거해 주세요')
    priority = settings.get('priority') or [q['key'] for q in questions.values()] + ['size']
    extra = [{'type': 'commonTime'}] if settings.get('requireCommonTime') else []
    extra += [{'type': 'requiredRole', 'teamId': r['teamId'], 'role': r['optionId'], 'minimum': r['minimum']}
              for r in settings.get('requiredRoles', [])]
    version = source.get('publishedVersion')
    status = source.get('status')
    state = ('published' if version else 'forming') if status == 'closed' else STATE.get(status, status)
    roster_token = digest(sorted((u, r['status'], str(r['answerVersion'])) for u, r in applications.items()))[:16]
    activity = {'state': state, 'rosterVersion': roster_token, 'settingsVersion': settings.get('settingsVersion', 1),
                'teamIds': tids, 'capacity': {t: caps.get(t) for t in tids},
                'capacityInitialized': settings.get('capacityInitialized', False),
                'criteria': [{'key': k, 'priority': i+1} for i, k in enumerate(priority)],
                'formationMode': settings.get('method', 'balanced'), 'extraRequirements': extra,
                'publishedVersionId': f'v{version}' if version else None}
    publication = docs.get('publication') or {}
    published = {m['uid']: t['teamId'] for t in publication.get('teams', []) for m in t.get('members', [])}
    preferences = {}
    for p in docs['preferences']:
        if p.get('groupId') == g and p.get('active') is True and p.get('userId') != p.get('targetUserId'):
            preferences[digest([p['userId'], p['targetUserId']])] = {
                'ownerUid': p['userId'], 'targetUid': p['targetUserId'], 'status': 'active'}
    notified = {v['userId']: {'peers': sorted(m['uid'] for m in v.get('members', []) if m['uid'] != v['userId'])}
                for v in docs['teamViews'].values() if v.get('activityId') == a}
    config = docs.get('learning') or {}
    learning = {'enabled': settings.get('learningEnabled', True) is not False,
                'modelId': config.get('activeModelId'), 'b': config.get('b')}
    return {'activity': activity, 'members': members, 'questions': questions, 'applications': applications,
            'draft': draft_from_doc(docs.get('draft') or {}), 'meta': {}, 'preferences': preferences,
            'published': published, 'publishedMeta': {'seq': version or 0}, 'notified': notified, 'learning': learning}


def draft_from_doc(d):
    if not d:
        return {}
    out = {k: deepcopy(d[k]) for k in ('version', 'locks', 'discarded', 'sourceRunId', 'manuallyEdited') if k in d}
    if 'basedOnPublishedVersion' in d:
        out['basedOnPublishedVersionId'] = f"v{d['basedOnPublishedVersion']}" if d['basedOnPublishedVersion'] else None
    if 'teams' in d:
        out['assignments'] = {**{u: None for u in d.get('unassigned', [])},
                              **{u: t['teamId'] for t in d['teams'] for u in t['members']}}
    return out


def draft_to_doc(g, a, d, team_order, stamp):
    out = {'activityId': a, 'groupId': g, 'version': d.get('version', 0), 'status': 'ready',
           'discarded': d.get('discarded', False), 'updatedAt': stamp}
    if 'assignments' in d:
        assignments = d['assignments']
        order = list(team_order) + sorted({t for t in assignments.values() if t is not None} - set(team_order))
        out['teams'] = [{'teamId': t, 'members': sorted(u for u, v in assignments.items() if v == t)} for t in order]
        out['unassigned'] = sorted(u for u, v in assignments.items() if v is None)
    for k in ('locks', 'sourceRunId', 'manuallyEdited'):
        if k in d:
            out[k] = deepcopy(d[k])
    if 'requiredStatus' in d:
        out['validation'] = {**deepcopy(d['requiredStatus']), 'summary': deepcopy(d.get('publicSummary', {}))}
    if 'basedOnPublishedVersionId' in d:
        v = d['basedOnPublishedVersionId']
        out['basedOnPublishedVersion'] = int(v[1:]) if v else None
    return out


def settings_doc(patch, state):
    s = {}
    if 'teamIds' in patch or 'capacity' in patch:
        s['teamIds'] = list(patch.get('teamIds') or patch.get('capacity') or state['activity']['teamIds'])
    if 'capacity' in patch:
        s['teamCapacities'] = dict(patch['capacity'])
    if 'formationMode' in patch:
        s['method'] = patch['formationMode']
    if 'criteria' in patch:
        order = [c['key'] for c in sorted(patch['criteria'], key=lambda c: c['priority'])]
        if {k for k in order if k != 'size'} != {q['key'] for q in state['questions'].values()}:
            raise Invalid('편성 기준 질문은 소모임을 만들 때만 정할 수 있습니다')
        s['priority'] = order
    if 'extraRequirements' in patch:
        rules = patch['extraRequirements']
        s['requireCommonTime'] = any(r['type'] == 'commonTime' for r in rules)
        s['requiredRoles'] = [{'teamId': r['teamId'], 'optionId': r['role'], 'minimum': r['minimum']}
                              for r in rules if r['type'] == 'requiredRole']
    for k in ('capacityInitialized', 'settingsVersion', 'learningEnabled'):
        if k in patch:
            s[k] = patch[k]
    return s


def publication_writes(g, a, state, publication, stamp):
    """Publication + every participant's teamView + notifications for changed compositions only."""
    n = publication['version']
    out = [('set', f'publications/{a}_v{n}', publication, False)]
    role_q = next((q['id'] for q in state['questions'].values() if q['key'] == 'role'), None)
    seen = set()
    for team in publication['teams']:
        uids = [m['uid'] for m in team['members']]
        members = [{**m, 'role': state['applications'].get(m['uid'], {}).get('answers', {}).get(role_q, {}).get('value')
                    if role_q else None} for m in team['members']]
        for uid in uids:
            seen.add(uid)
            old = state['notified'].get(uid)
            changed = old is not None and old['peers'] != sorted(u for u in uids if u != uid)
            out.append(('set', f'teamViews/{a}_{uid}', {
                'activityId': a, 'groupId': g, 'userId': uid, 'version': n, 'teamId': team['teamId'],
                'members': members, 'commonTimes': team.get('commonTimes', []),
                'compositionChanged': changed, 'publishedAt': publication['publishedAt']}, False))
            if old is None or changed:
                out.append(('set', f'notifications/{a}_v{n}_{uid}', {
                    'userId': uid, 'type': 'teamPublished' if old is None else 'teamChanged',
                    'groupId': g, 'activityId': a, 'createdAt': stamp, 'readAt': None}, False))
    out += [('delete', f'teamViews/{a}_{uid}', None, False) for uid in state['notified'] if uid not in seen]
    return out


def translate(g, a, state, pending, stamp):
    """Internal buffered writes -> [(op, path, value, merge)] in main's layout."""
    prefix = f'groups/{g}/activities/{a}'
    out, publication, activity_patch, settings_patch = [], None, {}, {}
    for path, value, merge in pending:
        if path.startswith('serverRuns/'):
            out.append(('set', path, value, merge))
            continue
        if not path.startswith(prefix):
            continue  # internal notifications are rebuilt in main's shape by publication_writes
        parts = [p for p in path[len(prefix):].split('/') if p]
        if not parts:
            if 'state' in value:
                activity_patch['status'] = STATUS[value['state']]
            settings_patch.update({k: v for k, v in value.items() if k not in ('state', 'publishedVersionId')})
        elif parts[0] == 'teamVersions' and len(parts) == 2 and 'seq' not in value and 'validTo' in value:
            # Previous publication ends when the next one starts (membershipRatio in stage 4).
            out.append(('set', f'publications/{a}_{parts[1]}', {'validTo': value['validTo']}, True))
        elif parts[0] == 'teamVersions' and len(parts) == 2 and 'seq' in value:
            publication = {'activityId': a, 'groupId': g, 'version': value['seq'], 'teams': [],
                           'publishedBy': value['publishedBy'], 'publishedAt': value['publishedAt'],
                           'validFrom': value.get('validFrom', value['publishedAt']), 'validTo': None,
                           'sourceRunId': value.get('sourceRunId'), 'manuallyEdited': value.get('manuallyEdited', False)}
            activity_patch['publishedVersion'] = value['seq']
        elif parts[0] == 'teamVersions' and len(parts) == 4:
            publication['teams'].append({'teamId': parts[3], 'members': [
                {'uid': u, 'displayName': state['members'].get(u, {}).get('displayName', u)} for u in value['members']],
                **value.get('publicMetrics', {}), 'losses': value.get('losses')})
        elif parts[0] == 'draft':
            out.append(('set', f'drafts/{a}', draft_to_doc(g, a, value, state['activity']['teamIds'], stamp), False))
        elif parts[0] == 'draftHistory':
            out.append(('set', f'drafts/{a}/history/{parts[1]}',
                        draft_to_doc(g, a, value, state['activity']['teamIds'], stamp), False))
        elif parts[0] == 'formationRuns':
            out.append(('set', f'formationRuns/{parts[1]}', {**value, 'activityId': a, 'groupId': g}, merge))
    if settings_patch:
        out.append(('set', f'activities/{a}/settings/matching', {**settings_doc(settings_patch, state), 'updatedAt': stamp}, True))
    if publication:
        out += publication_writes(g, a, state, publication, stamp)
    if activity_patch:
        out.append(('set', f'activities/{a}', {**activity_patch, 'updatedAt': stamp}, True))
    return out


class Transaction:
    def __init__(self, db, transaction):
        self.db, self.tx = db, transaction
        self.pending, self.loaded = [], None

    def one(self, path):
        snap = self.db.document(path).get(transaction=self.tx)
        return snap.to_dict() if snap.exists else None

    def where(self, collection, **equal):
        from google.cloud.firestore_v1.base_query import FieldFilter
        query = self.db.collection(collection)
        for field, value in equal.items():
            query = query.where(filter=FieldFilter(field, '==', value))
        return {d.id: d.to_dict() for d in query.stream(transaction=self.tx)}

    def load(self, g, a):
        activity = self.one(f'activities/{a}')
        if activity is None or activity.get('groupId') != g:
            raise Missing()
        version = activity.get('publishedVersion')
        docs = {'activity': activity, 'settings': self.one(f'activities/{a}/settings/matching'),
                'questions': {d.id: d.to_dict() for d in self.db.collection(f'activities/{a}/questions').stream(transaction=self.tx)},
                'memberships': self.where('memberships', groupId=g),
                'registrations': self.where('registrations', activityId=a),
                'draft': self.one(f'drafts/{a}'),
                'publication': self.one(f'publications/{a}_v{version}') if version else None,
                'preferences': list(self.where('placementPreferences', groupId=g, active=True).values()),
                'teamViews': self.where('teamViews', activityId=a),
                'learning': self.one('appConfig/learning')}
        self.loaded = (g, a, build_state(g, a, docs))
        return deepcopy(self.loaded[2])

    def set(self, path, value, merge=False):
        self.pending.append((path, deepcopy(value), merge))

    def flush(self):
        if not self.pending:
            return
        g, a, state = self.loaded
        for op, path, value, merge in translate(g, a, state, self.pending, datetime.now(timezone.utc)):
            ref = self.db.document(path)
            if op == 'delete':
                self.tx.delete(ref)
            else:
                self.tx.set(ref, value, merge=merge)


class FirestoreRepository:
    def __init__(self, db): self.db = db

    def atomic(self, callback):
        from firebase_admin import firestore

        @firestore.transactional
        def execute(tx):
            adapter = Transaction(self.db, tx)
            result = callback(adapter)
            adapter.flush()
            return result
        return execute(self.db.transaction())
