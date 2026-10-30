// Stage 4 pure logic: membership ratio and the officer summary.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const A=require('../src/activity');

const H=3600000;
const pub=(version,from,to,teams)=>({version,validFrom:from,validTo:to,teams:Object.entries(teams).map(([teamId,uids])=>({teamId,members:uids.map(uid=>({uid}))}))});

test('membershipRatio: time in the ending team over the activity period, across republishes',()=>{
  // activity 0h..10h; v1 valid -5h..6h, v2 6h..now. u moves team_1 -> team_2 at 6h, w stays in team_1.
  const pubs=[pub(1,new Date(-5*H),new Date(6*H),{team_1:['u','w'],team_2:['x']}),pub(2,new Date(6*H),null,{team_1:['w'],team_2:['u','x']})];
  assert.equal(A.membershipRatio(pubs,'u','team_2',new Date(0),new Date(10*H)),0.4);
  assert.equal(A.membershipRatio(pubs,'w','team_1',new Date(0),new Date(10*H)),1);
  assert.equal(A.membershipRatio(pubs,'u','team_2',new Date(5),new Date(5)),1);
});

const fb=(teamId,overall)=>({teamId,userId:`u-${teamId}-${overall}`,scores:{overall,schedule:3,roles:4,rejoin:5}});
test('summary: only teams with 3+ respondents, score averages only, no individual rows',()=>{
  const s=A.summarize([fb('t1',5),fb('t1',4),fb('t1',3),fb('t2',1),fb('t2',2)]);
  assert.deepEqual(Object.keys(s.teams),['t1']);
  assert.deepEqual(s.teams.t1,{respondents:3,averages:{overall:4,schedule:3,roles:4,rejoin:5}});
  assert.equal(s.questionnaireVersion,'r2');
  assert.ok(!JSON.stringify(s).includes('u-t1'));
});
