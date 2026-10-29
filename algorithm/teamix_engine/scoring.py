"""Exact rational score formulas, capped tables, independent assignment verifier."""
from collections import Counter
from fractions import Fraction as F
from itertools import product

TABLE_LIMIT = 100_000


def rounded(v):
    v = F(v)
    return (2*v.numerator + v.denominator) // (2*v.denominator)


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
        raise ValueError("점수표 행 수가 100,000을 초과합니다. 이번 구현은 선형화로 전환하지 않습니다.")
    rows.append(tuple(row))


def tables(s, upper):
    N, K = len(s["people"]), len(s["teams"])
    result = {}
    size = []
    for n in range(1, upper+1):
        add_row(size, (n, size_loss(n, N, K)))
    result["size"] = size
    for q in s["selected"]:
        rows = []
        if q in ("role", "interest"):
            cats = s["categories"][q]
            totals = [sum((p["answers"][q] == c) if q == "role" else
                          (c in p["answers"][q]) for p in s["people"]) for c in cats]
            for n in range(1, upper+1):
                for counts in product(*(range(min(n, t)+1) for t in totals)):
                    if q == "role" and sum(counts) != n:
                        continue
                    if q == "interest" and not n <= sum(counts) <= n*len(cats):
                        continue
                    loss = category_loss(counts, totals, n, N, s["method"], q == "interest")
                    add_row(rows, (n, *counts, loss))
        elif q == "time":
            for n in range(1, upper+1):
                for m in range(n+1):
                    add_row(rows, (n, m, time_loss(n, m)))
        elif s["method"] == "balanced":
            total = sum(p["answers"][q] for p in s["people"])
            for n in range(1, upper+1):
                for v in range(n, 5*n+1):
                    add_row(rows, (n, v, experience_loss(n, v, total, N)))
        else:
            for lo in range(1, 6):
                for hi in range(lo, 6):
                    add_row(rows, (lo, hi, 250*(hi-lo)))
        result[q] = rows
    return result


def verify(s, assignment):
    """No solver variables or tables: recompute hard validity and all scores."""
    if set(assignment) != set(s["ids"]) or any(t not in s["tids"] for t in assignment.values()):
        raise ValueError("미배정, 잘못된 팀 또는 명단 불일치")
    grouped = {t: [p for p in s["people"] if assignment[p["id"]] == t] for t in s["tids"]}
    for t in s["teams"]:
        n = len(grouped[t["id"]])
        if not n or (t.get("capacity") is not None and n > t["capacity"]):
            raise ValueError("빈 팀 또는 정원 초과")
    for f in s["fixed"]:
        if assignment[f["participant"]] != f["team"]:
            raise ValueError("고정 위반")
    for r in s["required"]:
        count = sum(p["answers"]["role"] == r["role"] for p in grouped[r["team"]])
        if count < r["minimum"]:
            raise ValueError("필수 역할 위반")
    N, K = len(s["people"]), len(s["teams"])
    summaries, losses = [], {}
    for t, members in grouped.items():
        n = len(members)
        pscore = {"size": size_loss(n, N, K)}
        summary = {"team_id": t, "participants": [p["id"] for p in members], "size": n}
        for q in s["selected"]:
            values = [p["answers"][q] for p in members]
            if q in ("role", "interest"):
                cats = s["categories"][q]
                counts = [sum((v == c) if q == "role" else (c in v) for v in values) for c in cats]
                totals = [sum((p["answers"][q] == c) if q == "role" else
                              (c in p["answers"][q]) for p in s["people"]) for c in cats]
                pscore[q] = category_loss(counts, totals, n, N, s["method"], q == "interest")
                summary["role_preferences" if q == "role" else "interests"] = dict(zip(cats, counts))
            elif q == "time":
                counts = {c: sum(c in v for v in values) for c in s["categories"][q]}
                common = [c for c, v in counts.items() if v == n]
                if s["common"] and not common:
                    raise ValueError("전원 공통 시간 위반")
                pscore[q] = time_loss(n, max(counts.values()))
                summary["common_times"] = common
                summary["time_availability"] = counts
            else:
                pscore[q] = (experience_loss(n, sum(values), sum(p["answers"][q] for p in s["people"]), N)
                             if s["method"] == "balanced" else 250*(max(values)-min(values)))
                summary["self_reported_experience"] = {"sum": sum(values), "respondents": n,
                                                       "mean": {"numerator": sum(values), "denominator": n}}
        L = sum(s["weights"][q]*v for q, v in pscore.items())
        losses[t] = {"items": pscore, "L_t": L}
        summary["public_losses"] = pscore
        summaries.append(summary)
    A = max(v["L_t"] for v in losses.values())
    B = sum(v["L_t"] for v in losses.values())
    V = sum(assignment[a] == assignment[b] for a, b in s["edges"])
    W = sum(s["weights"].values())
    fi = 3*K*A+2*B
    return {"summaries": summaries, "losses": losses, "F_int": fi,
            "V": V, "P": {"numerator": 1000*V, "denominator": 2*N},
            "J_int": 18*N*fi+5000*K*W*V}
