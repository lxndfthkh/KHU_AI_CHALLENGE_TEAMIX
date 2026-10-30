'use strict';
// Input validation for main's schema (docs/FIRESTORE.md, firestore.schema.json). Pure; no Firestore.
class ValidationError extends Error {}
function check(ok,message){if(!ok)throw new ValidationError(message);}
function plain(v){return v!==null&&typeof v==='object'&&!Array.isArray(v);}
function text(v,max=120){check(typeof v==='string'&&v.trim().length>0&&v.length<=max,'Invalid text');return v.trim();}
function optionalText(v,max){if(v===undefined||v===null)return '';check(typeof v==='string'&&v.length<=max,'Invalid text');return v;}
function id(v){check(typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v),'Invalid ID');return v;}
function noUnderscore(v){check(!id(v).includes('_'),'ID must not contain _');return v;}
const COLORS=['mint','peach','lilac'];
function color(v,fallback){if(v===undefined||v===null)return fallback;check(COLORS.includes(v),'Invalid theme color');return v;}
function posInt(v,max){check(Number.isInteger(v)&&v>0&&v<=max,'Invalid positive integer');return v;}

// Matching engine criteria and the question type each requires (algorithm/repository.py CRITERIA).
const CRITERIA={role:'single',time:'multiple',interest:'multiple',experience:'scale'};
const TYPES=['single','multiple','scale'];
// Personality axes: each axis averages 1-3 required scale questions (reverse items scored 6 - answer).
const MAX_TRAITS=4, MAX_TRAIT_ITEMS=3;

function question(q,order){
  check(plain(q),'Question required');
  check(Object.keys(q).every(k=>['id','label','type','options','required','enabled'].includes(k)),'Unknown question field');
  const qid=id(q.id);check(/^[a-z0-9]{1,32}$/.test(qid),'Question ID must be lowercase letters/digits');
  check(TYPES.includes(q.type),'Invalid question type');
  let options=[];
  if(q.type==='scale')check(q.options===undefined||(Array.isArray(q.options)&&q.options.length===0),'Scale questions use 1-5 without options');
  else{
    check(Array.isArray(q.options)&&q.options.length>0&&q.options.length<=30,'Choice questions need 1-30 options');
    options=q.options.map(o=>{check(plain(o)&&Object.keys(o).every(k=>['id','label'].includes(k)),'Invalid option');
      check(typeof o.id==='string'&&/^[a-z0-9]{1,32}$/.test(o.id),'Option ID must be lowercase letters/digits');return {id:o.id,label:text(o.label,60)};});
    check(new Set(options.map(o=>o.id)).size===options.length,'Duplicate option ID');
  }
  return {id:qid,label:text(q.label,120),type:q.type,options,required:q.required!==false,order,enabled:q.enabled!==false};
}

function activity(d){
  check(plain(d),'Activity required');
  const questions=(()=>{check(Array.isArray(d.questions)&&d.questions.length<=20,'Up to 20 questions');return d.questions.map((q,i)=>question(q,i+1));})();
  check(new Set(questions.map(q=>q.id)).size===questions.length,'Duplicate question ID');
  const deadline=typeof d.deadlineAt==='string'?Date.parse(d.deadlineAt):d.deadlineAt;
  check(Number.isSafeInteger(deadline)&&deadline>Date.now(),'Future deadline required');
  return {title:text(d.title,120),description:optionalText(d.description,5000),capacity:posInt(d.capacity,500),
    targetTeamSize:posInt(d.targetTeamSize,50),deadlineAt:deadline,questions,matching:matching(d.matching,questions)};
}

