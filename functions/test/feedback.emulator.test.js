// Stage 4 against the Firestore emulator (main schema), following 개발단계_가이드 4단계 통과 기준 (편성학습_v4: scores only).
// Run from functions/: npm run test:emulator
const {test,before,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const path=require('node:path');
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc}=require('firebase/firestore');
const {CommandError}=require('../src/common');
const A=require('../src/activity');

const PROJECT=process.env.GCLOUD_PROJECT||'';
const H=3600000;
let db,env;
before(async()=>{
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST&&PROJECT.startsWith('demo-'),'Firestore 에뮬레이터(demo- 프로젝트)에서 실행하세요');
  initializeApp({projectId:PROJECT},'feedback');db=getFirestore(require('firebase-admin/app').getApp('feedback'));
  env=await initializeTestEnvironment({projectId:PROJECT,firestore:{rules:readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
});
after(async()=>{if(env)await env.cleanup();});
const get=async p=>{const s=await db.doc(p).get();return s.exists?s.data():null;};
const rejects=(p,code)=>assert.rejects(p,e=>e instanceof CommandError?e.code===code:code==='invalid-argument');
const scores=(o=4)=>({overall:o,schedule:3,roles:4,rejoin:5});
const ts=ms=>Timestamp.fromMillis(ms);

// Activity a in group g: 5 participants. v1 at -12h: team_1 [u0,u1,u2], team_2 [u3,u4].
// Activity started at -10h. v2 at -4h (republish during the activity): u2 moves to team_2.
async function seed({status='active'}={}){
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,{method:'DELETE'});
  const t=Date.now(),put=(p,v)=>db.doc(p).set(v);
  await put('activities/a',{groupId:'g',title:'해커톤',status,publishedVersion:2,startedAt:status==='active'?ts(t-10*H):null,targetTeamSize:3});
  await put('memberships/g_admin',{groupId:'g',userId:'admin',displayName:'운영자',role:'admin',status:'approved'});
  const names=['김민수','이지은','박서준','최유나','정하늘'];
  for(let i=0;i<5;i++){
    await put(`memberships/g_u${i}`,{groupId:'g',userId:`u${i}`,displayName:names[i],role:'member',status:'approved'});
    await put(`users/u${i}`,{displayName:names[i]});
    await put(`registrations/a_u${i}`,{activityId:'a',groupId:'g',userId:`u${i}`,status:'submitted'});
  }
  await put('users/admin',{displayName:'운영자'});
  const team=(teamId,uids)=>({teamId,members:uids.map(uid=>({uid,displayName:uid}))});
  await put('publications/a_v1',{activityId:'a',groupId:'g',version:1,publishedAt:ts(t-12*H),validFrom:ts(t-12*H),validTo:ts(t-4*H),teams:[team('team_1',['u0','u1','u2']),team('team_2',['u3','u4'])]});
  await put('publications/a_v2',{activityId:'a',groupId:'g',version:2,publishedAt:ts(t-4*H),validFrom:ts(t-4*H),validTo:null,teams:[team('team_1',['u0','u1']),team('team_2',['u2','u3','u4'])]});
}
beforeEach(()=>seed());

test('4: state only moves forward; start/end need the right state and an officer',async()=>{
  await seed({status:'closed'});
  await rejects(A.endActivity(db,'admin',{activityId:'a'}),'failed-precondition');
  await rejects(A.startActivity(db,'u0',{activityId:'a'}),'permission-denied');
  assert.equal((await A.startActivity(db,'admin',{activityId:'a'})).status,'active');
  assert.equal((await A.startActivity(db,'admin',{activityId:'a'})).status,'active');
  await rejects(A.submitFeedback(db,'u0',{activityId:'a',scores:scores()}),'failed-precondition');
  assert.deepEqual(await A.endActivity(db,'admin',{activityId:'a'}),{status:'ended',endedVersion:2});
  await rejects(A.startActivity(db,'admin',{activityId:'a'}),'failed-precondition');
  await db.doc('activities/a').update({status:'recruiting',publishedVersion:null});
  await rejects(A.startActivity(db,'admin',{activityId:'a'}),'failed-precondition');
});

test('4: ending records endedVersion/endedAt and asks only the ending version for feedback',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  const a=await get('activities/a');
  assert.equal(a.status,'ended');assert.equal(a.endedVersion,2);assert.ok(a.endedAt);assert.equal(a.feedbackClosedAt,null);
  const notes=(await db.collection('notifications').where('activityId','==','a').get()).docs.map(d=>d.data());
  assert.deepEqual(notes.map(n=>n.userId).sort(),['u0','u1','u2','u3','u4']);
  assert.ok(notes.every(n=>n.type==='feedbackRequested'&&n.readAt===null));
});

