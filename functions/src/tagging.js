'use strict';
// Stage 5 (편성학습_v3 7장): tag free-text feedback with ctag1 after feedback closes.
// The language model provider is NOT chosen yet (편성학습_v3 0장 🔒). A provider is any object with
//   classify({text, tags, sentiments, instructions, temperature}) -> {tags:[{tag,sentiment}], model, modelVersion}
// It must be called with temperature 0 and under a no-retention / no-training data agreement (12장).
// Raw comments never leave this module except through classify(), and are never logged.
const {now}=require('./common');
const {TAGS,SENTIMENTS,writeSummary}=require('./activity');

const TAG_VERSION='ctag1', MASK='[팀원]';
const INSTRUCTIONS=[
  '팀 활동 후기를 정해진 주제 태그와 감정으로만 분류하세요.',
  '팀 활동 전체에 대한 주제와 감정만 고르세요.',
  '특정 개인에 대한 평가나 성격 추론을 만들지 마세요.',
  '주어진 태그 목록에 없는 태그를 만들지 마세요.',
  '결과는 {"tags":[{"tag":"...","sentiment":"pos|neg|neutral"}]} 형식 JSON 하나만 돌려주세요.',
].join('\n');

function escape(s){return s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}

// Replace participants' names (longest first). One-character names are skipped: they would mask ordinary words.
function maskNames(text,names){
  const list=[...new Set(names.filter(n=>typeof n==='string').map(n=>n.trim()).filter(n=>n.length>=2))].sort((a,b)=>b.length-a.length);
  return list.reduce((t,n)=>t.replace(new RegExp(escape(n),'gi'),MASK),text);
}

// null = wrong format (retry); otherwise only known tag/sentiment pairs, deduplicated.
function validTags(result){
  if(!result||!Array.isArray(result.tags))return null;
  const seen=new Set(),out=[];
  for(const t of result.tags){
    if(!t||!TAGS.includes(t.tag)||!SENTIMENTS.includes(t.sentiment))continue;
    const key=`${t.tag}:${t.sentiment}`;if(seen.has(key))continue;seen.add(key);out.push({tag:t.tag,sentiment:t.sentiment});
  }
  return out;
}

async function classify(provider,text){
  for(let attempt=0;attempt<2;attempt++){
    try{
      const r=await provider.classify({text,tags:TAGS,sentiments:SENTIMENTS,instructions:INSTRUCTIONS,temperature:0});
      const tags=validTags(r);
      if(tags)return {version:TAG_VERSION,status:'ok',tags,model:String(r.model||''),modelVersion:String(r.modelVersion||'')};
    }catch(e){/* provider error: retry once, then record failure without the text */}
  }
  return {version:TAG_VERSION,status:'failed'};
}

async function participantNames(db,activity){
  const regs=await db.collection('registrations').where('activityId','==',activity.id).get();
  const uids=[...new Set(regs.docs.map(r=>r.data().userId))];
  const names=[];
  for(const uid of uids){
    const [m,u]=await Promise.all([db.doc(`memberships/${activity.groupId}_${uid}`).get(),db.doc(`users/${uid}`).get()]);
    if(m.exists)names.push(m.data().displayName);
    if(u.exists)names.push(u.data().displayName);
  }
  return names;
}

// Tags every consented, untagged comment of a closed activity, then refreshes the officer summary.
async function tagActivity(db,activityId,provider){
  const ref=db.doc(`activities/${activityId}`),snap=await ref.get();
  if(!snap.exists||snap.data().status!=='ended'||!snap.data().feedbackClosedAt)return {status:'not_closed',tagged:0};
  if(!provider)return {status:'no_provider',tagged:0};
  const activity={id:activityId,groupId:snap.data().groupId};
  const feedback=await db.collection('feedback').where('activityId','==',activityId).get();
  const todo=feedback.docs.filter(f=>f.data().learningConsent===true&&f.data().comment&&f.data().commentTags?.status!=='ok');
  const names=todo.length?await participantNames(db,activity):[];
  let tagged=0,failed=0;
  for(const f of todo){
    const tags=await classify(provider,maskNames(f.data().comment,names));
    await f.ref.update({commentTags:{...tags,taggedAt:now()}});
    tags.status==='ok'?tagged++:failed++;
  }
  await db.runTransaction(async tx=>{
    const rows=(await tx.get(db.collection('feedback').where('activityId','==',activityId))).docs.map(d=>d.data());
    await writeSummary(tx,db,activityId,rows);
  });
  return {status:'done',tagged,failed};
}

// Configured provider, or null until one is chosen and approved (then tagging runs; until then it is skipped).
function configuredProvider(){return null;}

module.exports={maskNames,validTags,classify,tagActivity,configuredProvider,TAG_VERSION,INSTRUCTIONS};
