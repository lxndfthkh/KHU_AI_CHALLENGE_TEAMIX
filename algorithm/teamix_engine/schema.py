"""Snapshot normalization, placement rules and precheck (편성알고리즘 v3 2·3·12장)."""
from collections import Counter
from fractions import Fraction as F

SPEC_VERSION = "편성알고리즘_v3"
ALGORITHM_VERSION = "3.0"
QUESTIONS = ("time", "role", "experience", "interest")
# v3 5장: 기본 순서 가능 시간 → 역할 → 경험 수준 → 관심 분야 → 인원 균형
DEFAULT_PRIORITY = ("time", "role", "experience", "interest", "size")
LABELS = {"time": "가능 시간", "role": "역할", "experience": "경험 수준",
          "interest": "관심 분야", "size": "인원 균형"}
# 편성학습 v3 15장 ✅ 보정 범위
MULTIPLIER_MIN, MULTIPLIER_MAX = F(1, 2), F(2)
MAX_TEAMS = 100


class InputError(ValueError):
    pass


def rounded(v):
    """v3 4장: 소수 첫째 자리에서 반올림, 정확히 절반이면 올림."""
    v = F(v)
    return (2*v.numerator + v.denominator) // (2*v.denominator)


def weights(priority, multipliers):
    """편성학습 v3 9장: w'_q = round(10·w_q·b_q), 순위 유지, 최소 1."""
    m = len(priority)
    out, previous = {}, None
    for r, q in enumerate(priority, start=1):
        w = max(1, rounded(10*(m-r+1)*multipliers.get(q, F(1))))
        if previous is not None:
            w = min(w, previous)
        out[q] = previous = w
    return out


def _answered(q, v):
    if v is None:
        return False
    return not (isinstance(v, list) and not v)


def _valid_answer(q, v, categories):
    if q == "experience":
        return type(v) is int and 1 <= v <= 5
    if q == "role":
        return isinstance(v, str) and v in categories[q]
    # 시간·관심 분야는 복수 선택, 최소 1개 (v3 4장)
    return (isinstance(v, list) and bool(v) and all(isinstance(x, str) for x in v)
            and len(v) == len(set(v)) and set(v) <= set(categories[q]))


def _positive(v, nullable=False):
    return (nullable and v is None) or (type(v) is int and v >= 1)


def apply_setup(setup, teams):
    """편성 설정 ①: 팀 수 · 팀별 최대 인원 · 소모임 총 초대 인원.

    teams가 없으면 team_1 … team_K를 만들고, 있으면 개수를 맞춘다.
    팀별 최대 인원은 정원이 비어 있는 팀에 채우고, 그보다 큰 정원은 허용하지 않는다.
    """
    if not isinstance(setup, dict) or set(setup) - {"team_count", "max_per_team", "total_invites"}:
        raise InputError("편성 설정은 team_count, max_per_team, total_invites만 받습니다.")
    k = setup.get("team_count")
    per_team = setup.get("max_per_team")
    total = setup.get("total_invites")
    if not _positive(k) or k > MAX_TEAMS:
        raise InputError(f"팀 수는 1~{MAX_TEAMS} 사이의 정수여야 합니다.")
    if not _positive(per_team, nullable=True):
        raise InputError("팀별 최대 인원은 1 이상의 정수 또는 null이어야 합니다.")
    if not _positive(total, nullable=True):
        raise InputError("총 초대 인원은 1 이상의 정수 또는 null이어야 합니다.")
    if total is not None and total < k:
        raise InputError(f"총 초대 인원({total}명)이 팀 수({k}개)보다 적으면 빈 팀이 생깁니다.")
    if total is not None and per_team is not None and total > k*per_team:
        raise InputError(f"총 초대 인원({total}명)이 팀 수 × 팀별 최대 인원"
                         f"({k}×{per_team}={k*per_team}명)보다 많습니다.")

    if not teams:
        teams = [{"id": f"team_{i}", "capacity": per_team} for i in range(1, k+1)]
    elif len(teams) != k:
        raise InputError(f"팀 수({k}개)와 팀 목록({len(teams)}개)이 다릅니다.")
    else:
        teams = [dict(t) for t in teams]
        for t in teams:
            c = t.get("capacity")
            if c is None:
                t["capacity"] = per_team
            elif per_team is not None and type(c) is int and c > per_team:
                raise InputError(f"{t['id']}의 정원({c}명)이 팀별 최대 인원({per_team}명)보다 큽니다.")
    return teams, {"team_count": k, "max_per_team": per_team, "total_invites": total}


