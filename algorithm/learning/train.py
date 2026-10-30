"""Stage 7: train, validate and register correction factors (편성학습_v4 8·10장).

  train(rows, seed)       pure: rows -> result {status, alpha, coefficients, b, validation, ...}
  run_training(db, ...)   reads trainingDatasets/fx1/rows, records trainingRuns/{id};
                          a passing result becomes modelVersions/{id} with status 'candidate'.
Approval and activation are done by a service admin (functions/src/models.js), never here.

Run as a job:  python -m learning.train          (trains only when due, see should_train)
               python -m learning.train --force
"""
from datetime import datetime, timezone
import hashlib
import json
import math
import time

import numpy as np
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupKFold
from sklearn.preprocessing import StandardScaler

TRAINER_VERSION = 'tr1'
CRITERIA = ['time', 'role', 'experience', 'interest', 'size']
ALPHAS = [0.1, 1, 10, 100]
FOLDS, BOOTSTRAPS, INTERVAL = 5, 200, (10, 90)
MIN_ROWS, MIN_ACTIVITIES, NEW_ROWS_TRIGGER = 30, 5, 10
B_RANGE, IMPROVEMENT = (0.5, 2.0), 0.05
MODES, TYPES = ['balanced', 'similar'], ['study', 'project', 'social', 'other']
AUX_SCORES = ['y_schedule', 'y_roles', 'y_rejoin']


def features(rows):
    """Feature matrix (8장 1번). Column order is part of the model and recorded with it."""
    names = [f'loss_{q}' for q in CRITERIA] + [f'active_{q}' for q in CRITERIA if q != 'size'] + ['teamSize'] \
        + [f'mode_{m}' for m in MODES] + [f'type_{t}' for t in TYPES]
    X = [[r[f'loss_{q}'] for q in CRITERIA] + [r[f'active_{q}'] for q in CRITERIA if q != 'size'] + [r['teamSize']]
         + [int(r.get('formationMode') == m) for m in MODES] + [int(r.get('activityType') == t) for t in TYPES]
         for r in rows]
    return np.array(X, dtype=float), names


def weighted_rmse(y, pred, w):
    return float(math.sqrt(np.sum(w * (y - pred) ** 2) / np.sum(w)))


def fit(X, y, w, alpha):
    scaler = StandardScaler().fit(X)
    model = Ridge(alpha=alpha).fit(scaler.transform(X), y, sample_weight=w)
    return scaler, model


def cv_rmse(X, y, w, groups, make):
    """Grouped K-fold (group = activity), pooled weighted RMSE. make(Xtr, ytr, wtr) -> predict(Xte)."""
    pred = np.zeros_like(y)
    for tr, te in GroupKFold(n_splits=min(FOLDS, len(set(groups)))).split(X, y, groups):
        pred[te] = make(X[tr], y[tr], w[tr])(X[te])
    return weighted_rmse(y, pred, w)


def ridge_maker(alpha):
    def make(Xtr, ytr, wtr):
        scaler, model = fit(Xtr, ytr, wtr, alpha)
        return lambda Xte: model.predict(scaler.transform(Xte))
    return make


def mean_maker(Xtr, ytr, wtr):
    m = float(np.average(ytr, weights=wtr))
    return lambda Xte: np.full(len(Xte), m)


def corrections(beta, uncertain, n_rows):
    """8장 4·6번: s_q = max(0, -beta_q); raw = s / mean(s); b = clip(1 + lambda (raw - 1)); uncertain -> 1."""
    s = {q: max(0.0, -beta[q]) for q in CRITERIA}
    mean = sum(s.values()) / len(CRITERIA)
    lam = min(1.0, n_rows / 100)
    b = {}
    for q in CRITERIA:
        if mean == 0 or q in uncertain:
            b[q] = 1.0
        else:
            b[q] = round(min(B_RANGE[1], max(B_RANGE[0], 1 + lam * (s[q] / mean - 1))), 4)
    return b, s, lam


