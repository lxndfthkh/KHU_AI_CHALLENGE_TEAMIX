"""Production authenticated formation API; server.py remains main's demo API."""
import logging
import os
import firebase_admin
from firebase_admin import auth, firestore
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from formation import Invalid
from service import Denied, Missing, Stale
from validated_service import ValidatedFormationService
from repository import FirestoreRepository

bearer=HTTPBearer(auto_error=False)
ROUTES={'/precheck':'precheck','/closeRecruitment':'close','/updateMatchingSettings':'settings',
        '/generateDraft':'run','/moveMember':'edit','/discardDraft':'discard','/publishTeams':'publish'}

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
    return ValidatedFormationService(FirestoreRepository(firestore.client()))

# The Flutter web app calls this API from the browser, so it needs CORS.
# Default: local `flutter run -d chrome` (any port) and Firebase Hosting.
# Override with ALLOWED_ORIGIN_REGEX on Cloud Run if the app moves elsewhere.
ALLOWED_ORIGIN_REGEX=os.environ.get('ALLOWED_ORIGIN_REGEX',
    r'^(http://(localhost|127\.0\.0\.1)(:\d+)?|https://teamix-309c0\.(web\.app|firebaseapp\.com))$')

def create_app():
    app=FastAPI(title='TEAMIX formation',docs_url=None,redoc_url=None,openapi_url=None)
    app.add_middleware(CORSMiddleware,allow_origin_regex=ALLOWED_ORIGIN_REGEX,
                       allow_methods=['POST','GET'],allow_headers=['Authorization','Content-Type'])
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
    # Route names follow main's server command list (docs/FIRESTORE.md).
    for route,action in ROUTES.items():
        app.post(route)(handler(action))
    @app.post('/solve')
    def retired():
        raise HTTPException(410,'/generateDraft를 사용해 주세요. 서버가 입력을 조회합니다')
    @app.get('/health')
    def health(): return {'ok':True}
    return app

app=create_app()
