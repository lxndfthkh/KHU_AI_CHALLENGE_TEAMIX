"""Stage 6: training rows from closed feedback (편성학습_v4 6장) on main's schema.

One row = one team of the publication current when the activity ended (activities.endedVersion).
  trainingDatasets/fx1                        {extractorVersion, updatedAt, dirty}
  trainingDatasets/fx1/rows/{a}_v{n}_{team}   features + targets (below)
  trainingDatasets/fx1/activities/{a}         {extractedAt, summaryUpdatedAt, rowIds}  (re-extract marker)
All server-only (default-deny rules). Rows carry no user IDs, answers, private preferences or internal
scores; sourceRefs are SHA-256 hashes of feedback paths (deletion tracking, stage 9). Feedback is scores only.

Run as a job:  python -m learning.extract            (all closed activities that changed)
               python -m learning.extract --activity A
"""
from datetime import datetime, timezone
import hashlib

EXTRACTOR_VERSION = 'fx1'
DATASET = 'fx1'
CRITERIA = ['time', 'role', 'experience', 'interest', 'size']
SCORES = ['overall', 'schedule', 'roles', 'rejoin']
MIN_RATIO, MIN_REVIEWS, MIN_RESPONSE_RATE = 0.5, 2, 0.5


def source_ref(path):
    return hashlib.sha256(path.encode()).hexdigest()


def included(review):
    """Reviews that may be learned from: consented and in the team for at least half the activity."""
    return review.get('learningConsent') is True and (review.get('membershipRatio') or 0) >= MIN_RATIO


def build_rows(activity_id, activity, settings, publication, feedback):
    """Pure: main documents -> {rowId: row}. Rows below the inclusion thresholds are left out."""
    priority = list(settings.get('priority') or [])
    used = set(priority) | {'size'}
    # v3 default weights w = m - r + 1 (편성알고리즘_v3 5장); baseline 2 of 편성학습_v3 10장 needs them.
    default_w = {q: len(priority) - r for r, q in enumerate(priority)}
    method = settings.get('method')
    teams = publication.get('teams', [])
    rows = {}
    for team in teams:
        tid = team['teamId']
        size = len(team.get('members', []))
        reviews = [f for f in feedback if f.get('teamId') == tid and f.get('teamVersion') == publication['version'] and included(f)]
        n = len(reviews)
        if size == 0 or n < MIN_REVIEWS or n / size < MIN_RESPONSE_RATE:
            continue
        losses = team.get('losses') or {}
        row = {'activityType': activity.get('type'), 'formationMode': method, 'teamCount': len(teams), 'teamSize': size}
        for q in CRITERIA:
            row[f'active_{q}'] = int(q in used)
            row[f'loss_{q}'] = losses[q] / 1000 if q in used and losses.get(q) is not None else 0.0
            row[f'weight_{q}'] = default_w.get(q, 0)
        row['commonSlotCount'] = len(team.get('commonTimes') or []) if 'time' in used else 0
        row['manuallyEdited'] = bool(publication.get('manuallyEdited'))
        row['republishCount'] = publication['version'] - 1
        for k in SCORES:
            row[f'y_{k}'] = sum(r['scores'][k] for r in reviews) / n
        row.update(n_reviews=n, response_rate=n / size, activityId=activity_id, teamVersion=publication['version'], teamId=tid,
                   sourceRefs=sorted(source_ref(f"feedback/{activity_id}_{r['userId']}") for r in reviews),
                   extractorVersion=EXTRACTOR_VERSION)
        rows[f"{activity_id}_v{publication['version']}_{tid}"] = row
    return rows


def ready(activity):
    return activity.get('status') == 'ended' and activity.get('feedbackClosedAt') is not None and activity.get('endedVersion')


def extract_activity(db, activity_id):
    """Rebuild the rows of one closed activity (idempotent: stale rows of that activity are removed)."""
    snap = db.document(f'activities/{activity_id}').get()
    if not snap.exists or not ready(snap.to_dict()):
        return {'status': 'not_closed', 'rows': 0}
    activity = snap.to_dict()
    settings = (db.document(f'activities/{activity_id}/settings/matching').get().to_dict()) or {}
    publication = db.document(f"publications/{activity_id}_v{activity['endedVersion']}").get().to_dict()
    feedback = [d.to_dict() for d in db.collection('feedback').where('activityId', '==', activity_id).stream()]
    summary = db.document(f'activities/{activity_id}/feedbackSummary/current').get()
    rows = build_rows(activity_id, activity, settings, publication, feedback)
    base = db.document(f'trainingDatasets/{DATASET}')
    marker = base.collection('activities').document(activity_id)
    old = marker.get().to_dict() or {}
    now = datetime.now(timezone.utc)
    batch = db.batch()
    for rid in set(old.get('rowIds', [])) - set(rows):
        batch.delete(base.collection('rows').document(rid))
    for rid, row in rows.items():
        batch.set(base.collection('rows').document(rid), {**row, 'extractedAt': now})
    batch.set(marker, {'extractedAt': now, 'rowIds': sorted(rows),
                       'summaryUpdatedAt': summary.to_dict().get('updatedAt') if summary.exists else None})
    batch.set(base, {'extractorVersion': EXTRACTOR_VERSION, 'updatedAt': now}, merge=True)
    batch.commit()
    return {'status': 'done', 'rows': len(rows)}


def pending(db):
    """Closed activities never extracted, or whose feedback summary changed since."""
    out = []
    for snap in db.collection('activities').where('status', '==', 'ended').stream():
        a = snap.to_dict()
        if not ready(a):
            continue
        marker = db.document(f'trainingDatasets/{DATASET}/activities/{snap.id}').get()
        summary = db.document(f'activities/{snap.id}/feedbackSummary/current').get()
        updated = summary.to_dict().get('updatedAt') if summary.exists else None
        if not marker.exists or (updated and marker.to_dict().get('summaryUpdatedAt') != updated):
            out.append(snap.id)
    return sorted(out)


def main(argv=None):
    import argparse
    from google.cloud import firestore
    p = argparse.ArgumentParser(description='Stage 6 training row extraction')
    p.add_argument('--activity')
    args = p.parse_args(argv)
    db = firestore.Client()
    ids = [args.activity] if args.activity else pending(db)
    for a in ids:
        result = extract_activity(db, a)
        print(f"{a}: {result['status']} rows={result['rows']}")
    from learning import monitor
    print('monitor:', monitor.run(db)['status'])


if __name__ == '__main__':
    main()
