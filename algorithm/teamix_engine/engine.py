"""Initial CP-SAT formation. Public result and sensitive internal record stay separate."""
import copy
import hashlib
import json
import time
import ortools
from ortools.sat.python import cp_model as cp
from .schema import normalize, preflight, InputError, ALGORITHM_VERSION
from .scoring import tables, verify


def hard_model(s, diagnostic=False):
    model = cp.CpModel()
    N, K = len(s["people"]), len(s["teams"])
    x = {(p["id"], t["id"]): model.new_bool_var(f"x_{i}_{j}")
         for i, p in enumerate(s["people"]) for j, t in enumerate(s["teams"])}
    for i in s["ids"]:
        model.add_exactly_one(x[i, t] for t in s["tids"])
    sizes, labels = {}, {}
    def condition(constraint, label):
        if diagnostic:
            a = model.new_bool_var(f"assumption_{len(labels)}")
            constraint.only_enforce_if(a)
            model.add_assumption(a)
            labels[a.index] = label
    for t in s["teams"]:
        tid = t["id"]
        n = model.new_int_var(1, N, f"n_{tid}")
        model.add(n == sum(x[i, tid] for i in s["ids"]))
        sizes[tid] = n
        if t.get("capacity") is not None:
            condition(model.add(n <= t["capacity"]), f"{tid}: 최대 정원 {t['capacity']}명")
    for f in s["fixed"]:
        condition(model.add(x[f["participant"], f["team"]] == 1),
                  f"{f['participant']} → {f['team']}: 고정 배치")
    for r in s["required"]:
        condition(model.add(sum(x[p["id"], r["team"]] for p in s["people"]
                                if p["answers"]["role"] == r["role"]) >= r["minimum"]),
                  f"{r['team']}: {r['role']} 역할 희망자 최소 {r['minimum']}명")
    availability = {}
    if "time" in s["selected"]:
        for t in s["tids"]:
            hs, av = [], []
            for j, slot in enumerate(s["categories"]["time"]):
                a = model.new_int_var(0, N, f"avail_{t}_{j}")
                model.add(a == sum(x[p["id"], t] for p in s["people"] if slot in p["answers"]["time"]))
                av.append(a)
                if s["common"]:
                    h = model.new_bool_var(f"common_{t}_{j}")
                    u = sizes[t]-a
                    model.add(u <= N*(1-h))
                    model.add(u >= 1-h)
                    hs.append(h)
            availability[t] = av
            if s["common"]:
                condition(model.add(sum(hs) >= 1), f"{t}: 전원 공통 가능 시간 최소 1개")
    return model, x, sizes, availability, labels


def configured_solver(s):
    solver = cp.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = s["seed"]
    solver.parameters.max_deterministic_time = s["limit"]
    return solver