def normalize(raw):
    """Validate input shape. Missing answers are recorded for precheck, never imputed."""
    mode = raw.get("mode", "initial")
    if mode not in ("initial", "republish"):
        raise InputError("mode는 initial 또는 republish입니다.")
    people = sorted(raw.get("participants", []), key=lambda p: p["id"])
    teams, setup = raw.get("teams", []), None
    if raw.get("setup") is not None:
        teams, setup = apply_setup(raw["setup"], teams)
    teams = sorted(teams, key=lambda t: t["id"])
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
    priority = raw.get("priority",
                       [q for q in DEFAULT_PRIORITY if q in selected or q == "size"])
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

    missing = {q: [] for q in selected}
    for p in people:
        a = p.get("answers", {})
        for q in selected:
            if not _answered(q, a.get(q)):
                missing[q].append(p["id"])
            elif not _valid_answer(q, a[q], categories):
                raise InputError(f"{p['id']}: {q} 응답 형식이 올바르지 않습니다.")

    for t in teams:
        c = t.get("capacity")
        if c is not None and (type(c) is not int or c < 1):
            raise InputError("정원은 양의 정수 또는 null이어야 합니다.")
    capacity = {t["id"]: t.get("capacity") for t in teams}

    required = raw.get("required_roles", [])
    for r in required:
        if ("role" not in selected or r["team"] not in tids or
                r["role"] not in categories["role"] or
                type(r["minimum"]) is not int or r["minimum"] < 1):
            raise InputError("필수 역할 설정이 올바르지 않습니다.")
    common = raw.get("require_common_time", False)
    if type(common) is not bool or (common and "time" not in selected):
        raise InputError("전원 공통 시간 조건에는 가능 시간 질문이 필요합니다.")

    # 공개 배정 (republish only)
    published = raw.get("published")
    if mode == "initial" and published:
        raise InputError("처음 편성에는 공개 배정을 넣지 않습니다.")
    if mode == "republish" and not published:
        raise InputError("공개 후 재편성에는 공개 배정이 필요합니다.")
    pub_teams = list((published or {}).get("team_ids", []))
    deleted = sorted(raw.get("deleted_team_ids", []))
    if mode == "initial" and deleted:
        raise InputError("팀 삭제는 공개 후에만 지정합니다.")
    if set(deleted) - set(pub_teams) or set(deleted) & set(tids):
        raise InputError("삭제할 팀은 공개된 팀 중 이번 팀 목록에 없는 팀이어야 합니다.")
    if mode == "republish" and set(pub_teams) - set(deleted) - set(tids):
        raise InputError("공개된 팀은 유지하거나 삭제할 팀으로 지정해야 합니다.")
    # 탈퇴자: 명단에 없는 배정은 버림 (v3 3장 고정 적용 규칙)
    pub = {}
    for i, t in (published or {}).get("assignments", {}).items():
        if i in ids:
            if t not in pub_teams:
                raise InputError("공개 배정에 없는 팀이 있습니다.")
            pub[i] = t

    draft = raw.get("draft") or {}
    draft_assign = {}
    for i, t in draft.get("assignments", {}).items():
        if i in ids and t is not None:
            if t not in tids and t not in deleted:
                raise InputError("작업 초안에 없는 팀이 있습니다.")
            draft_assign[i] = t

    # 수동 고정: 기존 fixed 목록 + 초안 locks(type=manual). 기본 고정은 범위 규칙으로 처리.
    manual, default_locks = [], {}
    for f in raw.get("fixed", []):
        manual.append((f["participant"], f["team"]))
    for i, lock in draft.get("locks", {}).items():
        if lock.get("type") not in ("manual", "default"):
            raise InputError("고정 종류는 manual 또는 default입니다.")
        if i not in ids:
            continue
        if lock["type"] == "manual":
            manual.append((i, lock["team"]))
        else:
            default_locks[i] = lock["team"]
    for i, t in manual:
        if i not in ids or (t not in tids and t not in deleted):
            raise InputError("고정 배치에 없는 참가자 또는 팀이 있습니다.")
    for i, t in default_locks.items():
        if draft_assign.get(i) != t:
            raise InputError("기본 고정과 작업 초안 배정이 다릅니다.")

    scope = raw.get("scope_team_ids")
    scope = sorted(scope) if scope is not None else list(tids)
    if not scope or set(scope) - set(tids) or len(set(scope)) != len(scope):
        raise InputError("재편성 범위가 올바르지 않습니다.")
    if len(scope) < len(tids) and not draft_assign:
        raise InputError("일부 팀만 재편성하려면 작업 초안이 필요합니다.")

    edges, outgoing = set(), {}
    for e in raw.get("private_preferences", []):
        if not e.get("confirmed", False) or e.get("withdrawn", False):
            continue
        a, b = e["source"], e["target"]
        if a not in ids or b not in ids:
            continue
        if a == b:
            raise InputError("비공개 선호 입력이 올바르지 않습니다.")
        outgoing.setdefault(a, set()).add(b)
        if len(outgoing[a]) > 2:
            raise InputError("비공개 선호 입력이 올바르지 않습니다.")
        edges.add(tuple(sorted((a, b))))

    learning = raw.get("learning") or {}
    multipliers = {}
    for q, b in (learning.get("multipliers") or {}).items():
        if q not in priority or isinstance(b, bool) or not isinstance(b, (int, float, str)):
            raise InputError("학습 보정값이 올바르지 않습니다.")
        b = F(str(b))
        if not MULTIPLIER_MIN <= b <= MULTIPLIER_MAX:
            raise InputError("학습 보정값은 0.5~2.0 범위여야 합니다.")
        multipliers[q] = b

    settings = raw.get("solver", {})
    limit = settings.get("max_deterministic_time", 10)
    seed = settings.get("seed", 42)
    if isinstance(limit, bool) or not isinstance(limit, (int, float)) or not 0 < limit <= 10000:
        raise InputError("탐색 한도가 올바르지 않습니다.")
    if type(seed) is not int or not 0 <= seed <= 2147483647:
        raise InputError("시드가 올바르지 않습니다.")

    s = dict(mode=mode, people=people, teams=teams, ids=ids, tids=tids, capacity=capacity, setup=setup,
             selected=selected, priority=priority,
             weights=weights(priority, multipliers), model_id=learning.get("model_id"),
             categories=categories, method=method, missing=missing,
             required=required, common=common, edges=sorted(edges),
             pub=pub, pub_teams=pub_teams, deleted=deleted, draft_assign=draft_assign,
             manual=manual, scope=scope, limit=limit, seed=seed,
             versions=raw.get("versions", {}))
    s["kind"] = "partial" if len(scope) < len(tids) else mode
    s.update(placement(s))
    return s


