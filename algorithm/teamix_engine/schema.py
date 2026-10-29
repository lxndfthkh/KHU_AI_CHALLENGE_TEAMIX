"""JSON snapshot normalization and hard-condition preflight (initial formation only)."""
from collections import Counter

ALGORITHM_VERSION = "3-initial-1"
QUESTIONS = ("time", "role", "experience", "interest")

class InputError(ValueError):
    pass


def normalize(raw):
    if raw.get("published_assignment") or raw.get("mode", "initial") != "initial":
        raise InputError("이번 구현은 공개 전 처음 편성만 지원합니다.")
    people = sorted(raw.get("participants", []), key=lambda p: p["id"])
    teams = sorted(raw.get("teams", []), key=lambda t: t["id"])
    if not people or not teams:
        raise InputError("참가자와 팀은 각각 1개 이상 필요합니다.")
    ids = [p["id"] for p in people]
    tids = [t["id"] for t in teams]
    if any(not isinstance(i, str) or not i for i in ids + tids):
        raise InputError("ID는 비어 있지 않은 문자열이어야 합니다.")
    if len(set(ids)) != len(ids) or len(set(tids)) != len(tids):
        raise InputError("중복 ID가 있습니다.")
    selected = raw.get("selected_questions", list(QUESTIONS))
    if len(set(selected)) != len(selected) or set(selected) - set(QUESTIONS):
        raise InputError("선택 질문이 올바르지 않습니다.")
    priority = raw.get("priority", selected + ["size"])
    if len(priority) != len(set(priority)) or set(priority) != set(selected) | {"size"}:
        raise InputError("우선순위에는 선택 질문과 size가 각각 한 번씩 필요합니다.")
    method = raw.get("method", "balanced")
    if method not in ("balanced", "similar"):
        raise InputError("method는 balanced 또는 similar입니다.")
    categories = raw.get("categories", {})
    for q in selected:
        if q != "experience":
            values = categories.get(q, [])
            if not values or len(values) != len(set(values)):
                raise InputError(f"{q} 선택지가 없거나 중복되었습니다.")
    for p in people:
        a = p.get("answers", {})
        for q in selected:
            v = a.get(q)
            if q == "experience":
                valid = type(v) is int and 1 <= v <= 5
            elif q == "role":
                valid = isinstance(v, str) and v in categories[q]
            else:
                valid = (isinstance(v, list) and bool(v) and
                         all(isinstance(x, str) for x in v) and
                         len(v) == len(set(v)) and set(v) <= set(categories[q]))
            if not valid:
                raise InputError(f"{p['id']}: {q} 응답 누락 또는 잘못된 응답. 응답 요청/질문 전체 제외/참가자 제외가 필요합니다.")
    for t in teams:
        c = t.get("capacity")
        if c is not None and (type(c) is not int or c < 1):
            raise InputError("정원은 양의 정수 또는 null이어야 합니다.")
    fixed = raw.get("fixed", [])
    for f in fixed:
        if f["participant"] not in ids or f["team"] not in tids:
            raise InputError("고정 배치에 없는 참가자 또는 팀이 있습니다.")
    required = raw.get("required_roles", [])
    for r in required:
        if ("role" not in selected or r["team"] not in tids or
                r["role"] not in categories["role"] or
                type(r["minimum"]) is not int or r["minimum"] < 1):
            raise InputError("필수 역할 설정이 올바르지 않습니다.")
    common = raw.get("require_common_time", False)
    if type(common) is not bool or (common and "time" not in selected):
        raise InputError("전원 공통 시간 조건에는 가능 시간 질문이 필요합니다.")
    edges, outgoing = set(), {}
    for e in raw.get("private_preferences", []):
        if not e.get("confirmed", False) or e.get("withdrawn", False):
            continue
        a, b = e["source"], e["target"]
        # Only active relations between current participants affect this run.
        if a not in ids or b not in ids:
            continue
        if a == b:
            raise InputError("비공개 선호 입력이 올바르지 않습니다.")
        outgoing.setdefault(a, set()).add(b)
        if len(outgoing[a]) > 2:
            raise InputError("비공개 선호 입력이 올바르지 않습니다.")
        edges.add(tuple(sorted((a, b))))
    settings = raw.get("solver", {})
    limit = settings.get("max_deterministic_time", 10)
    seed = settings.get("seed", 42)
    if isinstance(limit, bool) or not isinstance(limit, (int, float)) or not 0 < limit <= 10000:
        raise InputError("탐색 한도가 올바르지 않습니다.")
    if type(seed) is not int or not 0 <= seed <= 2147483647:
        raise InputError("시드가 올바르지 않습니다.")
    return dict(people=people, teams=teams, ids=ids, tids=tids, selected=selected,
                priority=priority, weights={q: len(priority)-i for i, q in enumerate(priority)},
                categories=categories, method=method, fixed=fixed, required=required,
                common=common, edges=sorted(edges), limit=limit, seed=seed,
                versions=raw.get("versions", {}))


def preflight(s):
    errors = []
    n, k = len(s["people"]), len(s["teams"])
    if n < k:
        errors.append(f"참가자는 {n}명인데 팀은 {k}개입니다. 팀 수를 줄여 주세요.")
    caps = [t.get("capacity") for t in s["teams"]]
    if all(c is not None for c in caps) and sum(caps) < n:
        errors.append(f"참가자는 {n}명인데 전체 최대 정원은 {sum(caps)}명입니다.")
    assigned = {}
    counts = Counter()
    for f in s["fixed"]:
        i, t = f["participant"], f["team"]
        if i in assigned and assigned[i] != t:
            errors.append(f"{i}가 두 팀에 고정되어 있습니다.")
        if i not in assigned:
            counts[t] += 1
        assigned[i] = t
    for t in s["teams"]:
        if t.get("capacity") is not None and counts[t["id"]] > t["capacity"]:
            errors.append(f"{t['id']}은 최대 {t['capacity']}명인데 {counts[t['id']]}명이 고정되어 있습니다.")
    available = Counter(p.get("answers", {}).get("role") for p in s["people"])
    needs = Counter()
    for r in s["required"]:
        # Duplicate requirements on one team mean their maximum, not their sum.
        key = (r["team"], r["role"])
        needs[key] = max(needs[key], r["minimum"])
    demand = Counter()
    for (_, role), v in needs.items():
        demand[role] += v
    for role, v in demand.items():
        if available[role] < v:
            errors.append(f"{role} 역할 희망자는 {available[role]}명인데 팀별 필수 조건은 총 {v}명을 요구합니다.")
    return errors
