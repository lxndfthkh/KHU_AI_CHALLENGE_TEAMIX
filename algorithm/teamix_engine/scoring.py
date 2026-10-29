"""Exact rational losses (v3 4장), capped score tables (10-1), independent verifier."""
from fractions import Fraction as F
from itertools import product

from .schema import rounded, LABELS

# v3 16장: 선형화로 바꾸는 표 크기 한도는 미정. 1단계 구현값을 그대로 쓴다.
TABLE_LIMIT = 100_000


class TableTooLarge(ValueError):
    """Raised before the (TABLE_LIMIT+1)-th row; the item is then linearized (3-1)."""


def size_loss(n, N, K):
    if N == K or K == 1:
        return 0
    mean = F(N, K)
    d = max(N-K+1-mean, mean-1)
    return rounded(1000*abs(n-mean)/d)


def category_loss(counts, totals, n, N, method, multi=False):
    if method == "similar":
        return rounded(1000*(1-F(max(counts), n)))
    denominator = sum(counts) if multi else n
    total_denominator = sum(totals) if multi else N
    return rounded(500*sum(abs(F(a, denominator)-F(b, total_denominator))
                           for a, b in zip(counts, totals)))


def experience_loss(n, total, grand_total, N):
    return rounded(250*abs(F(total, n)-F(grand_total, N)))


def time_loss(n, maximum):
    return rounded(1000*(1-F(maximum, n)))


def add_row(rows, row):
    if len(rows) >= TABLE_LIMIT:
        raise TableTooLarge(f"점수표 행 수가 {TABLE_LIMIT:,}을 초과합니다.")
    rows.append(tuple(row))


def picks(p, q, c):
    """Did participant p choose category c for question q."""
    v = p["answers"][q]
    return v == c if q == "role" else c in v


def totals(s, q):
    return [sum(picks(p, q, c) for p in s["people"]) for c in s["categories"][q]]


def _vectors(caps, lo, hi):
    """Integer vectors 0 <= v_j <= caps[j] with lo <= sum <= hi, in lexicographic order."""
    suffix = [0]*(len(caps)+1)
    for j in range(len(caps)-1, -1, -1):
        suffix[j] = suffix[j+1]+caps[j]
    def walk(j, prefix, total):
        if j == len(caps):
            if lo <= total:
                yield tuple(prefix)
            return
        for v in range(caps[j]+1):
            if total+v > hi:
                break
            if total+v+suffix[j+1] < lo:
                continue
            yield from walk(j+1, prefix+[v], total+v)
    yield from walk(0, [], 0)


def item_table(s, q, upper):
    """Rows (args..., loss) covering team sizes 1..upper. Raises TableTooLarge."""
    N, K = len(s["people"]), len(s["teams"])
    rows = []
    if q == "size":
        for n in range(1, upper+1):
            add_row(rows, (n, size_loss(n, N, K)))
    elif q in ("role", "interest"):
        tot = totals(s, q)
        for n in range(1, upper+1):
            caps = [min(n, t) for t in tot]
            # 역할은 단일 선택이라 합 = n, 관심 분야는 n ≤ 합 ≤ n·선택지 수
            hi = n if q == "role" else n*len(caps)
            for counts in _vectors(caps, n, hi):
                loss = category_loss(counts, tot, n, N, s["method"], q == "interest")
                add_row(rows, (n, *counts, loss))
    elif q == "time":
        for n in range(1, upper+1):
            for m in range(n+1):
                add_row(rows, (n, m, time_loss(n, m)))
    elif s["method"] == "balanced":
        G = sum(p["answers"][q] for p in s["people"])
        for n in range(1, upper+1):
            for v in range(n, 5*n+1):
                add_row(rows, (n, v, experience_loss(n, v, G, N)))
    else:
        for lo, hi in product(range(1, 6), repeat=2):
            if lo <= hi:
                add_row(rows, (lo, hi, 250*(hi-lo)))
    return rows


def tables(s, upper):
    return {q: item_table(s, q, upper) for q in ["size"]+s["selected"]}


def team_losses(s, members):
    """Public per-item losses p[t,q] and summary for one non-empty team."""
    N, K = len(s["people"]), len(s["teams"])
    n = len(members)
    losses = {"size": size_loss(n, N, K)}
    summary = {"participants": [p["id"] for p in members], "size": n}
    for q in s["selected"]:
        values = [p["answers"][q] for p in members]
        if q in ("role", "interest"):
            cats = s["categories"][q]
            counts = [sum(picks(p, q, c) for p in members) for c in cats]
            losses[q] = category_loss(counts, totals(s, q), n, N, s["method"], q == "interest")
            # v3 3장 표현 규칙: 역할은 '희망자'
            summary["role_preferences" if q == "role" else "interests"] = dict(zip(cats, counts))
        elif q == "time":
            counts = {c: sum(c in v for v in values) for c in s["categories"][q]}
            summary["common_times"] = [c for c, v in counts.items() if v == n]
            summary["time_availability"] = counts
            losses[q] = time_loss(n, max(counts.values()))
        else:
            G = sum(p["answers"][q] for p in s["people"])
            losses[q] = (experience_loss(n, sum(values), G, N) if s["method"] == "balanced"
                         else 250*(max(values)-min(values)))
            summary["self_reported_experience"] = {
                "sum": sum(values), "respondents": n,
                "mean": {"numerator": sum(values), "denominator": n}}
    summary["public_losses"] = losses
    return losses, summary