def train(rows, seed=0):
    rows = sorted(rows, key=lambda r: (r['activityId'], r['teamVersion'], r['teamId']))
    activities = sorted({r['activityId'] for r in rows})
    base = {'trainerVersion': TRAINER_VERSION, 'rowCount': len(rows), 'activityCount': len(activities),
            'datasetHash': hashlib.sha256(json.dumps(rows, sort_keys=True, default=str).encode()).hexdigest()}
    if len(rows) < MIN_ROWS or len(activities) < MIN_ACTIVITIES:
        return {**base, 'status': 'insufficient_data',
                'reason': f'need >= {MIN_ROWS} rows and >= {MIN_ACTIVITIES} activities'}
    X, names = features(rows)
    y = np.array([r['y_overall'] for r in rows], dtype=float)
    w = np.array([r['n_reviews'] for r in rows], dtype=float)
    groups = np.array([r['activityId'] for r in rows])
    alpha = min(ALPHAS, key=lambda a: (cv_rmse(X, y, w, groups, ridge_maker(a)), a))
    scaler, model = fit(X, y, w, alpha)
    coef = dict(zip(names, (float(c) for c in model.coef_)))
    beta = {q: coef[f'loss_{q}'] for q in CRITERIA}

    rng = np.random.default_rng(seed)
    draws = {q: [] for q in CRITERIA}
    index = {a: np.where(groups == a)[0] for a in activities}
    for _ in range(BOOTSTRAPS):
        pick = np.concatenate([index[a] for a in rng.choice(activities, size=len(activities), replace=True)])
        _, m = fit(X[pick], y[pick], w[pick], alpha)
        for q in CRITERIA:
            draws[q].append(float(m.coef_[names.index(f'loss_{q}')]))
    interval = {q: [float(np.percentile(draws[q], INTERVAL[0])), float(np.percentile(draws[q], INTERVAL[1]))] for q in CRITERIA}
    uncertain = {q for q, (lo, hi) in interval.items() if lo <= 0 <= hi}
    b, s, lam = corrections(beta, uncertain, len(rows))

    # 10장 validation: baseline 1 = mean, baseline 2 = v3 default weighted loss only.
    Xw = np.array([[sum(r[f'weight_{q}'] * r[f'loss_{q}'] for q in CRITERIA)] for r in rows])
    rmse = {'model': cv_rmse(X, y, w, groups, ridge_maker(alpha)), 'baseline_mean': cv_rmse(X, y, w, groups, mean_maker),
            'baseline_weighted_loss': cv_rmse(Xw, y, w, groups, ridge_maker(alpha))}
    candidate = rmse['model'] <= (1 - IMPROVEMENT) * rmse['baseline_mean'] and \
        rmse['model'] <= (1 - IMPROVEMENT) * rmse['baseline_weighted_loss']

    aux = {}
    for target in AUX_SCORES:
        sub = [i for i, r in enumerate(rows) if r.get(target) is not None]
        if len(sub) < MIN_ROWS or len({rows[i]['activityId'] for i in sub}) < MIN_ACTIVITIES:
            aux[target] = {'status': 'insufficient_data', 'rows': len(sub)}
            continue
        ya = np.array([rows[i][target] for i in sub], dtype=float)
        _, m = fit(X[sub], ya, w[sub], alpha)
        aux[target] = {'status': 'ok', 'rows': len(sub), 'rmse': cv_rmse(X[sub], ya, w[sub], groups[sub], ridge_maker(alpha)),
                       'lossCoefficients': {q: float(m.coef_[names.index(f'loss_{q}')]) for q in CRITERIA}}
    return {**base, 'status': 'candidate' if candidate else 'not_better_than_baselines', 'alpha': alpha,
            'featureNames': names, 'coefficients': coef, 'intercept': float(model.intercept_),
            'scaler': {'mean': scaler.mean_.tolist(), 'scale': scaler.scale_.tolist()},
            'b': b, 'importance': s, 'shrinkage': lam, 'bootstrapInterval': interval, 'uncertain': sorted(uncertain),
            'validation': {'rmse': rmse, 'improvementRequired': IMPROVEMENT, 'auxiliary': aux}, 'seed': seed}


