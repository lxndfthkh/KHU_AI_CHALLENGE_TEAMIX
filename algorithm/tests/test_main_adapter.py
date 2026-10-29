import unittest
from copy import deepcopy
from datetime import datetime, timezone
from repository import normalize, Transaction
from service import FormationService, Invalid
from formation import digest


def canonical():
    return {'groupId':'g','title':'demo','status':'closed','responseVersion':4,'settingsVersion':1,
        'currentPublicationId':None,'publicationVersion':0,
        'questions':{'selected':['role','time','experience','interest'],'roleOptions':['dev','design'],'timeOptions':['wed'],'interestOptions':['web']},
        'matchingSettings':{'teamCount':2,'teamCapacities':[2,2],'method':'balanced',
            'priority':['time','role','experience','interest','size'],'requireCommonTime':False}}

class DB:
    def document(self,path):return path
class Writes:
    def __init__(self):self.values={}
    def set(self,path,value,merge=False):
        self.values[path]={**self.values.get(path,{}),**deepcopy(value)} if merge else deepcopy(value)
class MainAdapterTests(unittest.TestCase):
    def parts(self,role='owner'):
        a=canonical();members={'operator':{'role':role,'nickname':'O'},**{f'u{i}':{'role':'member','nickname':f'N{i}'} for i in range(4)}}
        apps={f'u{i}':{'status':'submitted','updatedAt':datetime.now(timezone.utc),'answers':{'role':'dev' if i%2 else 'design','time':['wed'],'experience':i+1,'interest':['web']}} for i in range(4)}
        return a,members,apps
    def test_owner_admin_normalize(self):
        for role in ['owner','admin']:
            a,m,apps=self.parts(role);v,q,m,apps=normalize(a,{},m,apps)
            self.assertEqual(m['operator']['role'],'officer');self.assertEqual(m['operator']['sourceRole'],role)
            self.assertEqual(m['u0']['role'],'participant');self.assertEqual(apps['u0']['status'],'applied')
            self.assertEqual(q['time']['scale'],['wed']);self.assertEqual(v['teamIds'],['team_1','team_2'])
    def test_unknown_role_not_active(self):
        a,m,apps=self.parts('officer');_,_,m,_=normalize(a,{},m,apps)
        self.assertEqual(m['operator']['status'],'invalid')
    def test_capacity_shape_rejected(self):
        a,m,apps=self.parts();a['matchingSettings']['teamCapacities']=[2]
        with self.assertRaises(Invalid):normalize(a,{},m,apps)
    def test_hard_conditions_are_main_fields(self):
        a,m,apps=self.parts();a['matchingSettings'].update(requireCommonTime=True,requiredRoles=[{'team':'team_1','role':'dev','minimum':1}])
        v,_,_,_=normalize(a,{},m,apps)
        self.assertEqual(v['extraRequirements'],[{'type':'commonTime'},{'type':'requiredRole','teamId':'team_1','role':'dev','minimum':1}])
    def adapter(self):
        a,m,apps=self.parts();v,q,nm,na=normalize(a,{},m,apps)
        writes=Writes();adapter=Transaction(DB(),writes)
        adapter.context={'activities/a':{'source':a,'runtime':{},'members':nm,'applications':apps,'publication':{}}}
        return adapter,writes,{'activity':v,'questions':q,'members':nm,'applications':na,'draft':{},'meta':{},'preferences':{},'published':{},'publishedMeta':{},'notified':{}}
    def test_legacy_internal_paths_never_persist(self):
        tx,writes,_=self.adapter()
        tx.set('groups/g/activities/a/draft/current',{'version':2,'assignments':{'u0':'team_1'}})
        tx.flush()
        d=writes.values['activities/a/drafts/current']
        self.assertEqual(d['revision'],2);self.assertEqual(d['editedTeams'],[{'team_id':'team_1','participants':['u0']}])
        self.assertFalse(any(p.startswith('groups/') for p in writes.values))
    def test_full_run_publish_roundtrip_through_adapter(self):
        tx,writes,s=self.adapter()
        class Repo:
            def atomic(self,fn):
                tx.load=lambda g,a:deepcopy(s)
                out=fn(tx);tx.flush();tx.pending.clear()
                d=writes.values.get('activities/a/drafts/current')
                if d:s['draft']=deepcopy(d)
                return out
        svc=FormationService(Repo())
        body={'groupId':'g','activityId':'a','kind':'initial','expected':{'roster':4,'settings':1,'draft':0},'limit':0.2}
        out=svc.invoke('run','operator',body);self.assertTrue(out['applied'])
        body['expected']['draft']=out['draftVersion']
        publication=svc.invoke('publish','operator',body)
        path='activities/a/publications/'+publication['publishedVersionId']
        pub=writes.values[path]
        self.assertEqual(pub['version'],1);self.assertEqual(len(pub['teams']),2)
        self.assertEqual(sorted(u for t in pub['teams'] for u in t['participants']),['u0','u1','u2','u3'])
        self.assertNotIn('operator',pub['displayProfiles']);self.assertIn('u0',pub['displayProfiles'])
        self.assertEqual(writes.values['activities/a']['currentPublicationId'],publication['publishedVersionId'])
        self.assertFalse(any('/teamVersions/' in p or '/draft/current' in p for p in writes.values))
        self.assertEqual(writes.values['activities/a/publicationAudit/'+publication['publishedVersionId']]['seq'],1)
    def test_question_change_in_formation_rejected(self):
        tx,writes,s=self.adapter();tx.set('groups/g/activities/a',{'criteria':[{'key':'size','priority':1}]},merge=True)
        with self.assertRaises(Invalid):tx.flush()
    def test_fingerprint_catches_private_and_answer_edit(self):
        tx,writes,s=self.adapter();before=digest(s)
        s['preferences']={'p':{'ownerUid':'u0','targetUid':'u1','status':'active'}}
        self.assertNotEqual(before,digest(s));before=digest(s)
        s['applications']['u0']['answers']['experience']['value']=5
        self.assertNotEqual(before,digest(s))
