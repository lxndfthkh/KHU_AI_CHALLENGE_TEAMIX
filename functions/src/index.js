'use strict';
// Stage 1-2 and 4-5 callables. Names match docs/FIRESTORE.md; logic lives in commands.js, activity.js, tagging.js.
// Formation commands (closeRecruitment, generateDraft, moveMember, publishTeams) are served by algorithm/server_v3.py.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {onSchedule}=require('firebase-functions/v2/scheduler');
const {onDocumentUpdated}=require('firebase-functions/v2/firestore');
const {logger}=require('firebase-functions');
const V=require('./validation');
const {CommandError}=require('./common');
const C=require('./commands');
const A=require('./activity');
const T=require('./tagging');
initializeApp();
const db=getFirestore();
const region='asia-northeast3';

const callable=fn=>onCall({region},async req=>{
  if(!req.auth)throw new HttpsError('unauthenticated','로그인이 필요해요');
  try{return await fn(db,req.auth.uid,req.data||{});}
  catch(e){
    if(e instanceof V.ValidationError)throw new HttpsError('invalid-argument',e.message);
    if(e instanceof CommandError)throw new HttpsError(e.code,e.message);
    // Never return raw errors: they may contain other people's IDs or answers.
    logger.error('command failed',{name:e.name});
    throw new HttpsError('internal','처리 중 오류가 발생했어요');
  }
});

for(const name of ['createGroup','issueInvitation','previewInvitation','requestJoin','approveJoin','rejectJoin',
  'createActivity','submitRegistration','updateRegistration','cancelRegistration',
  'setPlacementPreference','revokePlacementPreference'])exports[name]=callable(C[name]);
for(const name of ['setLearningConsent','startActivity','endActivity','submitFeedback','closeFeedback'])exports[name]=callable(A[name]);

exports.closeExpiredFeedback=onSchedule({region,schedule:'every 60 minutes'},async()=>{
  const closed=await A.closeExpiredFeedback(db);
  logger.info('feedback closed',{count:closed.length});
});

// Feedback closed (by an officer or the schedule) -> tag comments, then refresh the summary.
exports.tagClosedFeedback=onDocumentUpdated({region,document:'activities/{activityId}'},async event=>{
  const before=event.data.before.data(),after=event.data.after.data();
  if(before.feedbackClosedAt||!after.feedbackClosedAt)return;
  const result=await T.tagActivity(db,event.params.activityId,T.configuredProvider());
  logger.info('feedback tagging',{status:result.status,tagged:result.tagged,failed:result.failed??0});
});
