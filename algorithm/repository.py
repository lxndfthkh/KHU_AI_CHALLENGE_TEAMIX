"""Canonical main storage adapter. Legacy solver names exist only in memory.
Reads precede buffered writes; no legacy members/activities/teamVersions are stored.
"""
from copy import deepcopy
from datetime import datetime, timezone
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from service import Missing, Invalid
from formation import digest


def normalize(activity, runtime, members, applications):
    q = activity['questions']
    settings = activity['matchingSettings']
    count = settings['teamCount']
    tids = runtime.get('teamIds', [f'team_{i+1}' for i in range(count)])
    if len(tids) != count or len(set(tids)) != count:
        raise Invalid('서버 팀 ID와 설정이 일치하지 않습니다')
    caps = settings['teamCapacities']
    if len(caps) != count:
        raise Invalid('팀 정원 설정을 확인해 주세요')
    selected = q['selected']
    questions = {key: {'id': key, 'key': key, 'questionVersion': activity['settingsVersion'],
                 'scale': [1,2,3,4,5] if key == 'experience' else q[key+'Options']}
                 for key in selected}
    view = deepcopy(activity)
    view.update(state={'recruiting':'recruiting','closed':'forming','active':'in_progress','ended':'ended'}[activity['status']],
        rosterVersion=activity['responseVersion'], teamIds=tids,
        capacity=dict(zip(tids, caps)), criteria=[{'key': k, 'priority':i+1} for i,k in enumerate(settings['priority'])],
        formationMode=settings['method'], extraRequirements=deepcopy(runtime.get('extraRequirements', [])),
        publishedVersionId=activity.get('currentPublicationId'), capacityInitialized=True)
    if settings.get('requireCommonTime'):
        view['extraRequirements'] = [r for r in view['extraRequirements'] if r['type'] != 'commonTime'] + [{'type':'commonTime'}]
    view['extraRequirements'] += [{'type':'requiredRole', 'teamId':r['team'], 'role':r['role'], 'minimum':r['minimum']}
        for r in settings.get('requiredRoles', [])]
    normalized_apps = {}
    for uid, app in applications.items():
        normalized_apps[uid] = {**deepcopy(app), 'status':'applied' if app.get('status') == 'submitted' else app.get('status'),
            'answerVersion':app.get('updatedAt'), 'answers':{key:{'questionVersion':activity['settingsVersion'], 'value':value}
                for key,value in app.get('answers', {}).items()}}
    normalized_members = {uid:{**m, 'sourceRole':m.get('role'),
        'role':'officer' if m.get('role') in ('owner','admin') else 'participant',
        'status':'active' if m.get('role') in ('owner','admin','member') else 'invalid'} for uid,m in members.items()}
    return view, questions, normalized_members, normalized_apps