RECHECK_ACTIVITIES, RECHECK_LIMIT, RECHECK_SECONDS = 3, 5, 30
VALID = ('OPTIMAL', 'FEASIBLE')


def reformation_check(db, b):
    """10장 추가 확인: re-form the latest rosters of the 3 most recent activities with b applied.

    Uses the server-only snapshot of each activity's latest valid run as a fresh first formation
    (published/draft/locks dropped). The report keeps statuses, team sizes and seconds only.
    """
    from formation import solve
    seen, checks = set(), []
    for run in db.collection('formationRuns').order_by('createdAt', direction='DESCENDING').limit(200).stream():
        r = run.to_dict()
        if r.get('status') not in VALID or r.get('activityId') in seen:
            continue
        snap = db.document(f'serverRuns/{run.id}').get()
        if not snap.exists:
            continue
        seen.add(r['activityId'])
        raw = {k: v for k, v in snap.to_dict()['snapshot'].items() if k not in ('published', 'draft', 'locks', 'scopeTeamIds')}
        raw.update(weightFactors=b, limit=RECHECK_LIMIT)
        start = time.monotonic()
        result = solve(raw)
        seconds = round(time.monotonic() - start, 2)
        ok = result['status'] in VALID and result.get('requiredStatus', {}).get('valid') is True and seconds <= RECHECK_SECONDS
        checks.append({'activityId': r['activityId'], 'status': result['status'], 'requiredValid': result.get('requiredStatus', {}).get('valid'),
                       'seconds': seconds, 'teamSizes': sorted(t['size'] for t in result.get('publicSummary', {}).values()), 'passed': ok})
        if len(checks) == RECHECK_ACTIVITIES:
            break
    return {'status': 'no_recent_runs' if not checks else 'passed' if all(c['passed'] for c in checks) else 'failed', 'activities': checks}


def should_train(rows_now, last_run, now):
    """8장: monthly, or >= 10 new rows since the last training run."""
    if last_run is None:
        return True
    last = last_run['trainedAt']
    return rows_now - last_run['rowCount'] >= NEW_ROWS_TRIGGER or (now.year, now.month) != (last.year, last.month)


def run_training(db, dataset='fx1', now=None, force=False, seed=0):
    now = now or datetime.now(timezone.utc)
    rows = [d.to_dict() for d in db.collection(f'trainingDatasets/{dataset}/rows').stream()]
    runs = db.collection('trainingRuns').order_by('trainedAt', direction='DESCENDING').limit(1).stream()
    last = next((r.to_dict() for r in runs), None)
    if not force and not should_train(len(rows), last, now):
        return {'status': 'not_due'}
    result = train([{k: v for k, v in r.items() if k != 'extractedAt'} for r in rows], seed=seed)
    if result['status'] == 'candidate':
        result['validation']['reformationCheck'] = check = reformation_check(db, result['b'])
        if check['status'] == 'failed':
            result['status'] = 'failed_reformation_check'
    run_id = f"{now.strftime('%Y%m%dT%H%M%S')}_{result['datasetHash'][:8]}"
    db.document(f'trainingRuns/{run_id}').set({**{k: result[k] for k in ('status', 'rowCount', 'activityCount', 'datasetHash', 'trainerVersion')},
                                                'trainedAt': now, 'datasetId': dataset, 'modelId': run_id if result['status'] == 'candidate' else None})
    if result['status'] == 'candidate':
        db.document(f'modelVersions/{run_id}').set({**result, 'datasetId': dataset, 'trainedAt': now, 'status': 'candidate',
                                                    'extractorVersion': 'fx1',
                                                    'approvedBy': None, 'approvedAt': None, 'fileUri': None})
    return {'status': result['status'], 'runId': run_id}


def main(argv=None):
    import argparse
    from google.cloud import firestore
    p = argparse.ArgumentParser(description='Stage 7 training')
    p.add_argument('--force', action='store_true')
    args = p.parse_args(argv)
    print(run_training(firestore.Client(), force=args.force))


if __name__ == '__main__':
    main()
