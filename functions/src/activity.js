'use strict';
// Stage 4 (편성학습_v4 1-3, 3장, 4-1) on main's schema: activity start/end, feedback, consent, team summary.
// Feedback is scores only: free text and language-model tagging were removed in 편성학습_v4.
// main fields are kept as they are; additions are documented in firestore.schema.json.
//   activities/{a}: startedAt, endedAt, endedVersion, feedbackClosedAt (main status stays recruiting|closed|active|ended)
//   feedback/{a}_{uid}: main fields (comment unused) + scores, questionnaireVersion, teamVersion, membershipRatio, learningConsent
//   activities/{a}/feedbackSummary/current: per-team aggregates, only teams with >= MIN_RESPONDENTS
//   consents/{uid}: learning consent (users/{uid} rules allow only displayName/createdAt/updatedAt)
const {Timestamp}=require('firebase-admin/firestore');
const V=require('./validation');
const {fail,now,requireMember,profile,loadActivity}=require('./common');

const QUESTIONNAIRE='r2', SCORE_KEYS=['overall','schedule','roles','rejoin'];
const MIN_RESPONDENTS=3, FEEDBACK_DAYS=7, CONSENT_VERSION='l2';

async function setLearningConsent(db,uid,d){
  V.check(typeof d.agreed==='boolean','agreed must be boolean');
  await db.runTransaction(async tx=>{
    await profile(tx,db,uid);
    tx.set(db.doc(`consents/${uid}`),{learning:{agreed:d.agreed,version:CONSENT_VERSION,at:now()},updatedAt:now()},{merge:true});
  });
  return {agreed:d.agreed};
}

async function adminActivity(tx,db,uid,d){
  const a=await loadActivity(tx,db,d.activityId);
  await requireMember(tx,db,a.data.groupId,uid,true);
  return a;
}

async function startActivity(db,uid,d){
  return db.runTransaction(async tx=>{
    const a=await adminActivity(tx,db,uid,d);
    if(a.data.status==='active')return {status:'active'};
    if(a.data.status!=='closed'||!a.data.publishedVersion)fail('failed-precondition','팀을 공개한 뒤에 시작할 수 있어요');
    tx.update(a.ref,{status:'active',startedAt:Timestamp.now(),updatedAt:now()});
    return {status:'active'};
  });
}

async function endActivity(db,uid,d){
  return db.runTransaction(async tx=>{
    const a=await adminActivity(tx,db,uid,d);
    if(a.data.status==='ended')return {status:'ended',endedVersion:a.data.endedVersion};
    if(a.data.status!=='active')fail('failed-precondition','진행 중인 활동만 종료할 수 있어요');
    const version=a.data.publishedVersion,pub=await tx.get(db.doc(`publications/${a.ref.id}_v${version}`));
    if(!pub.exists)fail('failed-precondition','공개된 팀을 찾을 수 없어요');
    tx.update(a.ref,{status:'ended',endedAt:Timestamp.now(),endedVersion:version,feedbackClosedAt:null,updatedAt:now()});
    // Only people in the ending version are asked for feedback (3-2 rule 4).
    for(const team of pub.data().teams)for(const m of team.members)
      tx.set(db.doc(`notifications/feedbackRequested_${a.ref.id}_${m.uid}`),{userId:m.uid,type:'feedbackRequested',
        groupId:a.data.groupId,activityId:a.ref.id,createdAt:now(),readAt:null});
    return {status:'ended',endedVersion:version};
  });
}

function millis(t){return t&&typeof t.toMillis==='function'?t.toMillis():t instanceof Date?t.getTime():null;}

// Share of the activity period [startedAt, endedAt] the user spent in `teamId` across publications (3-2 rule 2).
function membershipRatio(publications,uid,teamId,startedAt,endedAt){
  const start=millis(startedAt),end=millis(endedAt);
  if(end<=start)return 1;
  let inside=0;
  for(const p of publications){
    if(!p.teams.some(t=>t.teamId===teamId&&t.members.some(m=>m.uid===uid)))continue;
    const from=Math.max(start,millis(p.validFrom??p.publishedAt)),to=Math.min(end,p.validTo?millis(p.validTo):end);
    if(to>from)inside+=to-from;
  }
  return Math.round(inside/(end-start)*1000)/1000;
}

function scores(input){
  V.check(V.plain(input)&&Object.keys(input).length===SCORE_KEYS.length&&SCORE_KEYS.every(k=>Number.isInteger(input[k])&&input[k]>=1&&input[k]<=5),
    'scores need overall, schedule, roles, rejoin as 1-5');
  return Object.fromEntries(SCORE_KEYS.map(k=>[k,input[k]]));
}

