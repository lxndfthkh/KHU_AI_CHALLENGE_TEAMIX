'use strict';
// Stage 9 (편성학습_v4 12장) and main's leaveGroup / deleteAccount commands.
//   deleteFeedback  author removes a review -> summary recomputed, training dataset marked dirty
//                   (the extraction job re-extracts the activity because its summary changed)
//   leaveGroup      membership -> left; sole admin blocked; preferences revoked; unpublished sign-ups cancelled
//   deleteAccount   personal documents deleted; published team records keep 'deleted-user';
//                   answer copies scrubbed from serverRuns; Firebase Auth user removed last
const {FieldValue}=require('firebase-admin/firestore');
const V=require('./validation');
const {fail,now,membership}=require('./common');
const {writeSummary,summarize}=require('./activity');

const DELETED='deleted-user', DELETED_NAME='삭제된 사용자', DATASET='trainingDatasets/fx1';

async function soleAdminGroups(get,db,uid){
  const mine=await get(db.collection('memberships').where('userId','==',uid).where('role','==','admin').where('status','==','approved'));
  const blocked=[];
  for(const m of mine.docs){
    const admins=await get(db.collection('memberships').where('groupId','==',m.data().groupId).where('role','==','admin').where('status','==','approved'));
    if(admins.size<=1)blocked.push(m.data().groupId);
  }
  return blocked;
}

async function deleteFeedback(db,uid,d){
  const a=V.noUnderscore(d.activityId);
  return db.runTransaction(async tx=>{
    const ref=db.doc(`feedback/${a}_${uid}`),[mine,all]=await Promise.all([tx.get(ref),tx.get(db.collection('feedback').where('activityId','==',a))]);
    if(!mine.exists||mine.data().userId!==uid)return {deleted:false};
    tx.delete(ref);
    await writeSummary(tx,db,a,all.docs.filter(f=>f.id!==ref.id).map(f=>f.data()));
    tx.set(db.doc(DATASET),{dirty:true,dirtyAt:now()},{merge:true});
    return {deleted:true};
  });
}

async function leaveGroup(db,uid,d){
  const g=V.noUnderscore(d.groupId);
  return db.runTransaction(async tx=>{
    const m=await membership(tx,db,g,uid);
    if(!m.data||m.data.status==='left')return {status:'left'};
    if(m.data.role==='admin'&&m.data.status==='approved'&&(await soleAdminGroups(q=>tx.get(q),db,uid)).includes(g))
      fail('failed-precondition','다른 임원진을 정한 뒤에 나갈 수 있어요');
    const [authored,targeted,regs]=await Promise.all([
      tx.get(db.collection('placementPreferences').where('groupId','==',g).where('userId','==',uid)),
      tx.get(db.collection('placementPreferences').where('groupId','==',g).where('targetUserId','==',uid)),
      tx.get(db.collection('registrations').where('groupId','==',g).where('userId','==',uid).where('status','==','submitted'))]);
    const activities=await Promise.all(regs.docs.map(r=>tx.get(db.doc(`activities/${r.data().activityId}`))));
    tx.update(m.ref,{status:'left',updatedAt:now()});
    for(const p of [...authored.docs,...targeted.docs])if(p.data().active)tx.update(p.ref,{active:false,updatedAt:now()});
    // Before publication a leaver simply drops out; after publication the team record stays (re-formation handles it).
    regs.docs.forEach((r,i)=>{
      const a=activities[i];
      if(!a.exists||a.data().publishedVersion||!['recruiting','closed'].includes(a.data().status))return;
      tx.update(r.ref,{status:'cancelled',updatedAt:now()});
      tx.update(a.ref,{participantCount:FieldValue.increment(-1),updatedAt:now()});
    });
    return {status:'left'};
  });
}

function scrubTeams(teams,uid){
  return (teams||[]).map(t=>({...t,members:(t.members||[]).map(m=>typeof m==='string'?(m===uid?DELETED:m)
    :m.uid===uid?{...m,uid:DELETED,displayName:DELETED_NAME,...('role' in m?{role:null}:{})}:m)}));
}
function scrubSummary(summary,uid){
  if(!summary)return summary;
  return Object.fromEntries(Object.entries(summary).map(([t,v])=>[t,{...v,members:(v.members||[]).map(m=>m===uid?DELETED:m)}]));
}
function scrubSnapshot(s,uid){
  const drop=o=>Object.fromEntries(Object.entries(o||{}).filter(([k])=>k!==uid));
  return {...s,participants:(s.participants||[]).filter(p=>p.id!==uid),published:drop(s.published),draft:drop(s.draft),locks:drop(s.locks),
    private_preferences:(s.private_preferences||[]).filter(p=>p.source!==uid&&p.target!==uid)};
}

