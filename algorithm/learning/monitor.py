"""Stage 9 monitoring (편성학습_v4 11장).

  learningMonitor/{activityId}   per closed activity: model used (or none), mean overall score, respondents
  learningReports/latest         model vs default comparison once a model has >= REPORT_AFTER activities
Server-only (default deny). Numbers only; no user IDs. Never phrased as "learning raises satisfaction".

Run after extraction:  python -m learning.monitor
"""
from datetime import datetime, timezone

REPORT_AFTER = 10
CAUTION = '모임 수가 적어 결론을 단정하지 않습니다. 상관을 인과로 해석하지 않습니다. 떨어지는 경향이 보이면 되돌리기를 검토합니다.'


def model_of(db, activity_id, activity):
    """Model used by the formation that produced the ending publication; manual edits have no run."""
    pub = db.document(f"publications/{activity_id}_v{activity['endedVersion']}").get().to_dict() or {}
    run_id = pub.get('sourceRunId')
    if not run_id:
        return None, 'manual'
    run = db.document(f'formationRuns/{run_id}').get().to_dict() or {}
    return run.get('modelId'), 'ai'


def record_activity(db, activity_id, now=None):
    snap = db.document(f'activities/{activity_id}').get()
    a = snap.to_dict() if snap.exists else {}
    if a.get('status') != 'ended' or not a.get('feedbackClosedAt') or not a.get('endedVersion'):
        return None
    scores = [f.to_dict()['scores']['overall'] for f in db.collection('feedback').where('activityId', '==', activity_id).stream()]
    model_id, source = model_of(db, activity_id, a)
    row = {'modelId': model_id, 'source': source, 'respondents': len(scores),
           'yOverallMean': sum(scores) / len(scores) if scores else None,
           'feedbackClosedAt': a['feedbackClosedAt'], 'recordedAt': now or datetime.now(timezone.utc)}
    db.document(f'learningMonitor/{activity_id}').set(row)
    return row


def report(rows):
    """Pure: monitor rows -> comparison per model (None = default weights), only when a model has enough activities."""
    groups = {}
    for r in rows:
        if r.get('yOverallMean') is None or r.get('source') != 'ai':
            continue
        groups.setdefault(r.get('modelId') or 'default', []).append(r['yOverallMean'])
    summary = {k: {'activities': len(v), 'meanYOverall': round(sum(v) / len(v), 3)} for k, v in sorted(groups.items())}
    ready = [k for k, v in summary.items() if k != 'default' and v['activities'] >= REPORT_AFTER]
    return {'status': 'ready' if ready and 'default' in summary else 'waiting', 'groups': summary,
            'modelsReady': ready, 'reportAfter': REPORT_AFTER, 'caution': CAUTION}


def run(db, now=None):
    for snap in db.collection('activities').where('status', '==', 'ended').stream():
        record_activity(db, snap.id, now)
    result = report([d.to_dict() for d in db.collection('learningMonitor').stream()])
    db.document('learningReports/latest').set({**result, 'updatedAt': now or datetime.now(timezone.utc)})
    return result


def main():
    from google.cloud import firestore
    print(run(firestore.Client()))


if __name__ == '__main__':
    main()
