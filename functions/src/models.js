'use strict';
// Stage 7 model approval (편성학습_v3 10장). Only a service admin (Auth custom claim admin: true) may act.
// modelVersions/{id}.status: candidate -> approved -> active -> retired; exactly one active.
// appConfig/learning {activeModelId, b, activatedAt, activatedBy} is what the engine reads (stage 8).
// Rollback: activate a retired model again, or deactivateModel (activeModelId = null -> default weights).
const {fail,now}=require('./common');
const V=require('./validation');

function requireServiceAdmin(token){if(!token||token.admin!==true)fail('permission-denied','서비스 관리자만 할 수 있어요');}
const CONFIG='appConfig/learning';

async function approveModel(db,uid,d,token){
  requireServiceAdmin(token);
  const ref=db.doc(`modelVersions/${V.id(d.modelId)}`);
  return db.runTransaction(async tx=>{
    const s=await tx.get(ref);
    if(!s.exists)fail('not-found','모델을 찾을 수 없어요');
    if(s.data().status==='approved')return {status:'approved'};
    if(s.data().status!=='candidate')fail('failed-precondition','후보 모델만 승인할 수 있어요');
    tx.update(ref,{status:'approved',approvedBy:uid,approvedAt:now()});
    return {status:'approved'};
  });
}

async function activateModel(db,uid,d,token){
  requireServiceAdmin(token);
  const ref=db.doc(`modelVersions/${V.id(d.modelId)}`);
  return db.runTransaction(async tx=>{
    const [s,config]=await Promise.all([tx.get(ref),tx.get(db.doc(CONFIG))]);
    if(!s.exists)fail('not-found','모델을 찾을 수 없어요');
    if(s.data().status==='active')return {status:'active'};
    if(!['approved','retired'].includes(s.data().status))fail('failed-precondition','승인된 모델만 적용할 수 있어요');
    const previous=config.exists?config.data().activeModelId:null;
    if(previous&&previous!==ref.id)tx.update(db.doc(`modelVersions/${previous}`),{status:'retired',retiredAt:now()});
    tx.update(ref,{status:'active',activatedAt:now()});
    tx.set(db.doc(CONFIG),{activeModelId:ref.id,b:s.data().b,activatedAt:now(),activatedBy:uid});
    return {status:'active',previous};
  });
}

async function deactivateModel(db,uid,d,token){
  requireServiceAdmin(token);
  return db.runTransaction(async tx=>{
    const config=await tx.get(db.doc(CONFIG)),active=config.exists?config.data().activeModelId:null;
    if(active)tx.update(db.doc(`modelVersions/${active}`),{status:'retired',retiredAt:now()});
    tx.set(db.doc(CONFIG),{activeModelId:null,b:null,activatedAt:now(),activatedBy:uid});
    return {activeModelId:null,previous:active};
  });
}

module.exports={approveModel,activateModel,deactivateModel};