def solve(raw):
    start = time.perf_counter()
    raw = copy.deepcopy(raw)
    internal = {"algorithm_version": ALGORITHM_VERSION, "ortools_version": ortools.__version__,
                "input_sha256": hashlib.sha256(json.dumps(raw, sort_keys=True, ensure_ascii=False).encode()).hexdigest()}
    def finish(status, summaries=None, messages=None):
        elapsed = time.perf_counter()-start
        internal["elapsed_seconds"] = elapsed
        public = {"label": "추천 편성안", "status": status, "elapsed_seconds": elapsed,
                  "teams": summaries or [], "messages": messages or []}
        return {"public": public, "internal": internal}
    try:
        s = normalize(raw)
        internal.update(seed=s["seed"], workers=1, max_deterministic_time=s["limit"], versions=s["versions"])
        errors = preflight(s)
        if errors:
            internal["preflight_errors"] = errors
            return finish("INFEASIBLE", messages=errors)
        model, x, sizes, availability, _ = hard_model(s)
        N, K = len(s["people"]), len(s["teams"])
        weighted, scorevars, table_rows = [], {}, {}
        for team in s["teams"]:
            t = team["id"]
            upper = min(team.get("capacity") or N-K+1, N-K+1)
            ts = tables(s, upper)
            table_rows[t] = {q: len(rows) for q, rows in ts.items()}
            scorevars[t] = {}
            for q in ["size"] + s["selected"]:
                loss = model.new_int_var(0, 1000, f"loss_{t}_{q}")
                scorevars[t][q] = loss
                if q == "size":
                    args = [sizes[t]]
                elif q in ("role", "interest"):
                    counts = []
                    for j, c in enumerate(s["categories"][q]):
                        v = model.new_int_var(0, N, f"count_{t}_{q}_{j}")
                        model.add(v == sum(x[p["id"], t] for p in s["people"]
                                           if (p["answers"][q] == c if q == "role" else c in p["answers"][q])))
                        counts.append(v)
                    args = [sizes[t]] + counts
                elif q == "time":
                    v = model.new_int_var(0, N, f"best_time_{t}")
                    model.add_max_equality(v, availability[t])
                    args = [sizes[t], v]
                elif s["method"] == "balanced":
                    v = model.new_int_var(1, 5*N, f"experience_sum_{t}")
                    model.add(v == sum(p["answers"][q]*x[p["id"], t] for p in s["people"]))
                    args = [sizes[t], v]
                else:
                    low_values, high_values = [], []
                    for j, p in enumerate(s["people"]):
                        e, b = p["answers"][q], x[p["id"], t]
                        low = model.new_int_var(1, 6, f"lo_{t}_{j}")
                        high = model.new_int_var(0, 5, f"hi_{t}_{j}")
                        model.add(low == 6+(e-6)*b)
                        model.add(high == e*b)
                        low_values.append(low)
                        high_values.append(high)
                    lo, hi = model.new_int_var(1, 5, f"min_{t}"), model.new_int_var(1, 5, f"max_{t}")
                    model.add_min_equality(lo, low_values)
                    model.add_max_equality(hi, high_values)
                    args = [lo, hi]
                model.add_allowed_assignments(args+[loss], ts[q])
            W = sum(s["weights"].values())
            L = model.new_int_var(0, 1000*W, f"L_{t}")
            model.add(L == sum(s["weights"][q]*v for q, v in scorevars[t].items()))
            weighted.append(L)
        W = sum(s["weights"].values())
        A = model.new_int_var(0, 1000*W, "worst_team")
        model.add_max_equality(A, weighted)
        Fint = 3*K*A+2*sum(weighted)
        together = []
        for j, (a, b) in enumerate(s["edges"]):
            for t in s["tids"]:
                y = model.new_bool_var(f"private_{j}_{t}")
                model.add(y <= x[a, t])
                model.add(y <= x[b, t])
                model.add(y >= x[a, t]+x[b, t]-1)
                together.append(y)
        V = model.new_int_var(0, len(s["edges"]), "private_violations")
        model.add(V == sum(together))
        J = 18*N*Fint+5000*K*W*V
        model.minimize(J)
        problem = model.validate()
        if problem:
            raise ValueError(problem)
        internal["table_rows"] = table_rows
        solver = configured_solver(s)
        status = solver.solve(model)
        internal["solver_status"] = solver.status_name(status)
        internal["deterministic_time"] = solver.response_proto.deterministic_time
        internal["best_objective_bound"] = solver.best_objective_bound
        if status in (cp.OPTIMAL, cp.FEASIBLE):
            assignment = {i: next(t for t in s["tids"] if solver.value(x[i, t])) for i in s["ids"]}
            verified = verify(s, assignment)
            if verified["J_int"] != solver.value(J) or verified["V"] != solver.value(V):
                raise ValueError("독립 목적식 검증 실패")
            for t, items in scorevars.items():
                if any(solver.value(v) != verified["losses"][t]["items"][q] for q, v in items.items()):
                    raise ValueError("독립 항목 점수 검증 실패")
            if verified["F_int"] != solver.value(Fint):
                raise ValueError("독립 공정성 점수 검증 실패")
            internal.update({k: v for k, v in verified.items() if k != "summaries"})
            internal["assignment"] = assignment
            return finish(solver.status_name(status), verified["summaries"])
        if status == cp.UNKNOWN:
            return finish("LIMIT_NO_CANDIDATE", messages=["탐색 한도에 도달했습니다. 불가능이 확인된 것은 아닙니다."])
        if status == cp.INFEASIBLE:
            dm, _, _, _, labels = hard_model(s, diagnostic=True)
            ds = configured_solver(s)
            dstatus = ds.solve(dm)
            internal["diagnostic_status"] = ds.status_name(dstatus)
            if dstatus == cp.INFEASIBLE:
                conflicts = [labels[i] for i in ds.sufficient_assumptions_for_infeasibility() if i in labels]
                internal["conflicts"] = conflicts
                return finish("INFEASIBLE", messages=["함께 충족할 수 없는 필수 조건이 있습니다."]+conflicts)
            if dstatus in (cp.OPTIMAL, cp.FEASIBLE):
                raise ValueError("편성 모델과 진단 모델 불일치")
            raise ValueError("진단 한도 내 필수 조건 충돌을 재확인하지 못했습니다.")
        raise ValueError(f"솔버 비정상 상태: {solver.status_name(status)}")
    except (InputError, KeyError, TypeError, ValueError) as e:
        internal["error"] = str(e)
        # Missing responses are actionable input errors, never imputed.
        messages = ([str(e)] if ((isinstance(e, InputError) and "비공개" not in str(e))
                                or str(e).startswith("점수표 행 수"))
                    else ["처리 중 오류가 발생했습니다. 내부 기록을 확인해 주세요."])
        return finish("ERROR", messages=messages)
    except Exception as e:
        internal["error"] = f"{type(e).__name__}: {e}"
        return finish("ERROR", messages=["처리 중 오류가 발생했습니다."])
