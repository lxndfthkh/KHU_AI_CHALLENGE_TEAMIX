// Stage 9 deletion against the Firestore emulator (편성학습_v4 12장, 개발단계 가이드 9단계). Run from functions/: npm run test:emulator
const {test,before,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,getApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {CommandError}=require('../src/common');
const A=require('../src/activity');
const P=require('../src/privacy');

const PROJECT=process.env.GCLOUD_PROJECT||'';
const H=3600000;
let db;
before(()=>{
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST&&PROJECT.startsWith('demo-'),'Firestore 에뮬레이터(demo- 프로젝트)에서 실행하세요');
  initializeApp({projectId:PROJECT},'privacy');db=getFirestore(getApp('privacy'));
});
const get=async p=>{const s=await db.doc(p).get();return s.exists?s.data():null;};
const rejects=(p,code)=>assert.rejects(p,e=>e instanceof CommandError?e.code===code:code==='invalid-argument');
const scores=o=>({overall:o,schedule:3,roles:4,rejoin:5});
const team=(teamId,uids)=>({teamId,members:uids.map(uid=>({uid,displayName:`N-${uid}`}))});

// Group g: admin + u0..u3. Activity a (ended, v1: team_1 [u0,u1,u2], team_2 [u3]) and activity b (recruiting).
beforeEach(async()=>{
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,{method:'DELETE'});
  const t=Date.now(),put=(p,v)=>db.doc(p).set(v);
  for(const u of ['admin','u0','u1','u2','u3']){
    await put(`users/${u}`,{displayName:`N-${u}`});
    await put(`memberships/g_${u}`,{groupId:'g',userId:u,displayName:`N-${u}`,role:u==='admin'?'admin':'member',status:'approved'});
  }
  await put('activities/a',{groupId:'g',status:'active',publishedVersion:1,startedAt:Timestamp.fromMillis(t-10*H)});
  await put('activities/b',{groupId:'g',status:'recruiting',publishedVersion:null,participantCount:2});
  await put('publications/a_v1',{activityId:'a',groupId:'g',version:1,publishedAt:Timestamp.fromMillis(t-12*H),validFrom:Timestamp.fromMillis(t-12*H),validTo:null,
    teams:[team('team_1',['u0','u1','u2']),team('team_2',['u3'])]});
  for(const u of ['u0','u1','u2','u3']){
    await put(`registrations/a_${u}`,{activityId:'a',groupId:'g',userId:u,status:'submitted',answers:{role:'dev'}});
    await put(`teamViews/a_${u}`,{activityId:'a',groupId:'g',userId:u,version:1,teamId:u==='u3'?'team_2':'team_1',
      members:(u==='u3'?['u3']:['u0','u1','u2']).map(x=>({uid:x,displayName:`N-${x}`,role:'dev'}))});
    await put(`notifications/x_${u}`,{userId:u,type:'teamPublished',groupId:'g',activityId:'a'});
  }
  for(const u of ['u0','u1'])await put(`registrations/b_${u}`,{activityId:'b',groupId:'g',userId:u,status:'submitted',answers:{}});
  await put('drafts/a',{activityId:'a',groupId:'g',version:2,teams:[{teamId:'team_1',members:['u0','u1','u2']},{teamId:'team_2',members:['u3']}],
    unassigned:[],locks:{u0:{teamId:'team_1',type:'manual'}},validation:{valid:true,conflicts:[],summary:{team_1:{members:['u0','u1','u2'],size:3}}}});
  await put('formationRuns/r1',{activityId:'a',groupId:'g',status:'OPTIMAL',publicSummary:{team_1:{members:['u0','u1','u2']},team_2:{members:['u3']}}});
  await put('serverRuns/r1',{activityId:'a',groupId:'g',snapshot:{participants:[{id:'u0',answers:{role:'dev'}},{id:'u1',answers:{role:'dev'}}],
    published:{u0:'team_1',u1:'team_1'},draft:{u0:'team_1'},locks:{u0:{type:'manual'}},
    private_preferences:[{source:'u0',target:'u1',confirmed:true},{source:'u1',target:'u2',confirmed:true}]}});
  await put('placementPreferences/g_u0_u1',{groupId:'g',userId:'u0',targetUserId:'u1',active:true});
  await put('placementPreferences/g_u2_u0',{groupId:'g',userId:'u2',targetUserId:'u0',active:true});
  await put('consents/u0',{learning:{agreed:true}});
  await put('trainingDatasets/fx1',{extractorVersion:'fx1'});
  await A.endActivity(db,'admin',{activityId:'a'});
  for(const u of ['u0','u1','u2'])await A.submitFeedback(db,u,{activityId:'a',scores:scores(u==='u0'?1:5)});
});

