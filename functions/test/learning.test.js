// Stage 4-5 pure logic: membership ratio, officer summary, name masking, tag validation, retry.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const A=require('../src/activity');
const T=require('../src/tagging');

const H=3600000;
const pub=(version,from,to,teams)=>({version,validFrom:from,validTo:to,teams:Object.entries(teams).map(([teamId,uids])=>({teamId,members:uids.map(uid=>({uid}))}))});

test('membershipRatio: time in the ending team over the activity period, across republishes',()=>{
  // activity 0h..10h; v1 valid -5h..6h, v2 6h..now. u moves team_1 -> team_2 at 6h, w stays in team_1.
  const pubs=[pub(1,new Date(-5*H),new Date(6*H),{team_1:['u','w'],team_2:['x']}),pub(2,new Date(6*H),null,{team_1:['w'],team_2:['u','x']})];
  assert.equal(A.membershipRatio(pubs,'u','team_2',new Date(0),new Date(10*H)),0.4);
  assert.equal(A.membershipRatio(pubs,'w','team_1',new Date(0),new Date(10*H)),1);
  assert.equal(A.membershipRatio(pubs,'u','team_2',new Date(5),new Date(5)),1);
});

const fb=(teamId,overall,tags)=>({teamId,scores:{overall,schedule:3,roles:4,rejoin:5},commentTags:tags?{status:'ok',tags}:null});
test('summary: only teams with 3+ respondents, averages and tag counts, no individual rows',()=>{
  const s=A.summarize([fb('t1',5,[{tag:'schedule',sentiment:'neg'}]),fb('t1',4,[{tag:'schedule',sentiment:'neg'},{tag:'roles',sentiment:'pos'}]),fb('t1',3),
    fb('t2',1),fb('t2',2)]);
  assert.deepEqual(Object.keys(s.teams),['t1']);
  assert.equal(s.teams.t1.respondents,3);assert.equal(s.teams.t1.averages.overall,4);
  assert.deepEqual(s.teams.t1.tags,{schedule:{pos:0,neg:2,neutral:0},roles:{pos:1,neg:0,neutral:0}});
  assert.ok(!JSON.stringify(s).includes('userId'));
});

test('maskNames: participants become [팀원], longest first, case-insensitive; one-letter names kept',()=>{
  assert.equal(T.maskNames('김민수님이랑 민수, MINJI가 늦었어요. 수요일',['김민수','민수','Minji','수']),'[팀원]님이랑 [팀원], [팀원]가 늦었어요. 수요일');
});

test('validTags: unknown tags/sentiments dropped, duplicates merged, wrong shape -> null',()=>{
  assert.deepEqual(T.validTags({tags:[{tag:'schedule',sentiment:'neg'},{tag:'schedule',sentiment:'neg'},{tag:'mbti',sentiment:'pos'},{tag:'roles',sentiment:'angry'}]}),
    [{tag:'schedule',sentiment:'neg'}]);
  assert.equal(T.validTags({tags:'schedule'}),null);
  assert.equal(T.validTags(null),null);
});

test('classify: temperature 0, retries once on bad format, then records failure without text',async()=>{
  const calls=[];
  const flaky={async classify(req){calls.push(req);return calls.length===1?{tags:'bad'}:{tags:[{tag:'roles',sentiment:'pos'}],model:'m',modelVersion:'1'};}};
  const ok=await T.classify(flaky,'역할 분담이 좋았어요');
  assert.deepEqual(ok,{version:'ctag1',status:'ok',tags:[{tag:'roles',sentiment:'pos'}],model:'m',modelVersion:'1'});
  assert.ok(calls.every(c=>c.temperature===0&&c.tags.length===9&&c.instructions.includes('개인에 대한 평가')));
  const broken={async classify(){throw new Error('provider down: 역할 분담이 좋았어요');}};
  const failed=await T.classify(broken,'역할 분담이 좋았어요');
  assert.deepEqual(failed,{version:'ctag1',status:'failed'});
});
