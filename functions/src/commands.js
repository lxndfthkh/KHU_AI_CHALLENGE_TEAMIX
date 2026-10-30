'use strict';
// Stage 1-2 server commands on main's schema (docs/FIRESTORE.md).
// Group creation, invitations, join requests and join decisions are done by the app itself under
// firestore.rules (main: lib/data/firestore_group_writer.dart, firestore_invitations.dart,
// firestore_join_requests.dart). The server keeps only what rules cannot guard: activities,
// sign-ups and private placement preferences.
// Each handler is (db, uid, data) -> result and runs one transaction; index.js wraps them as callables.
// Order inside every command: login (caller) -> approved membership -> role -> object state.
// Admin SDK bypasses firestore.rules, so every check here is the only guard.
const {Timestamp}=require('firebase-admin/firestore');
const V=require('./validation');
const {CommandError,fail,now,membership,requireMember,loadActivity}=require('./common');

// ---------- 소모임 ----------
async function createActivity(db,uid,d){
  const g=V.noUnderscore(d.groupId),value=V.activity(d),ref=db.collection('activities').doc();
  await db.runTransaction(async tx=>{
    await requireMember(tx,db,g,uid,true);
    const group=await tx.get(db.doc(`groups/${g}`));
    if(!group.exists||group.data().status!=='active')fail('not-found','모임을 찾을 수 없어요');
    tx.create(ref,{groupId:g,title:value.title,description:value.description,createdBy:uid,
      themeColor:V.color(d.themeColor,group.data().themeColor),capacity:value.capacity,targetTeamSize:value.targetTeamSize,
      deadlineAt:Timestamp.fromMillis(value.deadlineAt),status:'recruiting',participantCount:0,questionsLockedAt:null,
      publishedVersion:null,createdAt:now(),updatedAt:now()});
    for(const q of value.questions){const {id,...rest}=q;tx.create(ref.collection('questions').doc(id),rest);}
    // Engine contract read by algorithm/repository.py; teamIds/capacities are set at closeRecruitment.
    tx.create(ref.collection('settings').doc('matching'),{...value.matching,capacityInitialized:false,settingsVersion:1,updatedAt:now()});
  });
  return {activityId:ref.id};
}

async function registrationContext(tx,db,uid,d,states=['recruiting']){
  const a=await loadActivity(tx,db,d.activityId);
  await requireMember(tx,db,a.data.groupId,uid);
  if(!states.includes(a.data.status))fail('failed-precondition','지금은 신청을 바꿀 수 없어요');
  const ref=db.doc(`registrations/${a.ref.id}_${uid}`),old=await tx.get(ref);
  return {a,ref,old:old.exists?old.data():null};
}
async function enabledQuestions(tx,a){
  const s=await tx.get(a.ref.collection('questions'));
  return s.docs.map(q=>({id:q.id,...q.data()})).filter(q=>q.enabled);
}
function open(a){if(a.data.deadlineAt.toMillis()<=Date.now())fail('failed-precondition','모집 기간이 끝났어요');}

async function submitRegistration(db,uid,d){
  return db.runTransaction(async tx=>{
    const {a,ref,old}=await registrationContext(tx,db,uid,d);open(a);
    const answers=V.answers(d.answers,await enabledQuestions(tx,a));
    if(old&&old.status==='submitted')return {status:'submitted',participantCount:a.data.participantCount};
    if(a.data.participantCount>=a.data.capacity)fail('resource-exhausted','모집 인원이 다 찼어요');
    tx.set(ref,{activityId:a.ref.id,groupId:a.data.groupId,userId:uid,status:'submitted',answers,
      submittedAt:old?old.submittedAt:now(),updatedAt:now()});
    const patch={participantCount:a.data.participantCount+1,updatedAt:now()};
    if(!a.data.questionsLockedAt)patch.questionsLockedAt=now();
    tx.update(a.ref,patch);
    return {status:'submitted',participantCount:patch.participantCount};
  });
}

async function updateRegistration(db,uid,d){
  return db.runTransaction(async tx=>{
    const {a,ref,old}=await registrationContext(tx,db,uid,d);open(a);
    if(!old||old.status!=='submitted')fail('failed-precondition','먼저 신청해 주세요');
    const answers=V.answers(d.answers,await enabledQuestions(tx,a));
    if(JSON.stringify(answers)===JSON.stringify(old.answers))return {status:'submitted',changed:false};
    tx.update(ref,{answers,updatedAt:now()});
    return {status:'submitted',changed:true};
  });
}

async function cancelRegistration(db,uid,d){
  return db.runTransaction(async tx=>{
    const {a,ref,old}=await registrationContext(tx,db,uid,d,['recruiting','closed']);
    // After publication a leaver changes published teams; that is handled with re-formation, not here.
    if(a.data.publishedVersion)fail('failed-precondition','팀이 공개된 뒤에는 임원진에게 요청해 주세요');
    if(!old||old.status!=='submitted')return {status:old?old.status:null};
    tx.update(ref,{status:'cancelled',updatedAt:now()});
    tx.update(a.ref,{participantCount:Math.max(0,a.data.participantCount-1),updatedAt:now()});
    return {status:'cancelled'};
  });
}

// ---------- 비공개 배치 선호 ----------
async function setPlacementPreference(db,uid,d){
  const g=V.noUnderscore(d.groupId),target=V.id(d.targetUserId);
  V.check(d.confirmed===true,'Explicit confirmation required');
  V.check(target!==uid,'자기 자신은 지목할 수 없어요');
  return db.runTransaction(async tx=>{
    await requireMember(tx,db,g,uid);
    const t=await membership(tx,db,g,target);
    if(!t.data||t.data.status!=='approved')fail('failed-precondition','같은 모임 회원만 지목할 수 있어요');
    const ref=db.doc(`placementPreferences/${g}_${uid}_${target}`),old=await tx.get(ref);
    if(old.exists&&old.data().active===true)return {active:true};
    const active=await tx.get(db.collection('placementPreferences').where('groupId','==',g).where('userId','==',uid).where('active','==',true));
    if(active.size>=V.MAX_PREFERENCES)fail('resource-exhausted','한 모임에서 최대 2명까지 지목할 수 있어요');
    tx.set(ref,{groupId:g,userId:uid,targetUserId:target,active:true,createdAt:old.exists?old.data().createdAt:now(),updatedAt:now()});
    return {active:true};
  });
}

async function revokePlacementPreference(db,uid,d){
  const g=V.noUnderscore(d.groupId),target=V.id(d.targetUserId);
  return db.runTransaction(async tx=>{
    const ref=db.doc(`placementPreferences/${g}_${uid}_${target}`),old=await tx.get(ref);
    // Revoking is always allowed for the author, even after leaving the group.
    if(!old.exists||old.data().userId!==uid||old.data().active!==true)return {active:false};
    tx.update(ref,{active:false,updatedAt:now()});
    return {active:false};
  });
}

module.exports={CommandError,createActivity,submitRegistration,updateRegistration,cancelRegistration,
  setPlacementPreference,revokePlacementPreference};
