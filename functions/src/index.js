'use strict';
// Stage 1-2 callables. Names match docs/FIRESTORE.md; logic lives in commands.js.
// Formation commands (closeRecruitment, generateDraft, moveMember, publishTeams) are served by algorithm/server_v3.py.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {logger}=require('firebase-functions');
const V=require('./validation');
const C=require('./commands');
initializeApp();
const db=getFirestore();

const callable=fn=>onCall({region:'asia-northeast3'},async req=>{
  if(!req.auth)throw new HttpsError('unauthenticated','로그인이 필요해요');
  try{return await fn(db,req.auth.uid,req.data||{});}
  catch(e){
    if(e instanceof V.ValidationError)throw new HttpsError('invalid-argument',e.message);
    if(e instanceof C.CommandError)throw new HttpsError(e.code,e.message);
    // Never return raw errors: they may contain other people's IDs or answers.
    logger.error('command failed',{name:e.name});
    throw new HttpsError('internal','처리 중 오류가 발생했어요');
  }
});

for(const name of ['createGroup','issueInvitation','previewInvitation','requestJoin','approveJoin','rejectJoin',
  'createActivity','submitRegistration','updateRegistration','cancelRegistration',
  'setPlacementPreference','revokePlacementPreference'])exports[name]=callable(C[name]);
