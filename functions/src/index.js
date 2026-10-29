'use strict';
// Canonical main schema: memberships, owner/admin/member, top-level activities.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,FieldValue,Timestamp}=require('firebase-admin/firestore');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {randomBytes}=require('node:crypto');
const V=require('./validation');
initializeApp();
const db=getFirestore(), now=()=>FieldValue.serverTimestamp();
const fail=(code,message)=>{throw new HttpsError(code,message);};
const callable=fn=>onCall({region:'asia-northeast3'},async req=>{
  if(!req.auth)fail('unauthenticated','Login required');
  try{return await fn(req.auth.uid,req.data||{});}catch(e){if(e instanceof V.ValidationError)fail('invalid-argument',e.message);throw e;}
});
const group=g=>db.doc(`groups/${V.id(g)}`);
const act=a=>db.doc(`activities/${V.id(a)}`);
async function authorize(tx,g,uid,operator=false){
  const s=await tx.get(group(g).collection('memberships').doc(uid));
  if(!s.exists||!['owner','admin','member'].includes(s.data().role)||(operator&&!['owner','admin'].includes(s.data().role)))fail('permission-denied','Membership required');
  return s.data();
}
async function activity(tx,g,a,uid,operator=false,states=['recruiting']){
  await authorize(tx,g,uid,operator);const ref=act(a),s=await tx.get(ref);
  if(!s.exists||s.data().groupId!==g)fail('not-found','Activity not found');
  if(!states.includes(s.data().status))fail('failed-precondition','Activity state does not allow operation');
  return {ref,data:s.data()};
}
exports.initializeProfile=callable(async(uid,d)=>{
  const nickname=V.text(d.nickname??d.displayName,40),termsVersion=V.text(d.termsVersion,80);
  V.check(d.termsAgreed===true,'Terms consent required');
  await db.runTransaction(async tx=>{
    const ref=db.doc(`users/${uid}`),s=await tx.get(ref);
    if(s.exists)fail('already-exists','Profile already initialized');
    tx.create(ref,{nickname,profileImagePath:null,createdAt:now()});
    tx.set(db.doc(`profileSettings/${uid}`),{terms:{version:termsVersion,at:now()},learning:{agreed:false,version:'l1',at:now()}});
  });return {uid};
});
exports.setLearningConsent=callable(async(uid,d)=>{
  V.check(typeof d.agreed==='boolean','Boolean required');
  await db.runTransaction(async tx=>{
    const s=await tx.get(db.doc(`users/${uid}`));if(!s.exists)fail('failed-precondition','Profile required');
    tx.set(db.doc(`profileSettings/${uid}`),{learning:{agreed:d.agreed,version:'l1',at:now()}},{merge:true});
  });return {ok:true};
});
exports.createGroup=callable(async(uid,d)=>{
  const name=V.text(d.name,100),description=V.text(d.description,2000),ref=db.collection('groups').doc();
  const code=randomBytes(12).toString('hex').toUpperCase(),inviteRef=ref.collection('invites').doc();
  await db.runTransaction(async tx=>{
    const p=await tx.get(db.doc(`users/${uid}`));if(!p.exists)fail('failed-precondition','Profile required');
    tx.create(ref,{name,description,ownerUid:uid,createdAt:now()});
    tx.create(ref.collection('memberships').doc(uid),{uid,groupId:ref.id,nickname:p.data().nickname,role:'owner',joinedAt:now()});
    tx.create(inviteRef,{code,enabled:true,expiresAt:Timestamp.fromMillis(Date.now()+7*86400000),createdAt:now()});
    tx.create(db.doc(`inviteCodes/${code}`),{groupId:ref.id,inviteId:inviteRef.id});
  });return {groupId:ref.id,inviteCode:code};
});
async function invite(tx,code,expectedGroup){
  V.check(typeof code==='string'&&/^[A-Z0-9]{6,32}$/.test(code),'Invalid invite code');
  const index=await tx.get(db.doc(`inviteCodes/${code}`));if(!index.exists)fail('not-found','Invalid invite');
  const g=index.data().groupId,i=index.data().inviteId;
  const s=await tx.get(group(g).collection('invites').doc(V.id(i)));
  if(!s.exists||!s.data().enabled||s.data().code!==code||(s.data().expiresAt&&s.data().expiresAt.toMillis()<=Date.now())||(expectedGroup&&g!==expectedGroup))fail('not-found','Invalid or expired invite');
  return {g,i};
}
exports.previewInvite=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const {g}=await invite(tx,d.inviteCode),ref=group(g);
  const [s,m,r,people]=await Promise.all([tx.get(ref),tx.get(ref.collection('memberships').doc(uid)),tx.get(ref.collection('joinRequests').doc(uid)),tx.get(ref.collection('memberships'))]);
  if(!s.exists)fail('not-found','Group not found');
  return {groupId:g,name:s.data().name,description:s.data().description,memberCount:people.size,status:m.exists?'active':r.exists?r.data().status:null};
}));
exports.requestJoin=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const {g,i}=await invite(tx,d.inviteCode,d.groupId),ref=group(g),request=ref.collection('joinRequests').doc(uid);
  const [m,r,p,s]=await Promise.all([tx.get(ref.collection('memberships').doc(uid)),tx.get(request),tx.get(db.doc(`users/${uid}`)),tx.get(ref)]);
  if(!p.exists||!s.exists)fail('failed-precondition','Profile/group required');
  if(m.exists)return {status:'active'};
  if(r.exists&&r.data().status==='pending')return {status:'pending'};
  tx.set(request,{uid,groupId:g,groupName:s.data().name,nickname:p.data().nickname,status:'pending',requestedAt:now(),reviewedAt:null,reviewedBy:null,inviteId:i});
  return {status:'pending'};
}));
exports.decideJoin=callable(async(uid,d)=>db.runTransaction(async tx=>{
  V.id(d.uid);V.check(typeof d.approve==='boolean','Invalid decision');await authorize(tx,d.groupId,uid,true);
  const ref=group(d.groupId),request=ref.collection('joinRequests').doc(d.uid),member=ref.collection('memberships').doc(d.uid);
  const [r,m,g]=await Promise.all([tx.get(request),tx.get(member),tx.get(ref)]);
  if(!r.exists||r.data().status!=='pending'||m.exists||!g.exists)fail('failed-precondition','Pending nonmember required');
  const status=d.approve?'approved':'rejected';
  tx.update(request,{status,reviewedAt:now(),reviewedBy:uid});
  if(d.approve)tx.create(member,{uid:d.uid,groupId:d.groupId,nickname:r.data().nickname,role:'member',joinedAt:now()});
  tx.create(db.collection('notifications').doc(),{ownerUid:d.uid,groupId:d.groupId,kind:d.approve?'join_approved':'join_rejected',createdAt:now()});
  return {status:d.approve?'active':'rejected'};
}));
exports.listMyGroups=callable(async uid=>{
  const [members,requests]=await Promise.all([db.collectionGroup('memberships').where('uid','==',uid).get(),db.collectionGroup('joinRequests').where('uid','==',uid).get()]);
  const rows=new Map();
  for(const s of members.docs){const parts=s.ref.path.split('/');if(parts.length!==4||parts[0]!=='groups'||s.id!==uid)continue;
    const g=await s.ref.parent.parent.get();if(g.exists)rows.set(g.id,{groupId:g.id,name:g.data().name,description:g.data().description,role:s.data().role,status:'active'});}
  for(const s of requests.docs){const parts=s.ref.path.split('/');if(parts.length!==4||parts[0]!=='groups'||s.id!==uid||s.data().status!=='pending'||rows.has(parts[1]))continue;
    rows.set(parts[1],{groupId:parts[1],name:s.data().groupName,description:'',role:null,status:'pending'});}
  return {groups:[...rows.values()]};
});
exports.createActivity=callable(async(uid,d)=>{
  const value=V.mainActivity(d),ref=db.collection('activities').doc();
  await db.runTransaction(async tx=>{await authorize(tx,d.groupId,uid,true);
    tx.create(ref,{...value,groupId:V.id(d.groupId),createdBy:uid,applicationCount:0,responseVersion:0,settingsVersion:1,
      currentPublicationId:null,publicationVersion:0,status:'recruiting',createdAt:now(),updatedAt:now(),deadline:Timestamp.fromMillis(value.deadline)});
  });return {activityId:ref.id};
});
exports.updateActivitySettings=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const a=await activity(tx,d.groupId,d.activityId,uid,true);
  V.check(d.expectedSettingsVersion===a.data.settingsVersion,'Stale settings version');
  V.check(a.data.responseVersion===0,'Use stage 3 settings after responses exist');
  const value=V.mainActivity(d);
  tx.update(a.ref,{...value,deadline:Timestamp.fromMillis(value.deadline),settingsVersion:a.data.settingsVersion+1,updatedAt:now()});
  return {settingsVersion:a.data.settingsVersion+1};
}));
exports.submitApplication=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const a=await activity(tx,d.groupId,d.activityId,uid),ref=a.ref.collection('applications').doc(uid);
  if(a.data.currentPublicationId||a.data.publicationVersion!==0||a.data.deadline.toMillis()<=Date.now())fail('failed-precondition','Recruitment closed');
  const [old,member]=await Promise.all([tx.get(ref),tx.get(group(d.groupId).collection('memberships').doc(uid))]);
  const answers=V.mainAnswers(d.answers,a.data.questions),delta=old.exists&&old.data().status==='submitted'?0:1;
  if(old.exists&&old.data().status==='submitted'&&JSON.stringify(answers)===JSON.stringify(old.data().answers))return {responseVersion:a.data.responseVersion};
  V.check(a.data.applicationCount+delta<=a.data.recruitmentCapacity,'Recruitment full');
  tx.set(ref,{uid,groupId:d.groupId,status:'submitted',answers,nicknameSnapshot:member.data().nickname,
    submittedAt:old.exists?old.data().submittedAt:now(),updatedAt:now()});
  tx.update(a.ref,{applicationCount:a.data.applicationCount+delta,responseVersion:a.data.responseVersion+1});
  return {answerVersion:a.data.responseVersion+1,responseVersion:a.data.responseVersion+1};
}));
exports.withdrawApplication=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const a=await activity(tx,d.groupId,d.activityId,uid,false,['recruiting','closed']),ref=a.ref.collection('applications').doc(uid),s=await tx.get(ref);
  if(a.data.currentPublicationId||a.data.publicationVersion!==0)fail('failed-precondition','Post-publication withdrawal requires team cleanup');
  if(!s.exists||s.data().status==='withdrawn')return {ok:true};
  V.check(s.data().status==='submitted','Submitted application required');
  tx.update(ref,{status:'withdrawn',updatedAt:now()});tx.update(a.ref,{applicationCount:a.data.applicationCount-1,responseVersion:a.data.responseVersion+1});return {ok:true};
}));
exports.setPrivatePreference=callable(async(uid,d)=>db.runTransaction(async tx=>{
  V.id(d.targetUid);V.check(uid!==d.targetUid&&d.confirmed===true,'Explicit confirmation required');
  await authorize(tx,d.groupId,uid);await authorize(tx,d.groupId,d.targetUid);
  const ref=db.doc(`privatePreferences/${uid}/groups/${V.id(d.groupId)}`),s=await tx.get(ref);
  const targets=s.exists?s.data().targets:[];
  V.canAddPreference(targets.map(t=>t.targetUid),d.targetUid);
  const next=targets.filter(t=>t.targetUid!==d.targetUid).concat({targetUid:d.targetUid,confirmed:true});
  tx.set(ref,{authorUid:uid,groupId:d.groupId,targets:next,updatedAt:now()});return {prefId:d.targetUid};
}));
exports.withdrawPrivatePreference=callable(async(uid,d)=>db.runTransaction(async tx=>{
  const g=V.id(d.groupId),target=V.id(d.targetUid??d.prefId),ref=db.doc(`privatePreferences/${uid}/groups/${g}`),s=await tx.get(ref);
  if(!s.exists)return {ok:true};
  tx.update(ref,{targets:s.data().targets.filter(t=>t.targetUid!==target),updatedAt:now()});return {ok:true};
}));
exports.listPrivatePreferences=callable(async(uid,d)=>{
  const s=await db.doc(`privatePreferences/${uid}/groups/${V.id(d.groupId)}`).get();
  return {targets:s.exists?s.data().targets:[]};
});
