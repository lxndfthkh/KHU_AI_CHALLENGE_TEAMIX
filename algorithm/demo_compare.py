"""Demo subgroup for the 학습 관리 before/after comparison (learning_api.compare).

20 applicants named 참가자 01-20, 5 teams of 4, balanced mode, priority time > interest.
With default weights the engine's optimum is exactly 01-04, 05-08, 09-12, 13-16, 17-20
(each team has one person per interest, three share a weekday evening). The learned model
raises time and lowers interest, and the optimum becomes teams that share a weekend slot.
tests/test_demo_compare.py keeps this true if the engine changes.

  python demo_compare.py --write --admin-email admin@teamix.app   (GOOGLE_CLOUD_PROJECT set)
  python demo_compare.py --delete
Every ID starts with mock_compare / mock_demo_u.
"""
from datetime import datetime, timedelta, timezone

GROUP, ACTIVITY = 'mock_compare_demo', 'mock_compare_act'
INTERESTS = [('plan', '기획'), ('dev', '개발'), ('design', '디자인'), ('marketing', '마케팅')]
WEEKDAY = [('mon', '월 저녁'), ('tue', '화 저녁'), ('wed', '수 저녁'), ('thu', '목 저녁'), ('fri', '금 저녁')]
WEEKEND = [('sat_am', '토 오전'), ('sat_pm', '토 오후'), ('sun_am', '일 오전'), ('sun_pm', '일 오후')]
TEAMS = [f't{k}' for k in range(1, 6)]


def number(k, p):
    return 4 * k + p + 1


# Weekend teams: two interests twice each, two people from each of two weekday teams.
WEEKEND_TEAMS = [[number(0, 0), number(0, 1), number(1, 3), number(1, 0)],
                 [number(0, 2), number(0, 3), number(1, 1), number(1, 2)],
                 [number(2, 0), number(2, 1), number(3, 3), number(3, 0)],
                 [number(2, 2), number(2, 3), number(3, 1), number(3, 2)]]


def uid(i):
    return f'mock_demo_u{i:02d}'


def answers():
    """{uid: {'interest': [optionId], 'time': [optionIds]}} in engine terms."""
    out = {}
    for i in range(1, 21):
        k, p = divmod(i - 1, 4)
        slots = [WEEKDAY[k][0]] if k == 4 or p < 3 else []
        slots += [WEEKEND[j][0] for j, team in enumerate(WEEKEND_TEAMS) if i in team]
        out[uid(i)] = {'interest': [INTERESTS[(p + k) % 4][0]], 'time': slots}
    return out


def engine_input(factors=None):
    """The raw formation input the server builds from the seeded documents."""
    return {'participants': [{'id': u, 'answers': a} for u, a in sorted(answers().items())],
            'teams': [{'id': t, 'capacity': 4} for t in TEAMS],
            'selected_questions': ['time', 'interest'], 'priority': ['time', 'interest', 'size'],
            'method': 'balanced', 'categories': {'interest': [o for o, _ in INTERESTS],
                                                 'time': [o for o, _ in WEEKDAY + WEEKEND]},
            'traits': [], 'published': {}, 'draft': {}, 'locks': {}, 'required_roles': [],
            'require_common_time': False, 'seed': 42, 'limit': 10, 'private_preferences': [],
            'weightFactors': factors}


def documents(admin_uid=None, now=None):
    """{path: data} for the demo group, subgroup, questions, settings and registrations."""
    now = now or datetime.now(timezone.utc)
    docs = {f'groups/{GROUP}': {'name': '[데모] 학습 비교 모임', 'description': '학습 전후 편성 비교용 가짜 모임',
                                'categories': ['데모'], 'ownerId': admin_uid or 'mock_owner', 'themeColor': 'mint',
                                'status': 'active', 'mock': True, 'createdAt': now, 'updatedAt': now}}
    members = {uid(i): f'참가자 {i:02d}' for i in range(1, 21)}
    if admin_uid:
        members[admin_uid] = '서비스 관리자'
    for u, name in members.items():
        docs[f'memberships/{GROUP}_{u}'] = {'groupId': GROUP, 'userId': u, 'displayName': name,
                                            'role': 'admin' if u == admin_uid else 'member', 'status': 'approved',
                                            'createdAt': now, 'updatedAt': now}
    a = f'activities/{ACTIVITY}'
    docs[a] = {'groupId': GROUP, 'title': '학습 비교 데모 소모임', 'description': '20명 · 4명씩 5팀',
               'type': 'project', 'createdBy': admin_uid or 'mock_owner', 'themeColor': 'mint', 'capacity': 20,
               'targetTeamSize': 4, 'deadlineAt': now - timedelta(days=1), 'status': 'closed', 'participantCount': 20,
               'questionsLockedAt': now, 'publishedVersion': None, 'mock': True, 'createdAt': now, 'updatedAt': now}
    docs[f'{a}/questions/q_time'] = {'label': '가능한 시간', 'type': 'multiple', 'required': True, 'enabled': True,
                                     'order': 0, 'options': [{'id': o, 'label': l} for o, l in WEEKDAY + WEEKEND]}
    docs[f'{a}/questions/q_interest'] = {'label': '관심 분야', 'type': 'multiple', 'required': True, 'enabled': True,
                                         'order': 1, 'options': [{'id': o, 'label': l} for o, l in INTERESTS]}
    docs[f'{a}/settings/matching'] = {'method': 'balanced', 'enabledQuestionIds': ['q_time', 'q_interest'],
                                      'questionCriteria': {'q_time': 'time', 'q_interest': 'interest'},
                                      'priority': ['time', 'interest', 'size'], 'teamIds': TEAMS,
                                      'teamCapacities': {t: 4 for t in TEAMS}, 'capacityInitialized': True,
                                      'settingsVersion': 1, 'learningEnabled': True, 'updatedAt': now}
    for u, ans in answers().items():
        docs[f'registrations/{ACTIVITY}_{u}'] = {'activityId': ACTIVITY, 'groupId': GROUP, 'userId': u,
                                                 'status': 'submitted',
                                                 'answers': {'q_time': ans['time'], 'q_interest': ans['interest']},
                                                 'createdAt': now, 'updatedAt': now}
    return docs


def main(argv=None):
    import argparse
    from google.cloud import firestore
    p = argparse.ArgumentParser(description='Seed or remove the learning comparison demo')
    p.add_argument('--write', action='store_true')
    p.add_argument('--delete', action='store_true')
    p.add_argument('--admin-email', help='make this account the demo group admin so it can open it in the app')
    args = p.parse_args(argv)
    db = firestore.Client()
    admin_uid = None
    if args.admin_email:
        import firebase_admin
        from firebase_admin import auth
        if not firebase_admin._apps:
            firebase_admin.initialize_app(options={'projectId': db.project})
        admin_uid = auth.get_user_by_email(args.admin_email).uid
    docs = documents(admin_uid)
    if args.delete:
        # Drafts and runs the formation screen may have made for the demo go too.
        paths = list(docs) + [f'drafts/{ACTIVITY}'] + [d.reference.path for d in db.collection(
            'memberships').where('groupId', '==', GROUP).stream()]
    else:
        paths = list(docs)
    batch, n = db.batch(), 0
    for path in paths:
        batch.delete(db.document(path)) if args.delete else batch.set(db.document(path), docs[path])
        n += 1
        if n % 400 == 0:
            batch.commit()
            batch = db.batch()
    batch.commit()
    print(f"{'deleted' if args.delete else 'wrote'} {len(paths)} docs")


if __name__ == '__main__':
    main()
