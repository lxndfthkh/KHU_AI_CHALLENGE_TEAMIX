"""Transactional formation service. All sensitive data stays on the server."""
from copy import deepcopy
from datetime import datetime, timezone
import uuid
from formation import prepare, assess, solve, digest, Invalid, require, VALID, ENGINE_VERSION

class Denied(Exception): pass
class Missing(Exception): pass
class Stale(Exception): pass


def path_id(value):
    require(isinstance(value,str) and 0 < len(value) <= 128 and all(c.isascii() and (c.isalnum() or c in '_-') for c in value), '잘못된 ID')
    return value


def expected(s, e):
    v=versions(s)
    if not isinstance(e,dict) or any(type(e.get(k)) is not int for k in ('roster','settings','draft')):
        raise Invalid('expected.roster/settings/draft 정수가 필요합니다')
    if any(e[k] != v[k] for k in ('roster','settings','draft')): raise Stale()


def versions(s):
    return {'roster':s['activity'].get('rosterVersion',0),'settings':s['activity'].get('settingsVersion',0),
            'draft':s['draft'].get('version',0),'answers':digest({i:{'version':a.get('answerVersion'),'answers':a.get('answers')} for i,a in s['applications'].items()})}


def fingerprint(s):
    return digest(s)


def base_draft(s):
    a=s['activity']; existing=s['draft']
    roster={i for i,v in s['applications'].items() if v.get('status') == 'applied' and s['members'].get(i,{}).get('status') == 'active'}
    published=s['published']
    assignments=existing.get('assignments') if not existing.get('discarded',False) else None
    if assignments is None: assignments=published
    assignments={i:assignments.get(i) for i in sorted(roster)}
    locks={i:v for i,v in existing.get('locks',{}).items() if i in roster} if not existing.get('discarded') else {}
    if not existing.get('assignments') or existing.get('discarded'):
        locks={i:{'teamId':t,'type':'default'} for i,t in assignments.items() if t in a['teamIds']}
    return {**existing,'assignments':assignments,'locks':locks,'basedOnPublishedVersionId':a.get('publishedVersionId'),'discarded':False}


def snapshot(s, body, include_private=True):
    a=s['activity']; draft=base_draft(s)
    criteria=sorted(a['criteria'],key=lambda c:c['priority'])
    selected=[c['key'] for c in criteria if c['key'] != 'size']
    questions={q['key']:q for q in s['questions'].values() if q['key'] in selected}
    require(set(questions) == set(selected),'질문 설정을 확인해 주세요')
    participants=[]
    for uid,app in sorted(s['applications'].items()):
        if app.get('status') != 'applied' or s['members'].get(uid,{}).get('status') != 'active': continue
        answers={}
        for key,q in questions.items():
            ans=app.get('answers',{}).get(q['id'],{})
            require(ans.get('questionVersion') == q['questionVersion'],f'{uid}: {key} 응답 버전을 확인해 주세요')
            val=ans.get('value')
            if key in ('time','interest') and isinstance(val,str): val=[val]
            if key == 'role' and isinstance(val,list) and len(val) == 1: val=val[0]
            answers[key]=val
        participants.append({'id':uid,'answers':answers})
    roles=[]; common=False
    for rule in a.get('extraRequirements',[]):
        require(rule.get('type') in ('requiredRole','commonTime'),'알 수 없는 필수 조건')
        if rule['type'] == 'requiredRole': roles.append({'team':rule['teamId'],'role':rule['role'],'minimum':rule['minimum']})
        else: common=True
    raw={'participants':participants,'teams':[{'id':t,'capacity':a['capacity'].get(t)} for t in a['teamIds']],
         'selected_questions':selected,'priority':[c['key'] for c in criteria], 'method':a['formationMode'],
         'categories':{k:q['scale'] for k,q in questions.items() if k != 'experience'},
         'published':s['published'],'draft':draft['assignments'],'locks':draft['locks'],
         'required_roles':roles,'require_common_time':common,'seed':body.get('seed',42),'limit':body.get('limit',10),
         'private_preferences':[{'source':p['ownerUid'],'target':p['targetUid'],'confirmed':True} for p in s['preferences'].values() if p.get('status') == 'active'] if include_private else []}
    if body.get('kind') == 'partial': raw['scopeTeamIds']=body.get('scopeTeamIds')
    require(body.get('kind','initial') in ('initial','republish','partial'),'실행 종류 확인 필요')
    require(body.get('kind') != 'initial' or not s['published'],'공개 후에는 재편성을 선택해 주세요')
    return raw


