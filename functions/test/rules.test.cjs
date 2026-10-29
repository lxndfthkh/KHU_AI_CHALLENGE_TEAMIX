const {before,after,test}=require('node:test');
const {readFileSync}=require('node:fs');
const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,collection,query,where,getDocs,updateDoc}=require('firebase/firestore');
let env;
const db=uid=>env.authenticatedContext(uid).firestore();
before(async()=>{
  env=await initializeTestEnvironment({projectId:'demo-teamix',firestore:{rules:readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const f=ctx.firestore();
    const rows={
      'users/p':{displayName:'참가원',consents:{learning:{agreed:false}}},
      'groups/g':{name:'테스트'},
      'groups/g/members/p':{role:'participant',status:'active'},
      'groups/g/members/o':{role:'officer',status:'active'},
      'groups/g/members/w':{role:'participant',status:'pending'},
      'groups/g/activities/a':{state:'recruiting',publishedVersionId:'v1'},
      'groups/g/activities/a/applications/p':{status:'applied'},
      'groups/g/activities/a/applications/x':{status:'applied'},
      'groups/g/activities/a/reviews/p':{comment:'비공개 원문'},
      'groups/g/activities/a/draft/current':{version:1},
      'groups/g/activities/a/private/meta':{prefVersion:1},
      'privatePreferences/pref':{ownerUid:'p',targetUid:'x',groupId:'g',activityId:'a',status:'active'},
      'groups/g/activities/a/teamVersions/v1/teams/t1':{members:['p']},
      'groups/g/activities/a/teamVersions/v1/teams/t2':{members:['x']},
      'groups/g/activities/a/teamVersions/v1/teams/t3':{members:['p'],reviewSummary:{overall:4}},
      'serverRuns/r':{secret:true},'trainingDatasets/d':{secret:true},'modelVersions/m':{secret:true}
    };
    for(const [p,value] of Object.entries(rows))await setDoc(doc(f,p),value);
  });
});
after(async()=>{if(env)await env.cleanup();});
test('participant cannot read another review, another preference or draft',async()=>{
  await assertFails(getDoc(doc(db('x'),'groups/g/activities/a/reviews/p')));
  await assertFails(getDoc(doc(db('o'),'privatePreferences/pref')));
  await assertFails(getDoc(doc(db('p'),'groups/g/activities/a/draft/current')));
});
test('owner can read own review/preferences; officer cannot read review',async()=>{
  await assertSucceeds(getDoc(doc(db('p'),'groups/g/activities/a/reviews/p')));
  await assertSucceeds(getDoc(doc(db('p'),'privatePreferences/pref')));
  await assertFails(getDoc(doc(db('o'),'groups/g/activities/a/reviews/p')));
});
test('owner-filtered preference query allowed; unfiltered query denied',async()=>{
  await assertSucceeds(getDocs(query(collection(db('p'),'privatePreferences'),where('ownerUid','==','p'))));
  await assertFails(getDocs(collection(db('o'),'privatePreferences')));
});
test('officer cannot access private meta or server data',async()=>{
  for(const p of ['groups/g/activities/a/private/meta','serverRuns/r','trainingDatasets/d','modelVersions/m'])await assertFails(getDoc(doc(db('o'),p)));
});
test('pending user cannot read group; active user and officer can',async()=>{
  await assertFails(getDoc(doc(db('w'),'groups/g')));
  await assertSucceeds(getDoc(doc(db('p'),'groups/g')));
  await assertSucceeds(getDoc(doc(db('o'),'groups/g/activities/a/draft/current')));
});
test('no direct membership/application/preference writes, including officer',async()=>{
  await assertFails(updateDoc(doc(db('p'),'groups/g/members/p'),{role:'officer'}));
  await assertFails(setDoc(doc(db('p'),'groups/g/activities/a/applications/p'),{status:'applied'}));
  await assertFails(setDoc(doc(db('o'),'privatePreferences/new'),{ownerUid:'o'}));
});
test('profile can edit name but cannot directly opt into learning',async()=>{
  await assertSucceeds(updateDoc(doc(db('p'),'users/p'),{displayName:'새 이름'}));
  await assertFails(updateDoc(doc(db('p'),'users/p'),{'consents.learning.agreed':true}));
});
test('participant can only read own published team without aggregate field',async()=>{
  await assertSucceeds(getDoc(doc(db('p'),'groups/g/activities/a/teamVersions/v1/teams/t1')));
  await assertFails(getDoc(doc(db('p'),'groups/g/activities/a/teamVersions/v1/teams/t2')));
  await assertFails(getDoc(doc(db('p'),'groups/g/activities/a/teamVersions/v1/teams/t3')));
});
test('unauthenticated reads denied',async()=>await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'groups/g'))));