// Writes in chunks; the command is idempotent, so a retry after a partial failure finishes the job.
async function commit(db,ops){
  for(let i=0;i<ops.length;i+=400){
    const batch=db.batch();
    for(const [op,ref,value] of ops.slice(i,i+400))
      op==='delete'?batch.delete(ref):op==='update'?batch.update(ref,value):batch.set(ref,value,op==='merge'?{merge:true}:{});
    await batch.commit();
  }
}

async function deleteAccount(db,uid,d,deps){
  V.check(d.confirm===true,'confirm: true required');
  const get=q=>q.get();
  const blocked=await soleAdminGroups(get,db,uid);
  if(blocked.length)fail('failed-precondition','혼자 임원진인 모임이 있어요. 다른 임원진을 정하거나 모임을 정리한 뒤 탈퇴할 수 있어요');
  const byUser=c=>get(db.collection(c).where('userId','==',uid));
  const [memberships,regs,feedback,authored,targeted,notes,views]=await Promise.all([byUser('memberships'),byUser('registrations'),byUser('feedback'),
    byUser('placementPreferences'),get(db.collection('placementPreferences').where('targetUserId','==',uid)),byUser('notifications'),byUser('teamViews')]);
  const ops=[];
  const activityIds=[...new Set([...regs.docs,...feedback.docs].map(s=>s.data().activityId))];
  for(const a of activityIds){
    const [act,pubs,draft,runs,secret,teamViews]=await Promise.all([get(db.doc(`activities/${a}`)),get(db.collection('publications').where('activityId','==',a)),
      get(db.doc(`drafts/${a}`)),get(db.collection('formationRuns').where('activityId','==',a)),get(db.collection('serverRuns').where('activityId','==',a)),
      get(db.collection('teamViews').where('activityId','==',a))]);
    for(const p of pubs.docs)ops.push(['update',p.ref,{teams:scrubTeams(p.data().teams,uid)}]);
    for(const v of teamViews.docs)if(v.data().userId!==uid)ops.push(['update',v.ref,{members:scrubTeams([{members:v.data().members}],uid)[0].members}]);
    if(draft.exists){
      const x=draft.data(),locks={...(x.locks||{})};delete locks[uid];
      ops.push(['update',draft.ref,{teams:scrubTeams(x.teams,uid).map(t=>({...t,members:t.members.filter(m=>m!==DELETED)})),
        unassigned:(x.unassigned||[]).filter(u=>u!==uid),locks,...(x.validation?{'validation.summary':scrubSummary(x.validation.summary,uid)}:{})}]);
    }
    for(const r of runs.docs)if(r.data().publicSummary)ops.push(['update',r.ref,{publicSummary:scrubSummary(r.data().publicSummary,uid)}]);
    for(const s of secret.docs)if(s.data().snapshot)ops.push(['update',s.ref,{snapshot:scrubSnapshot(s.data().snapshot,uid)}]);
    const reg=regs.docs.find(r=>r.data().activityId===a);
    if(act.exists&&reg&&reg.data().status==='submitted'&&!act.data().publishedVersion)
      ops.push(['update',act.ref,{participantCount:FieldValue.increment(-1),updatedAt:now()}]);
    if(feedback.docs.some(f=>f.data().activityId===a)){
      const rest=(await get(db.collection('feedback').where('activityId','==',a))).docs.filter(f=>f.data().userId!==uid).map(f=>f.data());
      ops.push(['set',db.doc(`activities/${a}/feedbackSummary/current`),{...summarize(rest),updatedAt:now()}]);
    }
  }
  for(const s of [...memberships.docs,...regs.docs,...feedback.docs,...authored.docs,...targeted.docs,...notes.docs,...views.docs])ops.push(['delete',s.ref]);
  for(const p of ['consents','users'])ops.push(['delete',db.doc(`${p}/${uid}`)]);
  ops.push(['delete',db.doc(`rateLimits/${uid}_invite`)]);
  if(feedback.size)ops.push(['merge',db.doc(DATASET),{dirty:true,dirtyAt:now()}]);
  await commit(db,ops);
  await deps.deleteAuthUser(uid);
  return {deleted:true,activities:activityIds.length};
}

module.exports={deleteFeedback,leaveGroup,deleteAccount,DELETED};
