"""편성알고리즘 v3 CP-SAT engine. Public result and sensitive internal record stay separate."""
import copy
import hashlib
import math
import json
import time

import ortools
from ortools.sat.python import cp_model as cp

from .schema import (normalize, precheck, upper_bounds, InputError,
                     ALGORITHM_VERSION, SPEC_VERSION)
from .scoring import item_table, verify, picks, totals, TableTooLarge

# v3 9-2 / 9-3 화면 안내 문구
ZERO_MOVE_NOTICE = "기존 배정을 그대로 유지할 수 있어 기존 팀원은 이동하지 않았습니다. 새 참가자만 배정했습니다."
UNPROVEN_MOVE_NOTICE = "탐색한 후보 중 이동이 가장 적은 안입니다."
GENERIC_ERROR = "처리 중 오류가 발생했습니다."


class EngineError(Exception):
    """계산을 믿을 수 없는 경우 (v3 11-1): 후보를 적용하지 않는다."""


# ---------------------------------------------------------------- hard model

def hard_model(s, diagnostic=False):
    """필수 조건만. diagnostic=True면 운영진이 바꿀 수 있는 조건에 가정 리터럴을 붙인다 (12-2)."""
    model = cp.CpModel()
    N = len(s["people"])
    x = {(p["id"], t["id"]): model.new_bool_var(f"x_{i}_{j}")
         for i, p in enumerate(s["people"]) for j, t in enumerate(s["teams"])}
    for i in s["ids"]:
        model.add_exactly_one(x[i, t] for t in s["tids"])
    labels = {}  # literal index -> (literal, label)

    def condition(constraints, label):
        if diagnostic:
            a = model.new_bool_var(f"assumption_{len(labels)}")
            for c in constraints:
                c.only_enforce_if(a)
            labels[a.index] = (a, label)

    sizes = {}
    for t in s["tids"]:
        n = model.new_int_var(1, N, f"n_{t}")
        model.add(n == sum(x[i, t] for i in s["ids"]))
        sizes[t] = n
        cap = s["capacity"][t]
        if cap is not None:
            condition([model.add(n <= cap)], f"{t}: 최대 정원 {cap}명")

    # 3장 고정 적용 규칙
    by_scope_team = {}
    for i, (t, kind) in sorted(s["fixed"].items()):
        if kind == "manual":
            condition([model.add(x[i, t] == 1)], f"{i} → {t}: 수동 고정")
        else:
            by_scope_team.setdefault(t, []).append(model.add(x[i, t] == 1))
    for t, cs in sorted(by_scope_team.items()):
        condition(cs, f"재편성 범위: {t}은 범위 밖이라 현재 배정 유지")
    outside = [t for t in s["tids"] if t not in s["scope"]]
    free = [i for i in s["ids"] if i not in s["fixed"]]
    if outside and free:
        condition([model.add(sum(x[i, t] for i in free for t in outside) == 0)],
                  "재편성 범위: 새로 배정할 참가자는 선택한 팀에만")

    for r in s["required"]:
        condition([model.add(sum(x[p["id"], r["team"]] for p in s["people"]
                                 if p["answers"]["role"] == r["role"]) >= r["minimum"])],
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
                    # 10-2: h = 팀 전원이 그 시간에 가능
                    h = model.new_bool_var(f"common_{t}_{j}")
                    u = sizes[t]-a
                    model.add(u <= N*(1-h))
                    model.add(u >= 1-h)
                    hs.append(h)
            availability[t] = av
            if s["common"]:
                condition([model.add(sum(hs) >= 1)], f"{t}: 전원 공통 가능 시간 최소 1개")
    return model, x, sizes, availability, labels


# ------------------------------------------------------------ score encoding

def add_rounded_ratio(model, loss, A, v, c, v_max, name):
    """loss == rounded(A / (c·v)) exactly, v >= 1 (rounded = 반올림, 절반은 올림).

    rounded(A/B) = floor((2A+B)/(2B)) ⇔ 2B·loss ≤ 2A+B ≤ 2B·loss + 2B − 1, B = c·v.
    """
    M = model.new_int_var(0, 1000*v_max, f"{name}_vloss")
    model.add_multiplication_equality(M, [v, loss])
    model.add(2*c*M <= 2*A+c*v)
    model.add(2*A+c*v <= 2*c*M+2*c*v-1)


def encode_item(model, s, x, sizes, availability, t, q, upper, name):
    """팀 t, 항목 q의 손실 변수. 표가 한도를 넘으면 정확한 선형화로 바꾼다 (3-1).

    Returns (loss_var, table_rows or None).
    """
    N = len(s["people"])
    n = sizes[t]
    loss = model.new_int_var(0, 1000, f"loss_{name}")
    members = lambda pred: sum(x[p["id"], t] for p in s["people"] if pred(p))

    if q == "size":
        args = [n]
    elif q in ("role", "interest"):
        counts = []
        for j, c in enumerate(s["categories"][q]):
            v = model.new_int_var(0, N, f"count_{name}_{j}")
            model.add(v == members(lambda p, c=c: picks(p, q, c)))
            counts.append(v)
        args = [n]+counts
    elif q == "time":
        best = model.new_int_var(0, N, f"best_time_{name}")
        model.add_max_equality(best, availability[t])
        args = [n, best]
    elif s["method"] == "balanced":
        total = model.new_int_var(1, 5*N, f"experience_sum_{name}")
        model.add(total == sum(p["answers"][q]*x[p["id"], t] for p in s["people"]))
        args = [n, total]
    else:
        lows, highs = [], []
        for j, p in enumerate(s["people"]):
            e, b = p["answers"][q], x[p["id"], t]
            low = model.new_int_var(1, 6, f"lo_{name}_{j}")
            high = model.new_int_var(0, 5, f"hi_{name}_{j}")
            model.add(low == 6+(e-6)*b)
            model.add(high == e*b)
            lows.append(low)
            highs.append(high)
        lo, hi = model.new_int_var(1, 5, f"min_{name}"), model.new_int_var(1, 5, f"max_{name}")
        model.add_min_equality(lo, lows)
        model.add_max_equality(hi, highs)
        args = [lo, hi]

    try:
        rows = item_table(s, q, upper)
        model.add_allowed_assignments(args+[loss], rows)
        return loss, len(rows)
    except TableTooLarge:
        pass

    # 선형화: 표와 같은 값을 정확히 강제한다.
    if q in ("role", "interest") and s["method"] == "balanced":
        counts, tot = args[1:], totals(s, q)
        if q == "role":
            v, c, v_max = n, N, N
        else:
            T = sum(tot)
            v = model.new_int_var(1, N*len(counts), f"mentions_{name}")
            model.add(v == sum(counts))
            c, v_max = T, N*len(counts)
        devs = []
        for j, (cnt, tj) in enumerate(zip(counts, tot)):
            d = model.new_int_var(0, c*N*len(counts), f"dev_{name}_{j}")
            model.add_abs_equality(d, c*cnt-tj*v)
            devs.append(d)
        add_rounded_ratio(model, loss, 500*sum(devs), v, c, v_max, name)
    elif q in ("role", "interest"):
        mx = model.new_int_var(0, N, f"max_count_{name}")
        model.add_max_equality(mx, args[1:])
        add_rounded_ratio(model, loss, 1000*(n-mx), n, 1, N, name)
    elif q == "time":
        add_rounded_ratio(model, loss, 1000*(n-args[1]), n, 1, N, name)
    elif q == "experience" and s["method"] == "balanced":
        G = sum(p["answers"][q] for p in s["people"])
        d = model.new_int_var(0, 5*N*N, f"exp_dev_{name}")
        model.add_abs_equality(d, N*args[1]-G*n)
        add_rounded_ratio(model, loss, 250*d, n, N, N, name)
    elif q == "experience":
        model.add(loss == 250*(args[1]-args[0]))
    else:
        # 인원: 1000·|n − N/K| / D_max = 1000·|K·n − N| / D, D = max(K(N−K+1)−N, N−K)
        K = len(s["teams"])
        if N == K or K == 1:
            model.add(loss == 0)
        else:
            D = max(K*(N-K+1)-N, N-K)
            d = model.new_int_var(0, K*N, f"size_dev_{name}")
            model.add_abs_equality(d, K*n-N)
            model.add(2*D*loss <= 2000*d+D)
            model.add(2000*d+D <= 2*D*loss+2*D-1)
    return loss, None


def formation_model(s):
    """편성 모델 = 필수 조건 + 점수 + 목적식 (10-5)."""
    model, x, sizes, availability, _ = hard_model(s)
    N, K = len(s["people"]), len(s["teams"])
    # 편성학습 9장의 w'(= 10·w·b)를 공약수로 나눠 모델에 넣는다. 목적식이 양의 상수배만
    # 달라지므로 최적 집합은 같고, b = 1이면 v3 원래 가중치(5~1)와 똑같은 모델이 된다
    # (개발단계 가이드 3단계: ×10 방식과 원래 가중치의 편성 결과가 같아야 함).
    g = math.gcd(*s["weights"].values())
    w = {q: v//g for q, v in s["weights"].items()}
    W = sum(w.values())
    U = upper_bounds(s)
    scorevars, weighted, table_rows, linearized = {}, [], {}, []
    for j, t in enumerate(s["tids"]):
        scorevars[t], table_rows[t] = {}, {}
        for q in ["size"]+s["selected"]:
            loss, rows = encode_item(model, s, x, sizes, availability, t, q, U[t], f"{j}_{q}")
            scorevars[t][q] = loss
            table_rows[t][q] = rows
            if rows is None:
                linearized.append({"team": t, "item": q})
        L = model.new_int_var(0, 1000*W, f"L_{t}")
        model.add(L == sum(w[q]*v for q, v in scorevars[t].items()))
        weighted.append(L)
    A = model.new_int_var(0, 1000*W, "worst_team")
    model.add_max_equality(A, weighted)
    F_int = 3*K*A+2*sum(weighted)

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
    J = 18*N*F_int+5000*K*W*V

    # 9장: 팀 ID가 바뀐 사람 수. 삭제 팀 소속은 항상 이동 (상수).
    def moved(reference):
        return sum((1-x[i, t]) if t in s["tids"] else 1 for i, t in reference.items())
    return dict(model=model, x=x, scorevars=scorevars, F_int=F_int, V=V, J=J, scale=g,
                M_pub=moved(s["pub"]), M_draft=moved(s["draft_assign"]),
                U=U, table_rows=table_rows, linearized=linearized)


# ------------------------------------------------------------ staged search

def configured_solver(s):
    solver = cp.CpSolver()
    solver.parameters.num_workers = 1  # 10-4 재현성
    solver.parameters.random_seed = s["seed"]
    solver.parameters.max_deterministic_time = s["limit"]
    return solver


class _Collector(cp.CpSolverSolutionCallback):
    """Every improving solution of a stage, with the solver's own values for cross-check."""

    def __init__(self, s, m):
        super().__init__()
        self.s, self.m, self.found = s, m, []

    def on_solution_callback(self):
        s, m = self.s, self.m
        assignment = {i: next(t for t in s["tids"] if self.value(m["x"][i, t])) for i in s["ids"]}
        # 처음 편성에는 이동 항이 상수 0
        values = {k: m[k] if isinstance(m[k], int) else self.value(m[k])
                  for k in ("J", "V", "F_int", "M_pub", "M_draft")}
        values["items"] = {t: {q: self.value(v) for q, v in items.items()}
                           for t, items in m["scorevars"].items()}
        self.found.append((assignment, values))


def run_stage(s, m, objective, hint):
    """One CP-SAT minimization. Returns (status_name, candidates, objective_value, bound)."""
    model = m["model"]
    model.minimize(objective)
    model.clear_hints()
    for (i, t), var in m["x"].items():
        if i in hint:
            model.add_hint(var, hint[i] == t)
    problem = model.validate()
    if problem:
        raise EngineError(f"MODEL_INVALID: {problem}")
    solver = configured_solver(s)
    collector = _Collector(s, m)
    status = solver.solve(model, collector)
    name = solver.status_name(status)
    if name == "MODEL_INVALID":
        raise EngineError("MODEL_INVALID")
    value = solver.objective_value if collector.found else None
    return name, collector.found, value, solver.best_objective_bound, solver.response_proto.deterministic_time


def candidate_key(s, verified):
    if s["mode"] == "republish":
        return (verified["M_pub"], verified["J_int"], verified["M_draft"])
    return (verified["J_int"],)


def checked(s, assignment, values, scale=1):
    """독립 검증기로 다시 계산하고 솔버 값과 대조 (11-1 검증 실패 → 적용 차단)."""
    try:
        verified = verify(s, assignment)
    except ValueError as e:
        raise EngineError(f"독립 검증 실패: {e}")
    for k in ("J", "V", "F_int", "M_pub", "M_draft"):
        mine = verified["J_int" if k == "J" else k]
        theirs = values[k]*scale if k in ("J", "F_int") else values[k]
        if mine != theirs:
            raise EngineError(f"독립 검증 불일치: {k}")
    for t, items in values["items"].items():
        if items != verified["losses"][t]["items"]:
            raise EngineError("독립 검증 불일치: 항목 손실")
    return verified


def published_hint(s):
    """10-3: 탈퇴자·삭제 팀·새 설정과 충돌하는 힌트는 뺀다. 고정은 힌트가 아니라 제약."""
    return {i: t for i, t in s["pub"].items() if t in s["allowed"][i]}


def optimize(s, m, stage_runner=run_stage):
    """v3 9장 단계별 최적화 + 9-1 현재 최선 후보 유지.

    Returns dict(status, incumbent, stages, proof). status: OPTIMAL/FEASIBLE/INFEASIBLE/LIMIT_NO_CANDIDATE.
    """
    republish = s["mode"] == "republish"
    names = ["pub", "quality", "draft"] if republish else ["quality"]
    objectives = {"pub": m["M_pub"], "quality": m["J"], "draft": m["M_draft"]}
    position = {"pub": 0, "quality": 1 if republish else 0, "draft": 2}
    inc = None  # (key, assignment, verified)
    stages, optimum = [], {}

    for k, name in enumerate(names):
        if inc is not None:
            # 9-1 규칙 3: 제한은 현재 최선 후보의 값 (앞 단계 OPTIMAL이면 그 값과 같음)
            if name in ("quality", "draft"):
                m["model"].add(m["M_pub"] <= inc[2]["M_pub"])
            if name == "draft":
                m["model"].add(m["J"] <= inc[2]["J_int"]//m["scale"])
        hint = inc[1] if inc else (published_hint(s) if republish else {})
        status, found, value, bound, dtime = stage_runner(s, m, objectives[name], hint)
        unit = m["scale"] if name == "quality" else 1  # 기록은 J_int 단위로
        stages.append({"stage": name, "status": status,
                       "objective": None if value is None else value*unit,
                       "bound": bound*unit, "deterministic_time": dtime, "candidates": len(found)})
        if status == "INFEASIBLE":
            if k == 0:
                return dict(status="INFEASIBLE", incumbent=None, stages=stages, proof={})
            # 현재 최선 후보가 제약을 만족하는데 불가능이면 모델 결함
            raise EngineError(f"{name} 단계가 현재 최선 후보와 모순")
        if status not in ("OPTIMAL", "FEASIBLE", "UNKNOWN"):
            raise EngineError(f"솔버 비정상 상태: {status}")
        for assignment, values in found:
            verified = checked(s, assignment, values, m["scale"])
            key = candidate_key(s, verified)
            if inc is None or key < inc[0]:
                inc = (key, assignment, verified)
        if inc is None:
            return dict(status="LIMIT_NO_CANDIDATE", incumbent=None, stages=stages, proof={})
        if status == "OPTIMAL":
            optimum[name] = value*unit

    # 9-1 규칙 4 / 9-3: 최종 후보의 값이 그 단계의 증명된 최적값과 같을 때만 증명
    proof = {n: (n in optimum and inc[0][position[n]] == optimum[n]) for n in names}
    status = "OPTIMAL" if all(proof.values()) else "FEASIBLE"
    return dict(status=status, incumbent=inc, stages=stages, proof=proof)


# ------------------------------------------------------------- diagnostics

def diagnose(s):
    """진단 모델(필수 조건만)에서 충돌 조건 집합을 찾고 하나씩 빼 보며 줄인다 (12-2)."""
    model, _, _, _, labels = hard_model(s, diagnostic=True)

    def status_with(indices):
        model.clear_assumptions()
        model.add_assumptions([labels[i][0] for i in indices])
        solver = configured_solver(s)
        return solver.status_name(solver.solve(model)), solver

    status, solver = status_with(sorted(labels))
    if status != "INFEASIBLE":
        return status, None
    core = sorted(i for i in solver.sufficient_assumptions_for_infeasibility() if i in labels)
    for i in list(core):
        trial = [c for c in core if c != i]
        # 진단 한도 안에서 불가능이 확인될 때만 뺀다 (확인된 충돌만 안내)
        if status_with(trial)[0] == "INFEASIBLE":
            core = trial
    return "INFEASIBLE", [labels[i][1] for i in core]


# ---------------------------------------------------------------- entry

def cache_key(raw):
    """10-4: 같은 실행 입력이면 같은 결과. 실행 ID는 입력이 아니다."""
    body = {k: v for k, v in raw.items() if k != "run_id"}
    return hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def run_precheck(raw):
    """/precheck: v3 12-1 사전 검사만."""
    try:
        s = normalize(copy.deepcopy(raw))
    except (InputError, KeyError, TypeError) as e:
        return {"ok": False, "issues": [{"kind": "input", "message": str(e)}]}
    issues = precheck(s)
    return {"ok": not issues, "issues": issues}


def solve(raw, cache=None, stage_runner=run_stage):
    start = time.perf_counter()
    raw = copy.deepcopy(raw)
    key = cache_key(raw)
    if cache is not None and key in cache:
        result = copy.deepcopy(cache[key])
        result["internal"]["cache_hit"] = True
        return result
    internal = {"spec_version": SPEC_VERSION, "algorithm_version": ALGORITHM_VERSION,
                "ortools_version": ortools.__version__, "input_sha256": key}
    public = {"label": "추천 편성안", "status": None, "teams": [], "messages": []}

    def finish(status, messages=()):
        elapsed = time.perf_counter()-start
        internal["elapsed_seconds"] = elapsed
        public.update(status=status, elapsed_seconds=elapsed)
        public["messages"] = list(public["messages"])+list(messages)
        result = {"public": public, "internal": internal}
        # 정상 종료만 저장해 재사용 (ERROR는 재시도 대상)
        if cache is not None and status != "ERROR":
            cache[key] = copy.deepcopy(result)
        return result

    try:
        s = normalize(raw)
        public.update(kind=s["kind"], weights_used=s["weights"], model_id=s["model_id"])
        internal.update(seed=s["seed"], workers=1, max_deterministic_time=s["limit"],
                        versions=s["versions"], weights_used=s["weights"])
        issues = precheck(s)
        missing = [i["message"] for i in issues if i["kind"] == "missing_answers"]
        if missing:
            # 4장: 0이나 평균으로 채우지 않는다. 설정 검증에서 처리할 입력 문제.
            internal["precheck"] = issues
            return finish("ERROR", missing+["응답 요청, 질문 전체 제외, 참가자 제외 중 하나를 선택해 주세요."])
        if issues:
            internal["precheck"] = issues
            return finish("INFEASIBLE", [i["message"] for i in issues])

        m = formation_model(s)
        internal.update(table_rows=m["table_rows"], linearized=m["linearized"], upper_bounds=m["U"])
        result = optimize(s, m, stage_runner)
        internal["stages"] = result["stages"]
        internal["stage_proof"] = result["proof"]

        if result["status"] == "INFEASIBLE":
            dstatus, conflicts = diagnose(s)
            internal["diagnostic_status"] = dstatus
            if dstatus in ("OPTIMAL", "FEASIBLE"):
                raise EngineError("편성 모델과 진단 모델 불일치")  # 10-5
            if conflicts is None:
                raise EngineError("진단 한도 내 필수 조건 충돌을 재확인하지 못했습니다.")
            internal["conflicts"] = conflicts
            return finish("INFEASIBLE", ["함께 충족할 수 없는 필수 조건이 있습니다."]+conflicts)
        if result["status"] == "LIMIT_NO_CANDIDATE":
            return finish("LIMIT_NO_CANDIDATE", ["탐색 한도에 도달했습니다. 불가능이 확인된 것은 아닙니다."])

        key_, assignment, verified = result["incumbent"]
        public["teams"] = verified["summaries"]
        public["stage_proof"] = {n: result["proof"].get(n) for n in ("pub", "quality", "draft")}
        internal.update({k: v for k, v in verified.items() if k != "summaries"})
        internal.update(assignment=assignment, incumbent_key=list(key_))
        if s["mode"] == "republish":
            public["moves"] = {"existing_moved": verified["M_pub"],
                               "due_to_team_deletion": verified["deletion_moves"]}
            if verified["deletion_moves"]:
                public["messages"].append(f"팀 삭제로 인한 이동 {verified['deletion_moves']}명")
            if verified["M_pub"] == 0:
                public["messages"].append(ZERO_MOVE_NOTICE)
            elif not result["proof"]["pub"]:
                public["messages"].append(UNPROVEN_MOVE_NOTICE)
        return finish(result["status"])
    except InputError as e:
        internal["error"] = str(e)
        # 비공개 선호 관련 입력 오류는 존재 자체를 드러내지 않는다 (7장)
        return finish("ERROR", [GENERIC_ERROR if "비공개" in str(e) else str(e)])
    except Exception as e:
        # 11-1: 원인 세부 내용 없이 안내 (비공개 정보 노출 방지)
        internal["error"] = f"{type(e).__name__}: {e}"
        return finish("ERROR", [GENERIC_ERROR])