test('4: feedback links to the ending version even after a republish; membershipRatio is right',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  const moved=await A.submitFeedback(db,'u2',{activityId:'a',scores:scores()});
  assert.equal(moved.teamId,'team_2');
  assert.ok(Math.abs(moved.membershipRatio-0.4)<0.01,`ratio ${moved.membershipRatio}`);
  const stayed=await A.submitFeedback(db,'u0',{activityId:'a',scores:scores(),teamId:'team_2',teamVersion:1});
  assert.equal(stayed.teamId,'team_1');assert.equal(stayed.membershipRatio,1);
  const f=await get('feedback/a_u2');
  assert.deepEqual([f.activityId,f.groupId,f.userId,f.teamId,f.teamVersion,f.rating,f.questionnaireVersion],['a','g','u2','team_2',2,4,'r2']);
  assert.deepEqual(f.scores,scores());assert.equal(f.learningConsent,false);
  assert.ok(!('comment' in f)&&!('commentTags' in f));
});

test('4: only people in the ending version, valid scores, no free text, closed after closeFeedback',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  await db.doc('memberships/g_u9').set({groupId:'g',userId:'u9',displayName:'x',role:'member',status:'approved'});
  await rejects(A.submitFeedback(db,'u9',{activityId:'a',scores:scores()}),'permission-denied');
  await rejects(A.submitFeedback(db,'u0',{activityId:'a',scores:{overall:4}}),'invalid-argument');
  await rejects(A.submitFeedback(db,'u0',{activityId:'a',scores:scores(),comment:'자유 서술'}),'invalid-argument');
  await A.submitFeedback(db,'u0',{activityId:'a',scores:scores(2)});
  await A.submitFeedback(db,'u0',{activityId:'a',scores:scores(5)});
  assert.equal((await get('feedback/a_u0')).rating,5);
  await rejects(A.closeFeedback(db,'u0',{activityId:'a'}),'permission-denied');
  await A.closeFeedback(db,'admin',{activityId:'a'});
  await rejects(A.submitFeedback(db,'u0',{activityId:'a',scores:scores()}),'failed-precondition');
});

test('4: learning consent copied at writing time; later changes apply to later writes',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  await A.setLearningConsent(db,'u0',{agreed:true});
  assert.equal((await get('consents/u0')).learning.agreed,true);
  await A.submitFeedback(db,'u0',{activityId:'a',scores:scores()});
  assert.equal((await get('feedback/a_u0')).learningConsent,true);
  await A.setLearningConsent(db,'u0',{agreed:false});
  assert.equal((await get('feedback/a_u0')).learningConsent,true);
  await A.submitFeedback(db,'u0',{activityId:'a',scores:scores()});
  assert.equal((await get('feedback/a_u0')).learningConsent,false);
});

test('4: summary only for teams with 3+ respondents; officers cannot read individual feedback',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  for(const u of ['u2','u3','u4'])await A.submitFeedback(db,u,{activityId:'a',scores:scores(u==='u2'?2:5)});
  await A.submitFeedback(db,'u0',{activityId:'a',scores:scores()});
  const s=await get('activities/a/feedbackSummary/current');
  assert.deepEqual(Object.keys(s.teams),['team_2']);
  assert.equal(s.teams.team_2.respondents,3);assert.equal(s.teams.team_2.averages.overall,4);
  assert.deepEqual(Object.keys(s.teams.team_2).sort(),['averages','respondents']);
  assert.ok(!JSON.stringify(s).includes('u2'));
  const as=uid=>env.authenticatedContext(uid).firestore();
  await assertSucceeds(getDoc(doc(as('u2'),'feedback/a_u2')));
  await assertFails(getDoc(doc(as('admin'),'feedback/a_u2')));
  await assertFails(getDoc(doc(as('u3'),'feedback/a_u2')));
  await assertSucceeds(getDoc(doc(as('admin'),'activities/a/feedbackSummary/current')));
  await assertFails(getDoc(doc(as('u2'),'activities/a/feedbackSummary/current')));
});

test('4: feedback closes automatically 7 days after the end',async()=>{
  await A.endActivity(db,'admin',{activityId:'a'});
  const ended=(await get('activities/a')).endedAt.toMillis();
  assert.deepEqual(await A.closeExpiredFeedback(db,ended+6*24*H),[]);
  assert.deepEqual(await A.closeExpiredFeedback(db,ended+7*24*H),['a']);
  assert.ok((await get('activities/a')).feedbackClosedAt);
});
