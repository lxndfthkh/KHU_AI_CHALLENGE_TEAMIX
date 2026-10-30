// Stage 7 model approval against the Firestore emulator. Run from functions/: npm run test:emulator
const {test,before,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,getApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {CommandError}=require('../src/common');
const M=require('../src/models');

const PROJECT=process.env.GCLOUD_PROJECT||'';
const ADMIN={admin:true},USER={};
let db;
before(()=>{
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST&&PROJECT.startsWith('demo-'),'Firestore 에뮬레이터(demo- 프로젝트)에서 실행하세요');
  initializeApp({projectId:PROJECT},'models');db=getFirestore(getApp('models'));
});
beforeEach(async()=>{
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,{method:'DELETE'});
  for(const [id,time] of [['m1',1.5],['m2',1.2]])
    await db.doc(`modelVersions/${id}`).set({status:'candidate',b:{time,role:1,experience:1,interest:1,size:1},approvedBy:null});
});
const get=async p=>(await db.doc(p).get()).data();
const rejects=(p,code)=>assert.rejects(p,e=>e instanceof CommandError&&e.code===code);

test('7: only a service admin can approve, activate or deactivate',async()=>{
  for(const fn of ['approveModel','activateModel','deactivateModel'])
    await rejects(M[fn](db,'officer',{modelId:'m1'},USER),'permission-denied');
  await rejects(M.approveModel(db,'x',{modelId:'m1'},undefined),'permission-denied');
  assert.equal((await get('modelVersions/m1')).status,'candidate');
});

test('7: candidate -> approved -> active, written to appConfig/learning',async()=>{
  await rejects(M.activateModel(db,'root',{modelId:'m1'},ADMIN),'failed-precondition');
  assert.equal((await M.approveModel(db,'root',{modelId:'m1'},ADMIN)).status,'approved');
  const m=await get('modelVersions/m1');assert.equal(m.approvedBy,'root');assert.ok(m.approvedAt);
  assert.equal((await M.activateModel(db,'root',{modelId:'m1'},ADMIN)).status,'active');
  const c=await get('appConfig/learning');
  assert.deepEqual([c.activeModelId,c.b.time,c.activatedBy],['m1',1.5,'root']);
});

test('7: one active model; activating another retires the previous; rollback works both ways',async()=>{
  for(const id of ['m1','m2'])await M.approveModel(db,'root',{modelId:id},ADMIN);
  await M.activateModel(db,'root',{modelId:'m1'},ADMIN);
  assert.equal((await M.activateModel(db,'root',{modelId:'m2'},ADMIN)).previous,'m1');
  assert.deepEqual([(await get('modelVersions/m1')).status,(await get('modelVersions/m2')).status],['retired','active']);
  await M.activateModel(db,'root',{modelId:'m1'},ADMIN);
  assert.deepEqual([(await get('modelVersions/m1')).status,(await get('modelVersions/m2')).status],['active','retired']);
  assert.equal((await get('appConfig/learning')).activeModelId,'m1');
  assert.deepEqual(await M.deactivateModel(db,'root',{},ADMIN),{activeModelId:null,previous:'m1'});
  assert.equal((await get('modelVersions/m1')).status,'retired');
  const c=await get('appConfig/learning');assert.equal(c.activeModelId,null);assert.equal(c.b,null);
});

test('7: unknown models and repeated calls',async()=>{
  await rejects(M.approveModel(db,'root',{modelId:'nope'},ADMIN),'not-found');
  await M.approveModel(db,'root',{modelId:'m1'},ADMIN);
  assert.equal((await M.approveModel(db,'root',{modelId:'m1'},ADMIN)).status,'approved');
  await M.activateModel(db,'root',{modelId:'m1'},ADMIN);
  await rejects(M.approveModel(db,'root',{modelId:'m1'},ADMIN),'failed-precondition');
});