def placement(s):
    """v3 3장 고정 적용 규칙 → 참가자별 허용 팀.

    수동 고정은 항상 유지. 범위 밖 팀에 배정된 참가자는 그 팀에 고정.
    범위 안의 기본 고정은 해제. 그 밖(신규·미배정·삭제 팀 소속)은 범위 안 팀에만 배정.
    """
    tids, scope = set(s["tids"]), set(s["scope"])
    fixed, duplicate = {}, []
    for i, t in s["manual"]:
        if t not in tids:
            continue  # 삭제 팀 수동 고정은 precheck에서 충돌로 안내
        if i in fixed and fixed[i][0] != t:
            duplicate.append(i)
        fixed.setdefault(i, (t, "manual"))
    for i in s["ids"]:
        d = s["draft_assign"].get(i)
        if i not in fixed and d in tids and d not in scope:
            fixed[i] = (d, "scope")
    allowed = {i: [fixed[i][0]] if i in fixed else list(s["scope"]) for i in s["ids"]}
    return dict(fixed=fixed, duplicate_fixes=sorted(set(duplicate)), allowed=allowed)


def upper_bounds(s):
    """v3 3-1: 팀 인원의 실제 가능한 최댓값 U_t (점수표 범위)."""
    fixed_count = Counter(t for t, _ in s["fixed"].values())
    # 고정되지 않은 참가자는 모두 범위 안 팀에만 갈 수 있다.
    free = sum(i not in s["fixed"] for i in s["ids"])
    U = {}
    for t in s["tids"]:
        if t not in s["scope"]:
            U[t] = max(1, fixed_count[t])
            continue
        others = sum(1 for o in s["scope"] if o != t and fixed_count[o] == 0)
        u = fixed_count[t] + max(0, free - others)
        if s["capacity"][t] is not None:
            u = min(u, s["capacity"][t])
        U[t] = max(1, u)
    return U