class Transaction:
    def __init__(self, db, transaction):
        self.db, self.tx = db, transaction
        self.pending = []
        self.context = {}
    def one(self, path):
        snap = self.db.document(path).get(transaction=self.tx)
        return snap.to_dict() if snap.exists else None
    def many(self, path):
        return {d.id:d.to_dict() for d in self.db.collection(path).stream(transaction=self.tx)}
    def load(self, g, a):
        base = f'activities/{a}'
        source = self.one(base)
        if source is None or source.get('groupId') != g:
            raise Missing()
        runtime = self.one(base+'/private/runtime') or {}
        members = self.many(f'groups/{g}/memberships')
        applications = self.many(base+'/applications')
        activity, questions, members, apps = normalize(source, runtime, members, applications)
        version = source.get('currentPublicationId')
        publication = self.one(base+'/publications/'+version) if version else {}
        publication = publication or {}
        published = {uid:team['team_id'] for team in publication.get('teams', [])
                     for uid in team.get('participants', [])}
        query = self.db.collection_group('groups').where(filter=FieldFilter('groupId','==',g))
        preferences = {}
        for d in query.stream(transaction=self.tx):
            parts = d.reference.path.split('/')
            if len(parts) != 4 or parts[0] != 'privatePreferences' or parts[2] != 'groups' or parts[3] != g:
                continue
            data = d.to_dict()
            if data.get('authorUid') != parts[1]:
                continue
            for t in data.get('targets', []):
                if t.get('confirmed') is True:
                    key = digest([parts[1],t['targetUid']])
                    preferences[key] = {'ownerUid':parts[1], 'targetUid':t['targetUid'], 'status':'active'}
        draft = self.one(base+'/drafts/current') or {}
        if draft.get('revision',0) > draft.get('version',0):
            raise Invalid('기존 클라이언트가 수정한 초안입니다. 서버에서 재편성 후 검토해 주세요')
        self.context[base] = {'source':source,'runtime':runtime,'members':members,'applications':applications,
                              'publication':publication}
        return {'activity':activity,'members':members,'questions':questions,'applications':apps,
            'draft':draft, 'meta':{}, 'preferences':preferences,
            'published':published, 'publishedMeta':{'seq':publication.get('version',0)},
            'notified':self.many(base+'/lastNotified')}
    def set(self, path, value, merge=False):
        if path.startswith('groups/') and '/activities/' in path:
            path = 'activities/'+path.split('/activities/',1)[1]
        self.pending.append((path,deepcopy(value),merge))
    def flush(self):
        publications = {}
        for path,value,merge in self.pending:
            if path.startswith('activities/'):
                parts = path.split('/')
                base = '/'.join(parts[:2])
                ctx = self.context[base]
                if len(parts) == 2:
                    source = ctx['source']
                    patch = {'updatedAt':datetime.now(timezone.utc)}
                    runtime = {}
                    if 'state' in value:
                        patch['status'] = {'forming':'closed','published':'closed','in_progress':'active','recruiting':'recruiting','ended':'ended'}[value['state']]
                    if 'publishedVersionId' in value:
                        patch['currentPublicationId'] = value['publishedVersionId']
                        patch['publicationVersion'] = source['publicationVersion']+1
                    if 'settingsVersion' in value: patch['settingsVersion'] = value['settingsVersion']
                    ms = deepcopy(source['matchingSettings'])
                    if 'teamIds' in value:
                        runtime['teamIds'] = value['teamIds']; ms['teamCount'] = len(value['teamIds'])
                    tids = value.get('teamIds',ctx['runtime'].get('teamIds',[f'team_{i+1}' for i in range(ms['teamCount'])]))
                    if 'capacity' in value: ms['teamCapacities'] = [value['capacity'][t] for t in tids]
                    if 'criteria' in value:
                        ms['priority'] = [c['key'] for c in sorted(value['criteria'],key=lambda c:c['priority'])]
                        if {k for k in ms['priority'] if k != 'size'} != set(source['questions']['selected']):
                            raise Invalid('질문 선택 변경은 모집 단계에서만 가능합니다')
                    if 'formationMode' in value: ms['method'] = value['formationMode']
                    if 'extraRequirements' in value:
                        ms['requireCommonTime'] = any(r['type']=='commonTime' for r in value['extraRequirements'])
                        ms['requiredRoles'] = [{'team':r['teamId'],'role':r['role'],'minimum':r['minimum']}
                                              for r in value['extraRequirements'] if r['type']=='requiredRole']
                        runtime['extraRequirements'] = []
                    if any(k in value for k in ('teamIds','capacity','criteria','formationMode','extraRequirements')):
                        patch['matchingSettings'] = ms
                    self.tx.set(self.db.document(base),patch,merge=True)
                    if runtime: self.tx.set(self.db.document(base+'/private/runtime'),runtime,merge=True)
                    continue
                if '/teamVersions/' in path:
                    version = parts[3]
                    pubpath = base+'/publications/'+version
                    if len(parts) == 4:
                        self.tx.set(self.db.document(base+'/publicationAudit/'+version),value,merge=True)
                        if 'seq' not in value:
                            continue
                        publications[pubpath] = {'version':value['seq'],'sourceDraftId':'current',
                            'publishedBy':value['publishedBy'],'publishedAt':value['publishedAt'],
                            'teams':[], 'displayProfiles':{}}
                    else:
                        for uid in value['members']:
                            publications[pubpath]['displayProfiles'][uid] = {'nickname':ctx['members'].get(uid,{}).get('nickname',uid)}
                        publications[pubpath]['teams'].append({'team_id':parts[5],
                            'participants':value['members'],**value.get('publicMetrics',{})})
                    continue
                path = path.replace('/draft/current','/drafts/current')
                if '/drafts/current' in path:
                    value['revision'] = value.get('version',0)
                    value['sourceResponseVersion'] = ctx['source']['responseVersion']
                    value['sourceSettingsVersion'] = ctx['source']['settingsVersion']
                    value['editedTeams'] = [{'team_id':t,'participants':[u for u,v in value.get('assignments',{}).items() if v==t]}
                        for t in sorted(set(v for v in value.get('assignments',{}).values() if v is not None))]
            self.tx.set(self.db.document(path),value,merge=merge)
        for path,value in publications.items():
            self.tx.set(self.db.document(path),value)


class FirestoreRepository:
    def __init__(self, db): self.db = db
    def atomic(self, callback):
        @firestore.transactional
        def execute(tx):
            adapter = Transaction(self.db,tx)
            result = callback(adapter)
            adapter.flush()
            return result
        return execute(self.db.transaction())