test('9: deleting a review removes it, recomputes the summary and marks the dataset dirty',async()=>{
  assert.equal((await get('activities/a/feedbackSummary/current')).teams.team_1.respondents,3);
  assert.deepEqual(await P.deleteFeedback(db,'u0',{activityId:'a'}),{deleted:true});
  assert.equal(await get('feedback/a_u0'),null);
  assert.deepEqual((await get('activities/a/feedbackSummary/current')).teams,{},'2명만 남아 집계 공개 기준(3명) 미만');
  const ds=await get('trainingDatasets/fx1');assert.equal(ds.dirty,true);assert.equal(ds.extractorVersion,'fx1');
  assert.deepEqual(await P.deleteFeedback(db,'u0',{activityId:'a'}),{deleted:false});
  assert.ok(await get('feedback/a_u1'),'다른 사람 후기는 그대로');
});

test('9: leaving a group: sole admin blocked; preferences revoked; unpublished sign-ups cancelled',async()=>{
  await rejects(P.leaveGroup(db,'admin',{groupId:'g'}),'failed-precondition');
  assert.deepEqual(await P.leaveGroup(db,'u0',{groupId:'g'}),{status:'left'});
  assert.equal((await get('memberships/g_u0')).status,'left');
  assert.equal((await get('placementPreferences/g_u0_u1')).active,false);
  assert.equal((await get('placementPreferences/g_u2_u0')).active,false);
  assert.equal((await get('registrations/b_u0')).status,'cancelled');
  assert.equal((await get('activities/b')).participantCount,1);
  assert.equal((await get('registrations/a_u0')).status,'submitted','공개된 활동의 기록은 유지');
  assert.deepEqual(await P.leaveGroup(db,'u0',{groupId:'g'}),{status:'left'});
});

test('9: account deletion needs confirmation and is blocked for a sole admin',async()=>{
  const calls=[];const deps={deleteAuthUser:async u=>calls.push(u)};
  await rejects(P.deleteAccount(db,'u0',{},deps),'invalid-argument');
  await rejects(P.deleteAccount(db,'admin',{confirm:true},deps),'failed-precondition');
  assert.deepEqual(calls,[]);
  assert.ok(await get('users/admin'));
});

test('9: account deletion removes personal data, keeps team records as deleted-user, scrubs answer copies',async()=>{
  const calls=[];
  assert.deepEqual(await P.deleteAccount(db,'u0',{confirm:true},{deleteAuthUser:async u=>calls.push(u)}),{deleted:true,activities:2});
  assert.deepEqual(calls,['u0']);
  for(const p of ['users/u0','consents/u0','memberships/g_u0','registrations/a_u0','registrations/b_u0','feedback/a_u0',
    'placementPreferences/g_u0_u1','placementPreferences/g_u2_u0','notifications/x_u0','teamViews/a_u0'])
    assert.equal(await get(p),null,p);
  const pub=await get('publications/a_v1');
  assert.deepEqual(pub.teams[0].members.map(m=>m.uid),['deleted-user','u1','u2']);
  assert.equal(pub.teams[0].members[0].displayName,'삭제된 사용자');
  assert.deepEqual((await get('teamViews/a_u1')).members.map(m=>[m.uid,m.role]),[['deleted-user',null],['u1','dev'],['u2','dev']]);
  const draft=await get('drafts/a');
  assert.deepEqual(draft.teams[0].members,['u1','u2']);assert.deepEqual(draft.locks,{});
  assert.deepEqual(draft.validation.summary.team_1.members,['deleted-user','u1','u2']);
  assert.deepEqual((await get('formationRuns/r1')).publicSummary.team_1.members,['deleted-user','u1','u2']);
  const snap=(await get('serverRuns/r1')).snapshot;
  assert.deepEqual(snap.participants.map(p=>p.id),['u1']);
  assert.deepEqual([snap.published,snap.draft,snap.locks],[{u1:'team_1'},{},{}]);
  assert.deepEqual(snap.private_preferences,[{source:'u1',target:'u2',confirmed:true}]);
  assert.ok(!JSON.stringify(await Promise.all(['publications/a_v1','drafts/a','formationRuns/r1','serverRuns/r1','teamViews/a_u1'].map(get))).includes('"u0"'));
  assert.equal((await get('activities/b')).participantCount,1,'공개 전 소모임 인원만 줄임');
  assert.equal((await get('activities/a/feedbackSummary/current')).teams.team_1,undefined);
  assert.equal((await get('trainingDatasets/fx1')).dirty,true);
  assert.ok(await get('users/u1')&&await get('feedback/a_u1'),'다른 사람 데이터는 그대로');
});