// Officer-visible aggregate (score averages only). Teams with fewer than MIN_RESPONDENTS respondents are left out.
function summarize(feedback){
  const byTeam=new Map();
  for(const f of feedback){if(!byTeam.has(f.teamId))byTeam.set(f.teamId,[]);byTeam.get(f.teamId).push(f);}
  const teams={};
  for(const [teamId,rows] of byTeam){
    if(rows.length<MIN_RESPONDENTS)continue;
    const averages=Object.fromEntries(SCORE_KEYS.map(k=>[k,Math.round(rows.reduce((s,r)=>s+r.scores[k],0)/rows.length*100)/100]));
    teams[teamId]={respondents:rows.length,averages};
  }
  return {questionnaireVersion:QUESTIONNAIRE,minRespondents:MIN_RESPONDENTS,teams};
}

async function writeSummary(tx,db,a,feedback){
  tx.set(db.doc(`activities/${a}/feedbackSummary/current`),{...summarize(feedback),updatedAt:now()});
}

async function submitFeedback(db,uid,d){
  const s=scores(d.scores);
  V.check(d.comment===undefined||d.comment===null,'Free-text comments are not collected');
  return db.runTransaction(async tx=>{
    const a=await loadActivity(tx,db,d.activityId);
    await requireMember(tx,db,a.data.groupId,uid);
    if(a.data.status!=='ended'||a.data.feedbackClosedAt)fail('failed-precondition','후기를 받는 기간이 아니에요');
    const [pubs,others,consent,old]=await Promise.all([
      tx.get(db.collection('publications').where('activityId','==',a.ref.id)),
      tx.get(db.collection('feedback').where('activityId','==',a.ref.id)),
      tx.get(db.doc(`consents/${uid}`)),tx.get(db.doc(`feedback/${a.ref.id}_${uid}`))]);
    const publications=pubs.docs.map(p=>p.data());
    const ended=publications.find(p=>p.version===a.data.endedVersion);
    const team=ended&&ended.teams.find(t=>t.members.some(m=>m.uid===uid));
    if(!team)fail('permission-denied','종료 시점 팀의 참가자만 후기를 쓸 수 있어요');
    const prev=old.exists?old.data():null;
    const doc={activityId:a.ref.id,groupId:a.data.groupId,userId:uid,teamId:team.teamId,rating:s.overall,scores:s,
      questionnaireVersion:QUESTIONNAIRE,teamVersion:a.data.endedVersion,
      membershipRatio:membershipRatio(publications,uid,team.teamId,a.data.startedAt,a.data.endedAt),
      learningConsent:consent.exists&&consent.data().learning?.agreed===true,
      createdAt:prev?prev.createdAt:now(),updatedAt:now()};
    tx.set(old.ref,doc);
    const all=others.docs.filter(f=>f.id!==old.ref.id).map(f=>f.data()).concat(doc);
    await writeSummary(tx,db,a.ref.id,all);
    return {teamId:team.teamId,membershipRatio:doc.membershipRatio};
  });
}

async function closeFeedback(db,uid,d){
  return db.runTransaction(async tx=>{
    const a=await adminActivity(tx,db,uid,d);
    if(a.data.status!=='ended')fail('failed-precondition','종료된 활동만 후기를 마감할 수 있어요');
    if(a.data.feedbackClosedAt)return {closed:true};
    tx.update(a.ref,{feedbackClosedAt:Timestamp.now(),updatedAt:now()});
    return {closed:true};
  });
}

// Scheduled: close feedback FEEDBACK_DAYS after the activity ended.
async function closeExpiredFeedback(db,nowMs=Date.now()){
  const due=await db.collection('activities').where('status','==','ended').where('feedbackClosedAt','==',null).get();
  const closed=[];
  for(const s of due.docs){
    if(millis(s.data().endedAt)>nowMs-FEEDBACK_DAYS*86400000)continue;
    await db.runTransaction(async tx=>{
      const cur=await tx.get(s.ref);
      if(cur.data().status==='ended'&&!cur.data().feedbackClosedAt){tx.update(s.ref,{feedbackClosedAt:Timestamp.fromMillis(nowMs),updatedAt:now()});closed.push(s.id);}
    });
  }
  return closed;
}

module.exports={setLearningConsent,startActivity,endActivity,submitFeedback,closeFeedback,closeExpiredFeedback,
  membershipRatio,summarize,writeSummary,MIN_RESPONDENTS,FEEDBACK_DAYS};