def required_violations(s, assignment):
    """v3 필수 조건 위반 (공개 항목만). assignment 값이 None이면 미배정."""
    out = []
    add = lambda kind, message: out.append({"kind": kind, "message": message})
    unassigned = [i for i in s["ids"] if assignment.get(i) is None]
    if unassigned:
        add("unassigned", f"미배정 참가자가 {len(unassigned)}명 있습니다.")
    if set(assignment) - set(s["ids"]):
        add("unknown", "명단에 없는 참가자가 배정되어 있습니다.")
    if any(t is not None and t not in s["tids"] for t in assignment.values()):
        add("unknown_team", "없는 팀에 배정된 참가자가 있습니다.")
    grouped = {t: [p for p in s["people"] if assignment.get(p["id"]) == t] for t in s["tids"]}
    for t in s["tids"]:
        n, cap = len(grouped[t]), s["capacity"][t]
        if n == 0:
            add("empty_team", f"{t}이 비어 있습니다.")
        if cap is not None and n > cap:
            add("over_capacity", f"{t}은 최대 {cap}명인데 {n}명이 배정되어 있습니다.")
    for i, (t, kind) in sorted(s["fixed"].items()):
        if assignment.get(i) is not None and assignment[i] != t:
            add("fix_violated", f"{i}의 {'수동 고정' if kind == 'manual' else '재편성 범위 밖 배정'}이 바뀌었습니다.")
    for r in s["required"]:
        count = sum(p["answers"]["role"] == r["role"] for p in grouped[r["team"]])
        if count < r["minimum"]:
            add("required_role", f"{r['team']}의 {r['role']} 역할 희망자가 {r['minimum']}명보다 적습니다.")
    if s["common"]:
        for t, members in grouped.items():
            if members and not any(all(c in p["answers"]["time"] for p in members)
                                   for c in s["categories"]["time"]):
                add("common_time", f"{t}에 전원 공통 가능 시간이 없습니다.")
    return out


def evaluate(s, assignment):
    """수동 수정(13-1 #10)용 공개 지표 계산기. 비공개 항목은 계산하지 않는다."""
    if any(s["missing"].values()):
        raise ValueError("응답 누락이 있어 공개 지표를 계산할 수 없습니다.")
    summaries = []
    for t in s["tids"]:
        members = [p for p in s["people"] if assignment.get(p["id"]) == t]
        if members:
            _, summary = team_losses(s, members)
            summaries.append({"team_id": t, **summary})
    return {"teams": summaries, "required_violations": required_violations(s, assignment)}


def moves(s, assignment):
    """v3 9장: 팀 ID가 바뀐 사람 수. 신규 첫 배정·탈퇴 제거는 세지 않는다."""
    m_pub = sum(assignment[i] != t for i, t in s["pub"].items())
    m_draft = sum(assignment[i] != t for i, t in s["draft_assign"].items())
    deletion = sum(t in s["deleted"] for t in s["pub"].values())
    return m_pub, m_draft, deletion


def verify(s, assignment):
    """No solver variables or tables: recompute hard validity and every score."""
    if set(assignment) != set(s["ids"]) or any(t not in s["tids"] for t in assignment.values()):
        raise ValueError("미배정, 잘못된 팀 또는 명단 불일치")
    violations = required_violations(s, assignment)
    if violations:
        raise ValueError("필수 조건 위반: " + "; ".join(v["kind"] for v in violations))
    summaries, losses = [], {}
    for t in s["tids"]:
        members = [p for p in s["people"] if assignment[p["id"]] == t]
        items, summary = team_losses(s, members)
        L = sum(s["weights"][q]*v for q, v in items.items())
        losses[t] = {"items": items, "L_t": L}
        summaries.append({"team_id": t, **summary})
    K, N = len(s["teams"]), len(s["people"])
    A = max(v["L_t"] for v in losses.values())
    B = sum(v["L_t"] for v in losses.values())
    V = sum(assignment[a] == assignment[b] for a, b in s["edges"])
    W = sum(s["weights"].values())
    fi = 3*K*A+2*B
    m_pub, m_draft, deletion = moves(s, assignment)
    return {"summaries": summaries, "losses": losses, "F_int": fi, "V": V,
            "P": {"numerator": 1000*V, "denominator": 2*N},
            "J_int": 18*N*fi+5000*K*W*V,
            "M_pub": m_pub, "M_draft": m_draft, "deletion_moves": deletion}


def question_label(q):
    return LABELS[q]
