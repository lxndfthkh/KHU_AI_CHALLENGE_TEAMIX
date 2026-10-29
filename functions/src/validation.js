'use strict';
class ValidationError extends Error {}
function check(ok,message){if(!ok)throw new ValidationError(message);}
function text(v,max=120){check(typeof v==='string'&&v.trim().length>0&&v.length<=max,'Invalid text');return v.trim();}
function id(v){check(typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v),'Invalid ID');return v;}
function plain(v){return v!==null&&typeof v==='object'&&!Array.isArray(v);}
function uniqueStrings(v){return Array.isArray(v)&&v.length<=30&&new Set(v).size===v.length&&v.every(s=>typeof s==='string'&&s.length>0&&s.length<=120);}
function questions(q){
  check(plain(q),'Questions required');
  check(Object.keys(q).every(k=>['selected','roleOptions','timeOptions','interestOptions'].includes(k)),'Unknown question field');
  check(Array.isArray(q.selected)&&q.selected.length<=4&&new Set(q.selected).size===q.selected.length&&q.selected.every(k=>['role','time','experience','interest'].includes(k)),'Invalid selected questions');
  for(const key of ['role','time','interest']){
    check(uniqueStrings(q[key+'Options']),'Invalid options');
    check(!q.selected.includes(key)||q[key+'Options'].length>0,'Selected question needs options');
  }
  return {selected:[...q.selected],roleOptions:[...q.roleOptions],timeOptions:[...q.timeOptions],interestOptions:[...q.interestOptions]};
}
function matching(s,q){
  check(plain(s),'Matching settings required');
  check(Object.keys(s).every(k=>['teamCount','teamCapacities','method','priority','requireCommonTime','fixed','requiredRoles'].includes(k)),'Unknown matching field');
  check(Number.isInteger(s.teamCount)&&s.teamCount>0&&s.teamCount<=100,'Invalid team count');
  check(Array.isArray(s.teamCapacities)&&s.teamCapacities.length===s.teamCount&&s.teamCapacities.every(v=>v===null||(Number.isInteger(v)&&v>0&&v<=10000)),'Invalid capacities');
  check(['balanced','similar'].includes(s.method),'Invalid method');
  const expected=[...q.selected,'size'];
  check(Array.isArray(s.priority)&&s.priority.length===expected.length&&new Set(s.priority).size===expected.length&&s.priority.every(k=>expected.includes(k)),'Priority must match selected questions plus size');
  check(typeof s.requireCommonTime==='boolean'&&(!s.requireCommonTime||q.selected.includes('time')),'Common-time requires time question');
  check((s.fixed===undefined||(Array.isArray(s.fixed)&&s.fixed.length===0))&&(s.requiredRoles===undefined||(Array.isArray(s.requiredRoles)&&s.requiredRoles.length===0)),'Hard constraints require stage 3');
  return {teamCount:s.teamCount,teamCapacities:[...s.teamCapacities],method:s.method,priority:[...s.priority],requireCommonTime:s.requireCommonTime};
}
function mainActivity(d){
  check(plain(d),'Activity required');
  const q=questions(d.questions),m=matching(d.matchingSettings,q);
  const deadline=typeof d.deadline==='string'?Date.parse(d.deadline):d.deadline;
  check(Number.isSafeInteger(deadline)&&deadline>Date.now(),'Future deadline required');
  check(Number.isInteger(d.recruitmentCapacity)&&d.recruitmentCapacity>0&&d.recruitmentCapacity<=100,'Invalid recruitment capacity');
  check(typeof d.description==='string'&&d.description.length<=5000,'Invalid description');
  check(typeof d.goal==='string'&&d.goal.length<=2000,'Invalid goal');
  return {title:text(d.title),description:d.description,goal:d.goal,recruitmentCapacity:d.recruitmentCapacity,deadline,questions:q,matchingSettings:m};
}
function mainAnswers(input,q){
  check(plain(input),'Answers required');
  check(Object.keys(input).length===q.selected.length&&Object.keys(input).every(k=>q.selected.includes(k)),'Only selected questions are accepted');
  const result={};
  for(const key of q.selected){
    const v=input[key];
    if(key==='experience')check(Number.isInteger(v)&&v>=1&&v<=5,'Experience must be 1-5');
    else if(key==='role')check(typeof v==='string'&&q.roleOptions.includes(v),'Invalid role');
    else check(Array.isArray(v)&&v.length>0&&new Set(v).size===v.length&&v.every(x=>q[key+'Options'].includes(x)),'Invalid selected options');
    result[key]=Array.isArray(v)?[...v]:v;
  }
  return result;
}
function canAddPreference(targets,target){check(targets.includes(target)||targets.length<2,'At most two group preferences');}
module.exports={ValidationError,check,text,id,questions,matching,mainActivity,mainAnswers,canAddPreference};