function matching(m,questions){
  check(plain(m),'Matching settings required');
  check(Object.keys(m).every(k=>['method','questionCriteria','priority','requireCommonTime','traits'].includes(k)),'Unknown matching field');
  check(['balanced','similar'].includes(m.method),'Invalid method');
  check(plain(m.questionCriteria),'questionCriteria required');
  const byId=new Map(questions.map(q=>[q.id,q])),used=new Set();
  for(const [qid,criterion] of Object.entries(m.questionCriteria)){
    const q=byId.get(qid);
    check(q&&q.enabled,'Matching question must exist and be enabled');
    check(CRITERIA[criterion]===q.type,`${criterion} needs a ${CRITERIA[criterion]} question`);
    check(q.required,'Matching questions must be required');
    check(!used.has(criterion),'Each criterion maps to one question');used.add(criterion);
  }
  const traits=traitAxes(m.traits,byId,new Set(Object.keys(m.questionCriteria)));
  const enabledQuestionIds=questions.filter(q=>q.id in m.questionCriteria).map(q=>q.id);
  const expected=[...used,...(traits.length?['personality']:[]),'size'];
  const priority=m.priority===undefined?[...enabledQuestionIds.map(q=>m.questionCriteria[q]),...(traits.length?['personality']:[]),'size']:m.priority;
  check(Array.isArray(priority)&&priority.length===expected.length&&new Set(priority).size===expected.length&&priority.every(k=>expected.includes(k)),'Priority must list mapped criteria plus size once each');
  const requireCommonTime=m.requireCommonTime===true;
  check(m.requireCommonTime===undefined||typeof m.requireCommonTime==='boolean','requireCommonTime must be boolean');
  check(!requireCommonTime||used.has('time'),'Common time requires a time question');
  return {method:m.method,enabledQuestionIds,questionCriteria:{...m.questionCriteria},priority:[...priority],requireCommonTime,requiredRoles:[],...(traits.length?{traits}:{})};
}

function traitAxes(input,byId,taken){
  if(input===undefined||input===null)return [];
  check(Array.isArray(input)&&input.length<=MAX_TRAITS,`Up to ${MAX_TRAITS} personality axes`);
  const ids=new Set(),usedQ=new Set(taken);
  return input.map(t=>{
    check(plain(t)&&Object.keys(t).every(k=>['id','label','items'].includes(k)),'Invalid personality axis');
    check(typeof t.id==='string'&&/^[a-z0-9]{1,32}$/.test(t.id)&&!ids.has(t.id),'Axis ID must be unique lowercase letters/digits');ids.add(t.id);
    check(Array.isArray(t.items)&&t.items.length>0&&t.items.length<=MAX_TRAIT_ITEMS,`Each axis needs 1-${MAX_TRAIT_ITEMS} questions`);
    const items=t.items.map(i=>{
      check(plain(i)&&Object.keys(i).every(k=>['questionId','reverse'].includes(k)),'Invalid axis item');
      const q=byId.get(i.questionId);
      check(q&&q.enabled&&q.required&&q.type==='scale','Axis questions must be enabled, required scale questions');
      check(!usedQ.has(q.id),'A question can belong to one criterion or axis only');usedQ.add(q.id);
      check(i.reverse===undefined||typeof i.reverse==='boolean','reverse must be boolean');
      return {questionId:q.id,reverse:i.reverse===true};
    });
    return {id:t.id,label:text(t.label,30),items};
  });
}

// answers keyed by question ID; questions = enabled question docs ({id,type,options,required}).
function answers(input,questions){
  check(plain(input),'Answers required');
  const byId=new Map(questions.filter(q=>q.enabled).map(q=>[q.id,q])),out={};
  check(Object.keys(input).every(k=>byId.has(k)),'Unknown question');
  for(const q of byId.values()){
    const v=input[q.id];
    if(v===undefined||v===null){check(!q.required,`Answer required: ${q.id}`);continue;}
    const ids=q.options.map(o=>o.id);
    if(q.type==='scale')check(Number.isInteger(v)&&v>=1&&v<=5,'Scale answers are 1-5');
    else if(q.type==='single')check(typeof v==='string'&&ids.includes(v),'Invalid option');
    else check(Array.isArray(v)&&v.length>0&&new Set(v).size===v.length&&v.every(x=>ids.includes(x)),'Invalid options');
    out[q.id]=Array.isArray(v)?[...v]:v;
  }
  return out;
}

const MAX_PREFERENCES=2;
module.exports={ValidationError,check,plain,text,optionalText,id,noUnderscore,color,activity,matching,answers,MAX_PREFERENCES,CRITERIA,MAX_TRAITS,MAX_TRAIT_ITEMS};
