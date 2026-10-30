const {test}=require('node:test');
const assert=require('node:assert/strict');
const V=require('../src/validation');

const questions=()=>[
  {id:'role',label:'희망 역할',type:'single',options:[{id:'dev',label:'개발'},{id:'design',label:'디자인'}]},
  {id:'time',label:'가능 시간',type:'multiple',options:[{id:'wed',label:'수'},{id:'fri',label:'금'}]},
  {id:'exp',label:'경험',type:'scale'},
  {id:'topic',label:'관심',type:'multiple',options:[{id:'web',label:'웹'}]},
  {id:'mbti',label:'MBTI',type:'single',required:false,options:[{id:'i',label:'I'},{id:'e',label:'E'}]},
];
const input=()=>({title:'Demo',description:'',capacity:20,targetTeamSize:4,deadlineAt:Date.now()+86400000,questions:questions(),
  matching:{method:'balanced',questionCriteria:{role:'role',time:'time',exp:'experience',topic:'interest'},requireCommonTime:true}});
const docs=()=>V.activity(input()).questions;
const answers=()=>({role:'dev',time:['wed'],exp:3,topic:['web']});

test('activity accepted; enabledQuestionIds follow question order, default priority adds size',()=>{
  const v=V.activity(input());
  assert.deepEqual(v.matching.enabledQuestionIds,['role','time','exp','topic']);
  assert.deepEqual(v.matching.priority,['role','time','experience','interest','size']);
  assert.equal(v.questions[4].required,false);
  assert.deepEqual(v.matching.requiredRoles,[]);
});
test('criterion must match question type',()=>{const d=input();d.matching.questionCriteria={time:'role'};assert.throws(()=>V.activity(d),/role needs a single/);});
test('one question per criterion',()=>{const d=input();d.matching.questionCriteria={time:'time',topic:'time'};assert.throws(()=>V.activity(d));});
test('matching question must be required',()=>{const d=input();d.matching.questionCriteria={mbti:'role'};assert.throws(()=>V.activity(d),/required/);});
test('explicit priority must cover mapped criteria plus size',()=>{
  const d=input();d.matching.priority=['size'];assert.throws(()=>V.activity(d));
  d.matching.priority=['size','interest','experience','time','role'];assert.equal(V.activity(d).matching.priority[0],'size');
});
test('common time needs a time criterion',()=>{const d=input();d.matching.questionCriteria={role:'role'};assert.throws(()=>V.activity(d),/Common time/);});
test('duplicate question or option IDs rejected',()=>{
  const d=input();d.questions.push({...d.questions[0]});assert.throws(()=>V.activity(d));
  const e=input();e.questions[0].options.push({id:'dev',label:'x'});assert.throws(()=>V.activity(e));
});
test('past deadline and non-positive sizes rejected',()=>{
  for(const patch of [{deadlineAt:1},{capacity:0},{targetTeamSize:0}])assert.throws(()=>V.activity({...input(),...patch}));
});
test('answers keyed by question ID accepted; optional may be omitted',()=>{assert.deepEqual(V.answers(answers(),docs()),answers());});
test('required answer missing or unknown key rejected',()=>{
  const a=answers();delete a.exp;assert.throws(()=>V.answers(a,docs()),/Answer required/);
  assert.throws(()=>V.answers({...answers(),zzz:1},docs()),/Unknown question/);
});
test('answer values checked against type and options',()=>{
  assert.throws(()=>V.answers({...answers(),role:'pm'},docs()));
  assert.throws(()=>V.answers({...answers(),exp:6},docs()));
  assert.throws(()=>V.answers({...answers(),time:['wed','wed']},docs()));
  assert.throws(()=>V.answers({...answers(),time:[]},docs()));
});
test('invite code normalized and checked',()=>{
  assert.equal(V.inviteCode(' abcdefghjk '),'ABCDEFGHJK');
  for(const bad of ['ABC','ABCDEFGHJI','ABCDEFGHJ0',42])assert.throws(()=>V.inviteCode(bad));
});
test('IDs: path traversal rejected, underscores rejected where IDs are joined',()=>{
  assert.throws(()=>V.id('../x'));assert.throws(()=>V.noUnderscore('a_b'));assert.equal(V.noUnderscore('abc1'),'abc1');
});