def project(result):
    out={k:deepcopy(result[k]) for k in ('status','stageProof','publicSummary','requiredStatus','conflicts') if k in result}
    if out.get('status') == 'ERROR': out['conflicts']=[]
    return out


class FormationService:
    def __init__(self, repository, solver=solve):
        self.repo=repository; self.solver=solver

    def state(self, tx, uid, g, a, forming=True):
        s=tx.load(g,a)
        member=s['members'].get(uid,{})
        if member.get('status') != 'active' or member.get('role') != 'officer': raise Denied()
        allowed=('forming','published','in_progress') if forming else ('recruiting','forming','published','in_progress')
        if s['activity'].get('state') not in allowed: raise Invalid('현재 활동 상태에서는 허용되지 않습니다')
        return s

    def invoke(self, action, uid, body):
        g=path_id(body.get('groupId')); a=path_id(body.get('activityId'))
        base=f'groups/{g}/activities/{a}'
        stamp=datetime.now(timezone.utc)
        if action == 'run': return self.run(uid,g,a,body,base,stamp)
        def work(tx):
            s=self.state(tx,uid,g,a,forming=action != 'close')
            if action != 'precheck': expected(s,body.get('expected'))
            if action == 'settings':
                patch=body.get('patch',{})
                require(isinstance(patch,dict) and set(patch) <= {'teamIds','capacity','criteria','formationMode','extraRequirements'},'설정 항목 확인 필요')
                changed={**s['activity'],**patch}
                tids=changed.get('teamIds',[])
                require(isinstance(tids,list) and 0 < len(tids) <= 100 and all(isinstance(t,str) for t in tids) and len(set(tids)) == len(tids),'팀 ID 확인 필요')
                for t in tids: path_id(t)
                n=sum(v.get('status') == 'applied' for v in s['applications'].values())
                cap=dict(changed.get('capacity',{}))
                require(set(cap) <= set(tids),'삭제된 팀 정원을 제거해 주세요')
                for t in tids:
                    if t not in cap: cap[t]=max(1,(n+len(tids)-1)//len(tids))
                changed['capacity']=cap
                criteria=changed.get('criteria',[])
                require(isinstance(criteria,list) and 0 < len(criteria) <= 5,'기준 확인 필요')
                require(sorted(c.get('priority',0) for c in criteria) == list(range(1,len(criteria)+1)),'우선순위 확인 필요')
                probe={**s,'activity':changed}
                dummy=snapshot(probe,{'kind':'republish'},False)
                dummy['locks']={};dummy['draft']={};dummy.pop('scopeTeamIds',None)
                prepare(dummy)
                output={k:changed[k] for k in ('teamIds','criteria','formationMode','extraRequirements')}
                output.update(capacity=cap,capacityInitialized=True,settingsVersion=s['activity'].get('settingsVersion',0)+1)
                tx.set(base,output,merge=True)
                return {'settingsVersion':output['settingsVersion'],'notice':'팀 수가 바뀌었다면 기존 팀 정원을 확인해 주세요'}
            if action == 'close':
                require(s['activity']['state'] == 'recruiting','이미 마감되었습니다')
                n=sum(v.get('status') == 'applied' and s['members'].get(i,{}).get('status') == 'active' for i,v in s['applications'].items())
                require(n > 0,'참가자가 없습니다')
                cap=dict(s['activity']['capacity'])
                if not s['activity'].get('capacityInitialized',False):
                    cap={t:(cap.get(t) if cap.get(t) is not None else (n+len(cap)-1)//len(cap)) for t in cap}
                tx.set(base,{'state':'forming','capacity':cap,'capacityInitialized':True,'settingsVersion':s['activity'].get('settingsVersion',0)+1},merge=True)
                return {'state':'forming'}
            if action == 'precheck':
                try:
                    raw=snapshot(s,body,False); normalized=prepare(raw)
                    errors=[]; N=len(raw['participants']); K=len(raw['teams'])
                    if N < K: errors.append('참가자보다 팀이 많습니다')
                    caps=[t['capacity'] for t in raw['teams']]
                    if all(c is not None for c in caps) and sum(caps) < N: errors.append('전체 최대 정원이 부족합니다')
                    for t in raw['teams']:
                        if t['capacity'] is not None and list(normalized['fixed'].values()).count(t['id']) > t['capacity']: errors.append(f'{t["id"]}: 고정 인원이 정원을 초과합니다')
                    for role in sorted({r['role'] for r in normalized['required_roles']}):
                        have=sum(p['answers'].get('role') == role for p in normalized['participants'])
                        need=sum(max([r['minimum'] for r in normalized['required_roles'] if r['role'] == role and r['team'] == t['id']] or [0]) for t in raw['teams'])
                        if have < need: errors.append(f'{role} 역할 희망자는 {have}명인데 필수 역할 최소 인원 합은 {need}명입니다')
                    scope=normalized.get('scopeTeamIds')
                    if scope is not None:
                        caps={t['id']:t['capacity'] for t in raw['teams'] if t['id'] in scope}
                        if caps and all(c is not None for c in caps.values()):
                            seats=sum(c-list(normalized['fixed'].values()).count(t) for t,c in caps.items())
                            placing=sum(p['id'] not in normalized['fixed'] for p in normalized['participants'])
                            if seats < placing: errors.append(f'선택한 팀의 남은 자리는 {seats}개인데 새로 배정할 참가자는 {placing}명입니다')
                    return {'valid':not errors,'conflicts':errors,'versions':versions(s),'feasibilityProven':False}
                except Invalid as e: return {'valid':False,'conflicts':[str(e)],'versions':versions(s),'feasibilityProven':False}
            if action == 'edit':
                d=base_draft(s); assignments=d['assignments']; locks=d['locks']
                operations=body.get('operations',[])
                require(isinstance(operations,list) and 0 < len(operations) <= 200,'편집 작업을 확인해 주세요')
                for op in operations:
                    kind=op.get('type'); who=op.get('uid')
                    require(who in assignments,'현재 참가자만 편집할 수 있습니다')
                    if kind in ('assign','move'):
                        team=op.get('teamId'); require(team in s['activity']['teamIds'] or team is None,'잘못된 팀')
                        require(who not in locks or locks[who]['teamId'] == team,'고정 해제 후 이동해 주세요')
                        assignments[who]=team
                    elif kind == 'swap':
                        other=op.get('otherUid'); require(other in assignments and who not in locks and other not in locks,'맞교환 전 고정을 해제해 주세요')
                        assignments[who],assignments[other]=assignments[other],assignments[who]
                    elif kind == 'lock':
                        require(assignments[who] in s['activity']['teamIds'],'배정 후 고정해 주세요')
                        locks[who]={'teamId':assignments[who],'type':'manual'}
                    elif kind == 'unlock': locks.pop(who,None)
                    else: raise Invalid('지원하지 않는 편집 작업')
                raw=snapshot({**s,'draft':d},body,False); normalized=prepare(raw)
                public,_=assess(normalized,assignments)
                d.update(public); d.update(version=s['draft'].get('version',0)+1,updatedAt=stamp,manuallyEdited=True,sourceRunId=None)
                tx.set(base+'/draft/current',d)
                return {'draftVersion':d['version'],**public}
            if action == 'discard':
                require(bool(s['activity'].get('publishedVersionId')),'공개 후 수정용 초안만 폐기할 수 있습니다')
                version=s['draft'].get('version',0)+1
                tx.set(base+'/draft/current',{'version':version,'discarded':True,'updatedAt':stamp})
                return {'discarded':True,'draftVersion':version}
            if action == 'publish':
                require(not s['draft'].get('discarded') and bool(s['draft'].get('assignments')),'검토할 초안이 없습니다')
                raw=snapshot(s,body,False); normalized=prepare(raw)
                assignment=s['draft']['assignments']; public,_=assess(normalized,assignment)
                require(public['requiredStatus']['valid'],'필수 조건을 다시 확인해 주세요')
                version=uuid.uuid4().hex
                previous=s['activity'].get('publishedVersionId')
                seq=s.get('publishedMeta',{}).get('seq',0)+1
                tx.set(base+'/teamVersions/'+version,{'seq':seq,'publishedAt':stamp,'publishedBy':uid,'prevVersionId':previous,
                    'sourceRunId':s['draft'].get('sourceRunId'),'manuallyEdited':s['draft'].get('manuallyEdited',False),
                    'validFrom':stamp,'validTo':None})
                if previous: tx.set(base+'/teamVersions/'+previous,{'validTo':stamp},merge=True)
                for tid,item in public['publicSummary'].items():
                    tx.set(base+'/teamVersions/'+version+'/teams/'+tid,{'members':item['members'],'publicMetrics':{k:v for k,v in item.items() if k not in ('members','losses')},'losses':item['losses']})
                tx.set(base,{'publishedVersionId':version,'state':'published' if s['activity']['state'] == 'forming' else s['activity']['state']},merge=True)
                for person,tid in assignment.items():
                    peers=sorted(i for i,t in assignment.items() if t == tid and i != person)
                    old=s['notified'].get(person)
                    if old is None or old.get('peers') != peers:
                        tx.set(base+'/notificationOutbox/'+version+'_'+person,{'uid':person,'versionId':version,'kind':'first_team' if old is None else 'team_changed','message':'내 팀이 배정됐어요' if old is None else '내 팀이 바뀌었어요','createdAt':stamp,'delivered':False})
                        tx.set('notifications/'+version+'_'+person,{'ownerUid':person,'groupId':g,'activityId':a,'versionId':version,'message':'내 팀이 배정됐어요' if old is None else '내 팀이 바뀌었어요','createdAt':stamp})
                        tx.set(base+'/lastNotified/'+person,{'peers':peers,'versionId':version})
                d=deepcopy(s['draft']); d.update(version=d.get('version',0)+1,discarded=True,updatedAt=stamp)
                tx.set(base+'/draft/current',d)
                return {'publishedVersionId':version,'seq':seq}
            raise Invalid('지원하지 않는 작업')
        return self.repo.atomic(work)

    def run(self,uid,g,a,body,base,stamp):
        def capture(tx):
            s=self.state(tx,uid,g,a); expected(s,body.get('expected'))
            raw=snapshot(s,body); prepare(raw)
            return s,raw
        s,raw=self.repo.atomic(capture)
        result=self.solver(raw)
        run_id=uuid.uuid4().hex
        def apply(tx):
            current=self.state(tx,uid,g,a)
            stale=fingerprint(current) != fingerprint(s)
            status='STALE' if stale else result.get('status','ERROR')
            if status not in VALID|{'INFEASIBLE','LIMIT_NO_CANDIDATE','STALE','ERROR'}: status='ERROR'
            if status in VALID:
                public,internal=assess(prepare(raw),result.get('assignments',{}))
                if internal is None: status='ERROR'
            response=project({**result,'status':status})
            if status in VALID:
                response.update(public)
                response['movementSummary']={'publishedMoved':internal['M_pub'], 'deletedTeamMoved':sum(t not in s['activity']['teamIds'] for i,t in s['published'].items() if i in result['assignments'])}
                if s['published'] and internal['M_pub'] == 0:
                    response['notice']='기존 배정을 그대로 유지할 수 있어 기존 팀원은 이동하지 않았습니다. 새 참가자만 배정했습니다.'
            if status in ('STALE','ERROR'):
                response={k:v for k,v in response.items() if k not in ('publicSummary','requiredStatus')}
            response.update(runId=run_id,applied=status in VALID)
            record={**response,'requestedBy':uid,'createdAt':stamp,'kind':body.get('kind','initial'),
                    'snapshotVersions':versions(s),'weightsUsed':prepare(raw)['weights'],'modelId':None,
                    'specVersion':'v3','engineVersion':ENGINE_VERSION,'solverVersion':result.get('internal',{}).get('solverVersion')}
            tx.set(base+'/formationRuns/'+run_id,record)
            tx.set('serverRuns/'+run_id,{'snapshot':raw,'prefVersion':s['meta'].get('prefVersion',0),'internal':result.get('internal',{}),'createdAt':stamp,'status':status})
            if status in VALID:
                old=s['draft']; version=old.get('version',0)+1
                tx.set(base+'/draftHistory/'+run_id,old or {'version':0})
                d={'version':version,'assignments':result['assignments'],'locks':base_draft(s)['locks'],
                   'basedOnPublishedVersionId':s['activity'].get('publishedVersionId'),**public,'sourceRunId':run_id,
                   'manuallyEdited':False,'discarded':False,'updatedAt':stamp}
                tx.set(base+'/draft/current',d); response['draftVersion']=version
            return response
        return self.repo.atomic(apply)
