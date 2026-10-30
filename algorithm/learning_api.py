"""Service-admin learning trigger for the app (편성학습 stage 6-7 on demand).

  POST /learning/status   active model (or default weights) and the latest training run
  POST /learning/train    extract closed feedback, then train; a passing model is saved as a candidate
Applying a model stays a separate step (functions approveModel/activateModel); until then the
engine keeps every b_q = 1.
"""
from datetime import datetime


class NotAdmin(Exception):
    pass


def require_admin(token):
    if not token or token.get('admin') is not True:
        raise NotAdmin()


def _iso(v):
    return v.isoformat() if isinstance(v, datetime) else v


def summarize(run, model):
    """Pure: trainingRuns + modelVersions docs -> what the learning screen shows."""
    if not run:
        return None
    out = {'runId': run.get('runId'), 'status': run.get('status'), 'rowCount': run.get('rowCount'),
           'activityCount': run.get('activityCount'), 'trainedAt': _iso(run.get('trainedAt')),
           'modelId': run.get('modelId'), 'modelStatus': None, 'rmse': None, 'b': None}
    if model:
        out.update(modelStatus=model.get('status'), rmse=(model.get('validation') or {}).get('rmse'), b=model.get('b'))
    return out


def latest(db):
    runs = list(db.collection('trainingRuns').order_by('trainedAt', direction='DESCENDING').limit(1).stream())
    if not runs:
        return None
    run = {**runs[0].to_dict(), 'runId': runs[0].id}
    model = db.document(f"modelVersions/{run['modelId']}").get() if run.get('modelId') else None
    return summarize(run, model.to_dict() if model and model.exists else None)


def status(db):
    config = db.document('appConfig/learning').get()
    c = config.to_dict() if config.exists else {}
    active = {'modelId': c['activeModelId'], 'b': c.get('b')} if c.get('activeModelId') else None
    return {'active': active, 'latest': latest(db)}


def train_now(db):
    from learning import extract, train
    extracted = [a for a in extract.pending(db) if extract.extract_activity(db, a)['status'] == 'done']
    train.run_training(db, force=True)
    return {**status(db), 'extracted': len(extracted)}
