'use strict';
// Stage 1-2 server commands on main's schema (docs/FIRESTORE.md "아직 구현해야 하는 서버 명령").
// Each handler is (db, uid, data) -> result and runs one transaction; index.js wraps them as callables.
// Order inside every command: login (caller) -> approved membership -> role -> object state.
// Admin SDK bypasses firestore.rules, so every check here is the only guard.
const {Timestamp}=require('firebase-admin/firestore');
const {createHash,randomInt}=require('node:crypto');
const V=require('./validation');

const {CommandError,fail,now,membership,requireMember,profile,loadActivity}=require('./common');
const hash=code=>createHash('sha256').update(code).digest('hex');
const INVITE_DAYS=7, PREVIEW_LIMIT=20, PREVIEW_WINDOW_MS=10*60*1000;

function newCode(){let c='';for(let i=0;i<10;i++)c+=V.CODE_ALPHABET[randomInt(V.CODE_ALPHABET.length)];return c;}
async function validInvitation(tx,db,code){
  const s=await tx.get(db.doc(`invitations/${hash(V.inviteCode(code))}`));
  if(!s.exists||s.data().active!==true||s.data().expiresAt.toMillis()<=Date.now())fail('not-found','초대가 만료되었거나 올바르지 않아요');
  return {id:s.id,groupId:s.data().groupId};
}
// Counted in its own transaction so failed code guesses are counted too (rateLimits/* is server-only).
async function countAttempt(db,uid,kind){
  await db.runTransaction(async tx=>{
    const ref=db.doc(`rateLimits/${uid}_${kind}`),s=await tx.get(ref),t=Date.now();
    const w=s.exists&&t-s.data().windowStart<PREVIEW_WINDOW_MS?s.data():{windowStart:t,count:0};
    if(w.count>=PREVIEW_LIMIT)fail('resource-exhausted','잠시 후 다시 시도해 주세요');
    tx.set(ref,{windowStart:w.windowStart,count:w.count+1});
  });
}

// ---------- 모임 ----------
async function createGroup(db,uid,d){
  const name=V.text(d.name,100),description=V.optionalText(d.description,2000);
  const themeColor=V.color(d.themeColor,'mint'),ref=db.collection('groups').doc();
  await db.runTransaction(async tx=>{
    const p=await profile(tx,db,uid);
    tx.create(ref,{name,description,ownerId:uid,themeColor,status:'active',createdAt:now(),updatedAt:now()});
    tx.create(db.doc(`memberships/${ref.id}_${uid}`),{groupId:ref.id,userId:uid,displayName:p.displayName,
      role:'admin',status:'approved',createdAt:now(),updatedAt:now()});
  });
  return {groupId:ref.id};
}

async function issueInvitation(db,uid,d){
  const g=V.noUnderscore(d.groupId),days=d.expiresInDays===undefined?INVITE_DAYS:d.expiresInDays;
  V.check(Number.isInteger(days)&&days>=1&&days<=30,'Invitation lasts 1-30 days');
  const code=newCode(),expiresAt=Timestamp.fromMillis(Date.now()+days*86400000);
  await db.runTransaction(async tx=>{
    await requireMember(tx,db,g,uid,true);
    const ref=db.doc(`invitations/${hash(code)}`);
    if((await tx.get(ref)).exists)fail('aborted','다시 시도해 주세요');
    tx.create(ref,{groupId:g,expiresAt,active:true,createdBy:uid,createdAt:now()});
  });
  // The code is returned once and never stored in plain text.
  return {code,expiresAt:expiresAt.toMillis()};
}

async function previewInvitation(db,uid,d){
  if(d.code!==undefined)await countAttempt(db,uid,'invite');
  return db.runTransaction(async tx=>{
    const g=d.code!==undefined?(await validInvitation(tx,db,d.code)).groupId:V.noUnderscore(d.groupId);
    const [group,mine,members]=await Promise.all([tx.get(db.doc(`groups/${g}`)),membership(tx,db,g,uid),
      tx.get(db.collection('memberships').where('groupId','==',g).where('status','==','approved'))]);
    if(!group.exists||group.data().status!=='active')fail('not-found','모임을 찾을 수 없어요');
    // Without a code, only people who already asked to join may see the safe preview.
    if(d.code===undefined&&!(mine.data&&['pending','approved'].includes(mine.data.status)))fail('permission-denied','초대 코드가 필요해요');
    return {groupId:g,name:group.data().name,description:group.data().description,themeColor:group.data().themeColor,
      memberCount:members.size,myStatus:mine.data?mine.data.status:null};
  });
}

async function requestJoin(db,uid,d){
  await countAttempt(db,uid,'invite');
  return db.runTransaction(async tx=>{
    const inv=await validInvitation(tx,db,d.code),g=inv.groupId;
    const [group,mine,p]=await Promise.all([tx.get(db.doc(`groups/${g}`)),membership(tx,db,g,uid),profile(tx,db,uid)]);
    if(!group.exists||group.data().status!=='active')fail('not-found','모임을 찾을 수 없어요');
    if(mine.data&&['approved','pending'].includes(mine.data.status))return {groupId:g,status:mine.data.status};
    tx.set(mine.ref,{groupId:g,userId:uid,displayName:p.displayName,role:'member',status:'pending',invitationId:inv.id,
      createdAt:mine.data?mine.data.createdAt:now(),updatedAt:now()});
    return {groupId:g,status:'pending'};
  });
}

async function decideJoin(db,uid,d,approve){
  const g=V.noUnderscore(d.groupId),target=V.id(d.userId);
  return db.runTransaction(async tx=>{
    await requireMember(tx,db,g,uid,true);
    const m=await membership(tx,db,g,target),want=approve?'approved':'rejected';
    if(m.data&&m.data.status===want)return {status:want};
    if(!m.data||m.data.status!=='pending')fail('failed-precondition','대기 중인 가입 요청이 없어요');
    tx.update(m.ref,{status:want,updatedAt:now()});
    tx.set(db.doc(`notifications/${approve?'joinApproved':'joinRejected'}_${g}_${target}_${m.data.updatedAt.toMillis()}`),
      {userId:target,type:approve?'joinApproved':'joinRejected',groupId:g,createdAt:now(),readAt:null});
    return {status:want};
  });
}

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

module.exports={CommandError,hash,createGroup,issueInvitation,previewInvitation,requestJoin,
  approveJoin:(db,uid,d)=>decideJoin(db,uid,d,true),rejectJoin:(db,uid,d)=>decideJoin(db,uid,d,false),
  createActivity,submitRegistration,updateRegistration,cancelRegistration,setPlacementPreference,revokePlacementPreference};
