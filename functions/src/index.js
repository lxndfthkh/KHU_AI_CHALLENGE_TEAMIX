'use strict';
// Stage 1-2, 4, 7 and 9 callables. Names match docs/FIRESTORE.md; logic lives in commands.js, activity.js, models.js, privacy.js.
// Formation commands (closeRecruitment, generateDraft, moveMember, publishTeams) are served by algorithm/server_v3.py.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {onSchedule}=require('firebase-functions/v2/scheduler');
const {logger}=require('firebase-functions');
const V=require('./validation');
const {CommandError}=require('./common');
const C=require('./commands');
const A=require('./activity');
const M=require('./models');
const P=require('./privacy');
const {getAuth}=require('firebase-admin/auth');
initializeApp();
const db=getFirestore();
const region='asia-northeast3';

const callable=fn=>onCall({region},async req=>{
  if(!req.auth)throw new HttpsError('unauthenticated','로그인이 필요해요');
  try{return await fn(db,req.auth.uid,req.data||{},req.auth.token);}
  catch(e){
    if(e instanceof V.ValidationError)throw new HttpsError('invalid-argument',e.message);
    if(e instanceof CommandError)throw new HttpsError(e.code,e.message);
    // Never return raw errors: they may contain other people's IDs or answers.
    logger.error('command failed',{name:e.name});
    throw new HttpsError('internal','처리 중 오류가 발생했어요');
  }
});

// createGroup, invitations, requestJoin and approve/reject run in the app under firestore.rules (main).
for(const name of ['createActivity','submitRegistration','updateRegistration','cancelRegistration',
  'setPlacementPreference','revokePlacementPreference'])exports[name]=callable(C[name]);
for(const name of ['setLearningConsent','startActivity','endActivity','submitFeedback','closeFeedback'])exports[name]=callable(A[name]);
// Service admin only (custom claim admin: true), checked inside each command.
for(const name of ['approveModel','activateModel','deactivateModel'])exports[name]=callable(M[name]);
exports.deleteFeedback=callable(P.deleteFeedback);
exports.leaveGroup=callable(P.leaveGroup);
exports.deleteAccount=callable((db,uid,d)=>P.deleteAccount(db,uid,d,{deleteAuthUser:u=>getAuth().deleteUser(u)}));

exports.closeExpiredFeedback=onSchedule({region,schedule:'every 60 minutes'},async()=>{
  const closed=await A.closeExpiredFeedback(db);
  logger.info('feedback closed',{count:closed.length});
});
