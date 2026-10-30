"""Service-admin learning trigger for the app (편성학습 stage 6-7 on demand).

  POST /learning/status   active model (or default weights) and the latest training run
  POST /learning/train    extract closed feedback, then train; a passing model is saved as a candidate
  POST /learning/compare  one subgroup formed twice: default weights vs the latest model (not saved)
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


def status(db, body=None):
    config = db.document('appConfig/learning').get()
    c = config.to_dict() if config.exists else {}
    active = {'modelId': c['activeModelId'], 'b': c.get('b')} if c.get('activeModelId') else None
    return {'active': active, 'latest': latest(db), 'targets': targets(db)}


def train_now(db, body=None):
    from learning import extract, train
    extracted = [a for a in extract.pending(db) if extract.extract_activity(db, a)['status'] == 'done']
    train.run_training(db, force=True)
    return {**status(db), 'extracted': len(extracted)}


def targets(db, limit=20):
    """Subgroups whose roster can be formed now (recruitment closed, not yet published first)."""
    out = []
    for snap in db.collection('activities').where('status', '==', 'closed').limit(limit).stream():
        a = snap.to_dict()
        g = db.document(f"groups/{a.get('groupId')}").get()
        out.append({'groupId': a.get('groupId'), 'activityId': snap.id, 'title': a.get('title') or snap.id,
                    'groupName': (g.to_dict() or {}).get('name', '') if g.exists else ''})
    return sorted(out, key=lambda t: (t['groupName'], t['title']))


def teams_of(result, names):
    """Solver result -> [{members: [displayName], commonTimes}] ordered by each team's first member."""
    teams = []
    for t in (result.get('publicSummary') or {}).values():
        if not t.get('members'):
            continue
        ids = sorted(t['members'])
        teams.append({'members': [names.get(i, i) for i in ids], 'memberIds': ids,
                      'commonTimes': t.get('commonTimes', [])})
    return sorted(teams, key=lambda t: t['memberIds'])


def compare(db, body):
    """Form the same roster twice: default weights vs the latest model's correction factors.

    Read-only: nothing is saved as a draft. Uses the latest trained model even before it is
    applied, so the effect can be shown before deciding.
    """
    from formation import solve
    from repository import FirestoreRepository
    from service import snapshot, path_id
    g, a = path_id(body.get('groupId')), path_id(body.get('activityId'))
    s = FirestoreRepository(db).atomic(lambda tx: tx.load(g, a))
    run = latest(db)
    b = (run or {}).get('b') or {}
    raw = snapshot({**s, 'published': {}}, {'kind': 'initial'})
    # A fresh first formation: earlier drafts and locks would pin people in place.
    raw.update(draft={}, locks={}, weightFactors=None)
    keys = set(raw['priority'])
    factors = {q: v for q, v in b.items() if q in keys} or None
    names = {u: m.get('displayName', u) for u, m in s['members'].items()}
    labels = {o['id']: o.get('label', o['id']) for q in db.collection(f'activities/{a}/questions').stream()
              for o in (q.to_dict().get('options') or [])}
    before, after = solve(raw), solve({**raw, 'weightFactors': factors})
    for r in (before, after):
        for t in (r.get('publicSummary') or {}).values():
            t['commonTimes'] = [labels.get(c, c) for c in t.get('commonTimes', [])]
    return {'modelId': (run or {}).get('modelId'), 'b': factors, 'priority': raw['priority'],
            'before': {'status': before.get('status'), 'teams': teams_of(before, names)},
            'after': {'status': after.get('status'), 'teams': teams_of(after, names)}}
