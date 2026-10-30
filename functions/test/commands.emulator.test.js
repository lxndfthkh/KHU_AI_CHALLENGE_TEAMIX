// Stage 1-2 commands against the Firestore emulator (main schema). Run from functions/:
//   npx firebase emulators:exec --only firestore --project demo-teamix-fn "node --test test/commands.emulator.test.js"
const {test,before,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {existsSync}=require('node:fs');
const {spawnSync}=require('node:child_process');
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const C=require('../src/commands');
const A=require('../src/activity');

const PROJECT=process.env.GCLOUD_PROJECT||'';
let db;
before(()=>{
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST&&PROJECT.startsWith('demo-'),'Firestore 에뮬레이터(demo- 프로젝트)에서 실행하세요');
  initializeApp({projectId:PROJECT});db=getFirestore();
});
beforeEach(async()=>{
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,{method:'DELETE'});
  for(const uid of ['admin','u0','u1','u2','u3','u4','outsider'])
    await db.doc(`users/${uid}`).set({displayName:`N-${uid}`,createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
});
const get=async p=>{const s=await db.doc(p).get();return s.exists?s.data():null;};
const rejects=(promise,code)=>assert.rejects(promise,e=>e instanceof C.CommandError?e.code===code:code==='invalid-argument'&&e.name==='Error');

const QUESTIONS=[
  {id:'role',label:'희망 역할',type:'single',options:[{id:'dev',label:'개발'},{id:'design',label:'디자인'}]},
  {id:'time',label:'가능 시간',type:'multiple',options:[{id:'wed',label:'수'}]},
  {id:'exp',label:'경험',type:'scale'},
];
const activityInput=(groupId,patch={})=>({groupId,title:'해커톤',capacity:10,targetTeamSize:2,deadlineAt:Date.now()+86400000,
  questions:QUESTIONS,matching:{method:'balanced',questionCriteria:{role:'role',time:'time',exp:'experience'}},...patch});
const ANSWERS=i=>({role:i%2?'dev':'design',time:['wed'],exp:1+i%5});

async function groupWithMembers(n=4){
  const {groupId}=await C.createGroup(db,'admin',{name:'메이커스',description:'시연'});
  const {code}=await C.issueInvitation(db,'admin',{groupId});
  for(let i=0;i<n;i++){await C.requestJoin(db,`u${i}`,{code});await C.approveJoin(db,'admin',{groupId,userId:`u${i}`});}
  return {groupId,code};
}

test('createGroup: profile required; group + approved admin membership in main layout',async()=>{
  await rejects(C.createGroup(db,'nobody',{name:'x'}),'failed-precondition');
  const {groupId}=await C.createGroup(db,'admin',{name:'메이커스',themeColor:'peach'});
  const g=await get(`groups/${groupId}`);
  assert.equal(g.ownerId,'admin');assert.equal(g.themeColor,'peach');assert.equal(g.status,'active');
  const m=await get(`memberships/${groupId}_admin`);
  assert.deepEqual([m.groupId,m.userId,m.role,m.status,m.displayName],[groupId,'admin','admin','approved','N-admin']);
});

test('issueInvitation: admin only; only the hash is stored',async()=>{
  const {groupId}=await C.createGroup(db,'admin',{name:'g'});
  await rejects(C.issueInvitation(db,'u0',{groupId}),'permission-denied');
  const {code,expiresAt}=await C.issueInvitation(db,'admin',{groupId});
  assert.match(code,/^[A-HJ-NP-Z2-9]{10}$/);assert.ok(expiresAt>Date.now());
  const inv=await get(`invitations/${C.hash(code)}`);
  assert.equal(inv.groupId,groupId);assert.equal(inv.active,true);
  assert.ok(!JSON.stringify(inv).includes(code));
});

test('previewInvitation: safe fields; expired/inactive/wrong codes rejected; guesses are rate limited',async()=>{
  const {groupId,code}=await groupWithMembers(2);
  const p=await C.previewInvitation(db,'outsider',{code:code.toLowerCase()});
  assert.deepEqual(Object.keys(p).sort(),['description','groupId','memberCount','myStatus','name','themeColor']);
  assert.equal(p.memberCount,3);assert.equal(p.myStatus,null);
  await db.doc(`invitations/${C.hash(code)}`).update({expiresAt:Timestamp.fromMillis(Date.now()-1)});
  await rejects(C.previewInvitation(db,'outsider',{code}),'not-found');
  const {code:c2}=await C.issueInvitation(db,'admin',{groupId});
  await db.doc(`invitations/${C.hash(c2)}`).update({active:false});
  await rejects(C.previewInvitation(db,'outsider',{code:c2}),'not-found');
  for(let i=0;i<17;i++)await rejects(C.previewInvitation(db,'outsider',{code:'ZZZZZZZZZZ'}),'not-found');
  await rejects(C.previewInvitation(db,'outsider',{code:'ZZZZZZZZZZ'}),'resource-exhausted');
});

test('previewInvitation by groupId only for people who already asked to join',async()=>{
  const {groupId,code}=await groupWithMembers(0);
  await rejects(C.previewInvitation(db,'outsider',{groupId}),'permission-denied');
  await C.requestJoin(db,'outsider',{code});
  assert.equal((await C.previewInvitation(db,'outsider',{groupId})).myStatus,'pending');
});

test('requestJoin → approveJoin / rejectJoin: idempotent, notifications in main shape',async()=>{
  const {groupId,code}=await groupWithMembers(0);
  assert.equal((await C.requestJoin(db,'u0',{code})).status,'pending');
  assert.equal((await C.requestJoin(db,'u0',{code})).status,'pending');
  await rejects(C.approveJoin(db,'u1',{groupId,userId:'u0'}),'permission-denied');
  assert.equal((await C.approveJoin(db,'admin',{groupId,userId:'u0'})).status,'approved');
  assert.equal((await C.approveJoin(db,'admin',{groupId,userId:'u0'})).status,'approved');
  const notes=(await db.collection('notifications').where('userId','==','u0').get()).docs.map(d=>d.data());
  assert.equal(notes.length,1);assert.equal(notes[0].type,'joinApproved');assert.equal(notes[0].readAt,null);
  assert.equal((await C.requestJoin(db,'u0',{code})).status,'approved');
  await C.requestJoin(db,'u1',{code});
  assert.equal((await C.rejectJoin(db,'admin',{groupId,userId:'u1'})).status,'rejected');
  assert.equal((await get(`memberships/${groupId}_u1`)).status,'rejected');
  assert.equal((await C.requestJoin(db,'u1',{code})).status,'pending');
  await rejects(C.approveJoin(db,'admin',{groupId,userId:'u4'}),'failed-precondition');
});

test('createActivity: admin only; activity, questions and settings/matching contract for stage 3',async()=>{
  const {groupId}=await groupWithMembers(1);
  await rejects(C.createActivity(db,'u0',activityInput(groupId)),'permission-denied');
  const {activityId}=await C.createActivity(db,'admin',activityInput(groupId));
  const a=await get(`activities/${activityId}`);
  assert.deepEqual([a.groupId,a.status,a.participantCount,a.publishedVersion,a.questionsLockedAt,a.targetTeamSize,a.themeColor],
    [groupId,'recruiting',0,null,null,2,'mint']);
  assert.equal((await get(`activities/${activityId}/questions/exp`)).type,'scale');
  const s=await get(`activities/${activityId}/settings/matching`);
  assert.deepEqual(s.enabledQuestionIds,['role','time','exp']);
  assert.deepEqual(s.priority,['role','time','experience','size']);
  assert.deepEqual([s.capacityInitialized,s.settingsVersion,s.requireCommonTime],[false,1,false]);
  assert.equal(s.teamIds,undefined);
});

test('registrations: approved members only, answers checked, count once, capacity and deadline enforced',async()=>{
  const {groupId,code}=await groupWithMembers(3);
  const {activityId}=await C.createActivity(db,'admin',activityInput(groupId,{capacity:2}));
  await C.requestJoin(db,'u4',{code});
  await rejects(C.submitRegistration(db,'u4',{activityId,answers:ANSWERS(4)}),'permission-denied');
  await rejects(C.submitRegistration(db,'u0',{activityId,answers:{role:'pm'}}),'invalid-argument');
  await C.submitRegistration(db,'u0',{activityId,answers:ANSWERS(0)});
  await C.submitRegistration(db,'u0',{activityId,answers:ANSWERS(0)});
  let a=await get(`activities/${activityId}`);
  assert.equal(a.participantCount,1);assert.ok(a.questionsLockedAt);
  const r=await get(`registrations/${activityId}_u0`);
  assert.deepEqual([r.activityId,r.groupId,r.userId,r.status],[activityId,groupId,'u0','submitted']);
  await C.submitRegistration(db,'u1',{activityId,answers:ANSWERS(1)});
  await rejects(C.submitRegistration(db,'u2',{activityId,answers:ANSWERS(2)}),'resource-exhausted');
  const before=r.updatedAt.toMillis();
  assert.equal((await C.updateRegistration(db,'u0',{activityId,answers:{...ANSWERS(0),exp:5}})).changed,true);
  assert.ok((await get(`registrations/${activityId}_u0`)).updatedAt.toMillis()>=before);
  await rejects(C.updateRegistration(db,'u2',{activityId,answers:ANSWERS(2)}),'failed-precondition');
  assert.equal((await C.cancelRegistration(db,'u1',{activityId})).status,'cancelled');
  a=await get(`activities/${activityId}`);assert.equal(a.participantCount,1);
  await C.submitRegistration(db,'u1',{activityId,answers:ANSWERS(1)});
  await db.doc(`activities/${activityId}`).update({deadlineAt:Timestamp.fromMillis(Date.now()-1000)});
  await rejects(C.updateRegistration(db,'u0',{activityId,answers:ANSWERS(0)}),'failed-precondition');
  await db.doc(`activities/${activityId}`).update({status:'closed',publishedVersion:1});
  await rejects(C.cancelRegistration(db,'u0',{activityId}),'failed-precondition');
});

test('placement preferences: same-group members only, at most two active, never self',async()=>{
  const {groupId}=await groupWithMembers(4);
  await rejects(C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u0',confirmed:true}),'invalid-argument');
  await rejects(C.setPlacementPreference(db,'u0',{groupId,targetUserId:'outsider',confirmed:true}),'failed-precondition');
  await rejects(C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u1'}),'invalid-argument');
  await C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u1',confirmed:true});
  await C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u1',confirmed:true});
  await C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u2',confirmed:true});
  await rejects(C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u3',confirmed:true}),'resource-exhausted');
  await C.revokePlacementPreference(db,'u0',{groupId,targetUserId:'u1'});
  await C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u3',confirmed:true});
  const p=await get(`placementPreferences/${groupId}_u0_u3`);
  assert.deepEqual([p.groupId,p.userId,p.targetUserId,p.active],[groupId,'u0','u3',true]);
  assert.equal((await get(`placementPreferences/${groupId}_u0_u1`)).active,false);
});

const PYTHON=path.join(__dirname,'../../algorithm/.venv/bin/python');
test('end to end: stage 1-2 data is closed, formed and published by stage 3, then started, ended and reviewed (stage 4)',{skip:!existsSync(PYTHON)&&'algorithm/.venv 없음'},async()=>{
  const {groupId}=await groupWithMembers(4);
  const {activityId}=await C.createActivity(db,'admin',activityInput(groupId));
  for(let i=0;i<4;i++)await C.submitRegistration(db,`u${i}`,{activityId,answers:ANSWERS(i)});
  await C.setPlacementPreference(db,'u0',{groupId,targetUserId:'u1',confirmed:true});
  const script=`
import json,sys
from google.cloud import firestore
from repository import FirestoreRepository
from validated_service import ValidatedFormationService
svc=ValidatedFormationService(FirestoreRepository(firestore.Client(project=${JSON.stringify(PROJECT)})))
b={'groupId':${JSON.stringify(groupId)},'activityId':${JSON.stringify(activityId)},'limit':2}
def ex(): v=svc.invoke('precheck','admin',b)['versions']; return {k:v[k] for k in ('roster','settings','draft')}
svc.invoke('close','admin',{**b,'expected':ex()})
run=svc.invoke('run','admin',{**b,'kind':'initial','expected':ex()})
pub=svc.invoke('publish','admin',{**b,'expected':ex()})
print(json.dumps({'applied':run['applied'],'seq':pub['seq']}))`;
  const out=spawnSync(PYTHON,['-c',script],{cwd:path.join(__dirname,'../../algorithm'),env:process.env,encoding:'utf8'});
  assert.equal(out.status,0,out.stderr);
  assert.deepEqual(JSON.parse(out.stdout.trim().split('\n').pop()),{applied:true,seq:1});
  assert.equal((await get(`activities/${activityId}`)).status,'closed');
  assert.deepEqual((await get(`activities/${activityId}/settings/matching`)).teamIds,['team_1','team_2']);
  const views=await Promise.all([0,1,2,3].map(i=>get(`teamViews/${activityId}_u${i}`)));
  assert.ok(views.every(v=>v&&v.version===1));
  assert.notEqual(views[0].teamId,views[1].teamId,'비공개 선호(u0↔u1)가 반영되어야 함');
  // Stage 4 on top of the publication stage 3 wrote.
  const pub=await get(`publications/${activityId}_v1`);
  assert.ok(pub.validFrom&&pub.validTo===null);
  await A.startActivity(db,'admin',{activityId});
  await A.endActivity(db,'admin',{activityId});
  const fb=await A.submitFeedback(db,'u0',{activityId,scores:{overall:5,schedule:4,roles:4,rejoin:5}});
  assert.equal(fb.teamId,views[0].teamId);
  assert.equal(fb.membershipRatio,1);
});