def precheck(s):
    """v3 12-1 사전 검사. [{kind, message}]; 통과하면 빈 목록."""
    issues = []
    add = lambda kind, message: issues.append({"kind": kind, "message": message})
    n, k = len(s["people"]), len(s["teams"])
    caps = s["capacity"]
    if n < k:
        add("team_count", f"참가자는 {n}명인데 팀은 {k}개입니다. 팀 수를 줄여 주세요.")
    total = (s["setup"] or {}).get("total_invites")
    if total is not None and n > total:
        add("invite_total", f"참가자는 {n}명인데 소모임 총 초대 인원은 {total}명입니다.")
    # 3-1: 정원이 없는 팀이 하나라도 있으면 전체 정원 검사를 건너뜀
    if all(c is not None for c in caps.values()) and sum(caps.values()) < n:
        add("capacity_total", f"참가자는 {n}명인데 전체 최대 정원은 {sum(caps.values())}명입니다.")
    fixed_count = Counter(t for t, _ in s["fixed"].values())
    for t in s["tids"]:
        if caps[t] is not None and fixed_count[t] > caps[t]:
            add("capacity_fixed", f"{t}은 최대 {caps[t]}명인데 {fixed_count[t]}명이 고정되어 있습니다.")
    for i in s["duplicate_fixes"]:
        add("duplicate_fix", f"같은 참가자({i})가 두 팀에 고정되어 있습니다.")

    if "role" in s["selected"] and s["required"]:
        available = Counter(p["answers"].get("role") for p in s["people"])
        needs = Counter()
        for r in s["required"]:
            # 같은 팀·역할의 중복 조건은 합이 아니라 최댓값
            key = (r["team"], r["role"])
            needs[key] = max(needs[key], r["minimum"])
        demand = Counter()
        teams_per_role = Counter()
        for (_, role), v in needs.items():
            demand[role] += v
            teams_per_role[role] += 1
        for role, v in demand.items():
            if available[role] < v:
                add("role_shortage", f"{role} 역할 희망자는 {available[role]}명인데 "
                    f"{teams_per_role[role]}팀에 총 {v}명을 요구하고 있습니다.")

    if len(s["scope"]) < k:
        free = sum(i not in s["fixed"] for i in s["ids"])
        scope_caps = [caps[t] for t in s["scope"]]
        # 범위 안에 정원 없는 팀이 있으면 남은 자리 무한 (3-1)
        if all(c is not None for c in scope_caps):
            seats = sum(max(0, caps[t]-fixed_count[t]) for t in s["scope"])
            if free > seats:
                add("scope_capacity", f"선택한 {len(s['scope'])}개 팀의 남은 자리는 {seats}개인데 "
                    f"새로 배정할 참가자는 {free}명입니다.")

    for q, people in s["missing"].items():
        if people:
            add("missing_answers", f"{len(people)}명이 '{LABELS[q]}'에 응답하지 않았습니다.")

    if s["mode"] == "republish":
        manual_on_deleted = Counter(t for i, t in s["manual"] if t in s["deleted"])
        for t, c in sorted(manual_on_deleted.items()):
            add("deleted_team_fixed", f"삭제할 {t}에 {c}명이 수동 고정되어 있습니다.")
        for t in s["tids"]:
            if t not in s["pub_teams"] and t not in s["scope"]:
                add("new_team_out_of_scope", f"새로 만든 {t}이 재편성 범위에 없어 채울 수 없습니다.")
    for t in s["tids"]:
        if t not in s["scope"] and fixed_count[t] == 0 and (
                s["mode"] != "republish" or t in s["pub_teams"]):
            add("empty_out_of_scope", f"{t}은 재편성 범위 밖인데 배정된 참가자가 없습니다. 범위에 포함해 주세요.")
    return issues


def preflight(s):
    """Backward-compatible message list."""
    return [i["message"] for i in precheck(s)]
