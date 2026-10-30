'use strict';
// Helpers shared by stage 1-2 (commands.js) and stage 4-5 (activity.js) commands.
const {FieldValue}=require('firebase-admin/firestore');
const V=require('./validation');

class CommandError extends Error{constructor(code,message){super(message);this.code=code;}}
const fail=(code,message)=>{throw new CommandError(code,message);};
const now=()=>FieldValue.serverTimestamp();

async function membership(tx,db,g,uid){
  const s=await tx.get(db.doc(`memberships/${V.id(g)}_${V.id(uid)}`));
  return s.exists&&s.data().groupId===g&&s.data().userId===uid?{ref:s.ref,data:s.data()}:{ref:s.ref,data:null};
}
async function requireMember(tx,db,g,uid,admin=false){
  const m=await membership(tx,db,g,uid);
  if(!m.data||m.data.status!=='approved')fail('permission-denied','모임 회원만 할 수 있어요');
  if(admin&&m.data.role!=='admin')fail('permission-denied','임원진만 할 수 있어요');
  return m;
}
async function profile(tx,db,uid){
  const s=await tx.get(db.doc(`users/${uid}`));
  if(!s.exists)fail('failed-precondition','프로필을 먼저 만들어 주세요');
  return s.data();
}
async function loadActivity(tx,db,a){
  const s=await tx.get(db.doc(`activities/${V.noUnderscore(a)}`));
  if(!s.exists)fail('not-found','소모임을 찾을 수 없어요');
  return {ref:s.ref,data:s.data()};
}
module.exports={CommandError,fail,now,membership,requireMember,profile,loadActivity};
