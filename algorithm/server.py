"""Authenticated formation API. No arbitrary client-provided snapshots."""
import logging
import firebase_admin
from firebase_admin import auth, firestore
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from formation import Invalid
from service import FormationService, Denied, Missing, Stale
from repository import FirestoreRepository

bearer=HTTPBearer(auto_error=False)

def current_uid(credentials: HTTPAuthorizationCredentials=Depends(bearer)):
    if not credentials or credentials.scheme.lower() != 'bearer':
        raise HTTPException(401,'로그인이 필요합니다')
    try:
        if not firebase_admin._apps: firebase_admin.initialize_app()
        token=auth.verify_id_token(credentials.credentials,check_revoked=True)
        return token['uid']
    except Exception:
        raise HTTPException(401,'유효한 로그인이 필요합니다') from None

def get_service():
    if not firebase_admin._apps: firebase_admin.initialize_app()
    return FormationService(FirestoreRepository(firestore.client()))

def create_app():
    app=FastAPI(title='TEAMIX formation',docs_url=None,redoc_url=None,openapi_url=None)
    def handler(action):
        def endpoint(body:dict,uid=Depends(current_uid),service=Depends(get_service)):
            try: return service.invoke(action,uid,body)
            except Denied: raise HTTPException(403,'권한이 없습니다') from None
            except Missing: raise HTTPException(404,'활동을 찾을 수 없습니다') from None
            except Stale: return {'status':'STALE','applied':False}
            except Invalid as e: raise HTTPException(409,str(e)) from None
            except Exception:
                logging.error('Formation request failed')
                raise HTTPException(500,'처리 중 오류가 발생했습니다') from None
        return endpoint
    for route,action in [('/precheck','precheck'),('/run','run'),('/draft/edit','edit'),('/publish','publish'),('/draft/discard','discard'),('/close','close'),('/settings','settings')]:
        app.post(route)(handler(action))
    @app.post('/solve')
    def retired():
        raise HTTPException(410,'/run을 사용해 주세요. 서버가 입력을 조회합니다')
    @app.get('/health')
    def health(): return {'ok':True}
    return app

app=create_app()
