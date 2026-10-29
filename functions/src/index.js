'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {randomBytes, createHash} = require('node:crypto');
const V = require('./validation');
initializeApp();
const db = getFirestore();
const now = () => FieldValue.serverTimestamp();
const fail = (code, message) => { throw new HttpsError(code, message); };
const callable = fn => onCall({region:'asia-northeast3'}, async req => {
  if (!req.auth) fail('unauthenticated', 'Login required');
  try { return await fn(req.auth.uid, req.data || {}); }
  catch (e) { if (e instanceof V.ValidationError) fail('invalid-argument', e.message); throw e; }
});
const groupRef = g => db.doc(`groups/${V.id(g)}`);
const activityRef = (g,a) => groupRef(g).collection('activities').doc(V.id(a));
async function authorize(tx, g, uid, officer = false) {
  const snap = await tx.get(groupRef(g).collection('members').doc(uid));
  if (!snap.exists || snap.data().status !== 'active' || (officer && snap.data().role !== 'officer')) fail('permission-denied', 'Active membership required');
  return snap.data();
}
async function activity(tx,g,a,uid,officer=false,states=['recruiting']) {
  await authorize(tx,g,uid,officer);
  const ref = activityRef(g,a); const snap = await tx.get(ref);
  if (!snap.exists) fail('not-found','Activity not found');
  if (!states.includes(snap.data().state)) fail('failed-precondition','Activity is not accepting this operation');
  return {ref, data:snap.data()};
}
// Firebase Auth provider is intentionally not selected here. All APIs use uid.
exports.initializeProfile = callable(async (uid,d) => {
  const displayName = V.text(d.displayName,80); const version = V.text(d.termsVersion,80);
  V.check(d.termsAgreed === true,'Terms consent required');
  const ref = db.doc(`users/${uid}`);
  await db.runTransaction(async tx => {
    const old = await tx.get(ref);
    if (old.exists) fail('already-exists','Profile already initialized');
    tx.create(ref,{displayName, consents:{terms:{version,at:now()}, learning:{agreed:false,version:'l1',at:now()}}});
  }); return {uid};
});
exports.setLearningConsent = callable(async (uid,d) => {
  V.check(typeof d.agreed === 'boolean','Boolean consent required');
  await db.runTransaction(async tx => {
    const ref=db.doc(`users/${uid}`); const s=await tx.get(ref);
    if (!s.exists) fail('failed-precondition','Initialize profile first');
    tx.update(ref,{'consents.learning':{agreed:d.agreed,version:'l1',at:now()}});
  }); return {ok:true};
});
exports.createGroup = callable(async (uid,d) => {
  const name=V.text(d.name,80), description=V.text(d.description,300);
  const ref=db.collection('groups').doc(); const inviteCode=randomBytes(18).toString('hex');
  await db.runTransaction(async tx => {
    const profile=await tx.get(db.doc(`users/${uid}`));
    if (!profile.exists) fail('failed-precondition','Initialize profile first');
    tx.create(ref,{name,description,createdBy:uid,createdAt:now()});
    tx.create(ref.collection('members').doc(uid),{role:'officer',status:'active',joinedAt:now(),updatedAt:now()});
    tx.create(db.doc(`invites/${inviteCode}`),{groupId:ref.id,expiresAt:Timestamp.fromMillis(Date.now()+7*86400000),revoked:false});
  }); return {groupId:ref.id,inviteCode};
});
async function invite(tx,code,g) {
  V.id(code); const s=await tx.get(db.doc(`invites/${code}`));
  if (!s.exists || s.data().revoked || s.data().expiresAt.toMillis() <= Date.now() || (g && s.data().groupId!==g)) fail('not-found','Invalid or expired invite');
  return s.data().groupId;
}
exports.previewInvite = callable(async (uid,d) => db.runTransaction(async tx => {
  const g=await invite(tx,d.inviteCode); const ref=groupRef(g);
  const [s,m,people]=await Promise.all([tx.get(ref),tx.get(ref.collection('members').doc(uid)),tx.get(ref.collection('members').where('status','==','active'))]);
  if (!s.exists) fail('not-found','Group not found');
  return {groupId:g,name:s.data().name,description:s.data().description,memberCount:people.size,status:m.exists?m.data().status:null};
}));
exports.requestJoin = callable(async (uid,d) => db.runTransaction(async tx => {
  const g=await invite(tx,d.inviteCode,d.groupId); const ref=groupRef(g).collection('members').doc(uid);
  const [s,p]=await Promise.all([tx.get(ref),tx.get(db.doc(`users/${uid}`))]);
  if (!p.exists) fail('failed-precondition','Initialize profile first');
  if (s.exists) {
    if (['active','pending'].includes(s.data().status)) return {status:s.data().status};
    fail('failed-precondition','Re-request policy is not defined');
  }
  tx.create(ref,{role:'participant',status:'pending',joinedAt:null,updatedAt:now()}); return {status:'pending'};
}));
exports.decideJoin = callable(async (uid,d) => {
  V.id(d.uid); V.check(typeof d.approve === 'boolean','Invalid decision');
  return db.runTransaction(async tx => {
    await authorize(tx,d.groupId,uid,true);
    const g=groupRef(d.groupId); const ref=g.collection('members').doc(d.uid);
    const [s,gs]=await Promise.all([tx.get(ref),tx.get(g)]);
    if (!s.exists || s.data().status!=='pending') fail('failed-precondition','Pending request required');
    const status=d.approve?'active':'rejected';
    tx.update(ref,{status,updatedAt:now(),joinedAt:d.approve?now():null});
    tx.create(db.collection('notifications').doc(),{ownerUid:d.uid,groupId:g.id,kind:d.approve?'join_approved':'join_rejected',message:d.approve?`${gs.data().name} 모임에 가입됐어요`:`${gs.data().name} 모임 참여가 승인되지 않았어요`,createdAt:now()});
    return {status};
  });
});
// A pending member cannot read groups directly. Only minimal own membership DTOs are returned.
exports.listMyGroups = callable(async uid => {
  const s=await db.collectionGroup('members').where('status','in',['active','pending']).get();
  const own=s.docs.filter(m => m.id===uid);
  const rows=await Promise.all(own.map(async m => {
    const g=await m.ref.parent.parent.get(); if (!g.exists) return null;
    return {groupId:g.id,name:g.data().name,description:g.data().description,role:m.data().role,status:m.data().status};
  })); return {groups:rows.filter(Boolean)};
});
exports.createActivity = callable(async (uid,d) => {
  const s=V.settings(d.settings); const ref=groupRef(d.groupId).collection('activities').doc();
  await db.runTransaction(async tx => {
    await authorize(tx,d.groupId,uid,true);
    const {questions,...fields}=s;
    tx.create(ref,{...fields,state:'recruiting',rosterVersion:0,settingsVersion:1,publishedVersionId:null,endedVersionId:null,learning:{enabled:true,modelId:null},startedAt:null,endedAt:null,reviewClosedAt:null,createdAt:now()});
    questions.forEach(q => {const {id,...fields}=q;tx.create(ref.collection('questions').doc(id),{...fields,questionVersion:1});});
  }); return {activityId:ref.id};
});
exports.updateActivitySettings = callable(async (uid,d) => {
  const s=V.settings(d.settings);
  return db.runTransaction(async tx => {
    const a=await activity(tx,d.groupId,d.activityId,uid,true,['recruiting','forming']);
    V.check(d.expectedSettingsVersion===a.data.settingsVersion,'Stale settings version');
    const old=await tx.get(a.ref.collection('questions'));
    // Full settings replacement with explicit expected version; no client-controlled counters.
    const next=new Map(s.questions.map(q=>[q.id,q]));
    const oldMap=new Map(old.docs.map(q=>[q.id,q.data()]));
    const changed = old.size!==s.questions.length || s.questions.some(q => {
      const prev=oldMap.get(q.id); return !prev || prev.key!==q.key || prev.multiSelect!==q.multiSelect || JSON.stringify(prev.scale)!==JSON.stringify(q.scale);
    });
    if (changed && a.data.state==='forming') fail('failed-precondition','Question changes after close require stage 3 response-request flow');
    const {questions,...fields}=s;
    tx.update(a.ref,{...fields,settingsVersion:a.data.settingsVersion+1});
    old.docs.forEach(q=>{if(!next.has(q.id))tx.delete(q.ref);});
    questions.forEach(q=>{
      const {id,...fields}=q;const prev=oldMap.get(id);
      const same=prev && prev.key===q.key && prev.multiSelect===q.multiSelect && JSON.stringify(prev.scale)===JSON.stringify(q.scale);
      // Activity version prevents remove/re-add ABA from accepting an old response version.
      tx.set(a.ref.collection('questions').doc(id),{...fields,questionVersion:same?prev.questionVersion:a.data.settingsVersion+1});
    }); return {settingsVersion:a.data.settingsVersion+1};
  });
});
exports.submitApplication = callable(async (uid,d) => db.runTransaction(async tx => {
  const a=await activity(tx,d.groupId,d.activityId,uid);
  const ref=a.ref.collection('applications').doc(uid);
  const [old,qs]=await Promise.all([tx.get(ref),tx.get(a.ref.collection('questions'))]);
  if (old.exists && old.data().status==='excluded') fail('failed-precondition','Excluded application cannot be restored by applicant');
  const answers=V.answers(d.answers,qs.docs.map(q=>({id:q.id,...q.data()})));
  const answerVersion=(old.exists?old.data().answerVersion:0)+1;
  tx.set(ref,{status:'applied',answers,answerVersion,updatedAt:now()});
  // roster changes only when applied membership changes, NOT on an answer-only edit (v3 2-1).
  if (!old.exists || old.data().status!=='applied') tx.update(a.ref,{rosterVersion:a.data.rosterVersion+1});
  return {answerVersion,rosterVersion:a.data.rosterVersion+(!old.exists || old.data().status!=='applied'?1:0)};
}));
exports.withdrawApplication = callable(async (uid,d) => db.runTransaction(async tx => {
  // Post-publication removal must also update public teams/draft/locks (stage 3).
  // Fail closed rather than leaving a withdrawn uid in a published team.
  const a=await activity(tx,d.groupId,d.activityId,uid,false,['recruiting','forming']);
  const ref=a.ref.collection('applications').doc(uid);const s=await tx.get(ref);
  if (!s.exists || s.data().status==='withdrawn') return {ok:true};
  if (s.data().status!=='applied') fail('failed-precondition','Applied status required');
  tx.update(ref,{status:'withdrawn',updatedAt:now()});tx.update(a.ref,{rosterVersion:a.data.rosterVersion+1});return {ok:true};
}));
function preferenceId(g,a,uid,target) {return createHash('sha256').update(JSON.stringify([g,a,uid,target])).digest('hex');}
exports.setPrivatePreference = callable(async (uid,d) => {
  V.id(d.targetUid);V.check(d.targetUid!==uid,'Cannot target self');
  V.check(d.confirmed===true,'Explicit confirmation required');
  return db.runTransaction(async tx => {
    const a=await activity(tx,d.groupId,d.activityId,uid);
    const meta=a.ref.collection('private').doc('meta');
    const pref=db.doc(`privatePreferences/${preferenceId(d.groupId,d.activityId,uid,d.targetUid)}`);
    const [owner,target,targetMember,active,old,m]=await Promise.all([
      tx.get(a.ref.collection('applications').doc(uid)),tx.get(a.ref.collection('applications').doc(d.targetUid)),
      tx.get(groupRef(d.groupId).collection('members').doc(d.targetUid)),
      tx.get(db.collection('privatePreferences').where('ownerUid','==',uid).where('groupId','==',d.groupId).where('activityId','==',d.activityId).where('status','==','active')),
      tx.get(pref),tx.get(meta)]);
    if (!owner.exists || owner.data().status!=='applied' || !target.exists || target.data().status!=='applied' || !targetMember.exists || targetMember.data().status!=='active') fail('failed-precondition','Active applicants required');
    V.canAddPreference(active.docs.map(p=>p.data().targetUid),d.targetUid);
    if(old.exists && old.data().status==='active')return {prefId:pref.id};
    tx.set(pref,{ownerUid:uid,targetUid:d.targetUid,groupId:d.groupId,activityId:d.activityId,status:'active',createdAt:old.exists?old.data().createdAt:now(),updatedAt:now()});
    // Shared meta document serializes concurrent preferences, including the 2-item cap.
    tx.set(meta,{prefVersion:(m.exists?m.data().prefVersion:0)+1},{merge:true});return {prefId:pref.id};
  });
});
exports.withdrawPrivatePreference = callable(async (uid,d) => db.runTransaction(async tx => {
  const pref=db.doc(`privatePreferences/${V.id(d.prefId)}`);const p=await tx.get(pref);
  if (!p.exists || p.data().ownerUid!==uid) fail('permission-denied','Own preference required');
  const a=await activity(tx,p.data().groupId,p.data().activityId,uid,false,['recruiting','forming','published','in_progress']);
  const meta=a.ref.collection('private').doc('meta');const m=await tx.get(meta);
  if(p.data().status==='withdrawn')return {ok:true};
  tx.update(pref,{status:'withdrawn',updatedAt:now()});tx.set(meta,{prefVersion:(m.exists?m.data().prefVersion:0)+1},{merge:true});return {ok:true};
}));
