"""Stage 3: exact, table-free CP-SAT + independent Fraction verifier.
Internal results NEVER cross the HTTP boundary. Existing initial engine is preserved.
"""
from collections import Counter
from fractions import Fraction
import hashlib
import json
import math
import ortools
from ortools.sat.python import cp_model as cp

ENGINE_VERSION = 'formation-3.1.0'
BASIC = ('time', 'role', 'experience', 'interest')
PERSONALITY = 'personality'
MAX_TRAITS, MAX_TRAIT_ITEMS = 4, 3
VALID = {'OPTIMAL', 'FEASIBLE'}

class Invalid(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise Invalid(message)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    default=str, separators=(',', ':')).encode()).hexdigest()


def rounded(a, b=1):
    v = Fraction(a, b)
    return (2*v.numerator + v.denominator)//(2*v.denominator)


def learned_weights(priority, factors=None):
    """편성학습_v4 9장: w'_q = round(10 * w_q * b_q), priority order kept, w'_q >= 1.

    w_q = m - r + 1 (편성알고리즘_v3 5장). Without a model every b_q = 1, so all weights and W are
    exactly 10x the v3 weights and the formation result is unchanged.
    """
    factors = factors or {}
    require(isinstance(factors, dict) and set(factors) <= set(priority), '보정 계수 확인 필요')
    for v in factors.values():
        require(type(v) in (int, float) and math.isfinite(v) and 0.5 <= v <= 2.0, '보정 계수 확인 필요')
    weights, previous = {}, None
    for r, q in enumerate(priority):
        w = rounded(Fraction(10 * (len(priority) - r)) * Fraction(factors.get(q, 1)).limit_denominator(10**6))
        if previous is not None:
            w = min(w, previous)
        weights[q] = previous = max(1, w)
    return weights


def prepare(raw):
    s = json.loads(json.dumps(raw))
    people, teams = s.get('participants', []), s.get('teams', [])
    require(0 < len(people) <= 200 and 0 < len(teams) <= 100, '참가자·팀 수를 확인해 주세요')
    ids, tids = [p['id'] for p in people], [t['id'] for t in teams]
    require(all(isinstance(i, str) and i for i in ids+tids), '잘못된 ID')
    require(len(ids) == len(set(ids)) and len(tids) == len(set(tids)), '중복 ID')
    s['participants'] = sorted(people, key=lambda p: p['id'])
    s['teams'] = sorted(teams, key=lambda t: t['id'])
    selected = s.get('selected_questions', [])
    priority = s.get('priority', [])
    require(len(selected) == len(set(selected)) and set(selected) <= set(BASIC) | {PERSONALITY}, '잘못된 기준')
    require(len(priority) == len(set(priority)) and set(priority) == set(selected)|{'size'}, '우선순위 확인 필요')
    require(s.get('method') in ('balanced', 'similar'), '잘못된 편성 방식')
    cats = s.get('categories', {})
    traits = s.get('traits', [])
    if PERSONALITY in selected:
        require(isinstance(traits, list) and 0 < len(traits) <= MAX_TRAITS, '성향 축 확인 필요')
        require(all(isinstance(t, dict) and isinstance(t.get('id'), str) and t['id'] and
                    type(t.get('size')) is int and 1 <= t['size'] <= MAX_TRAIT_ITEMS for t in traits), '성향 축 확인 필요')
        require(len({t['id'] for t in traits}) == len(traits), '성향 축 중복')
    else:
        traits = []
    s['traits'] = traits
    for q in selected:
        if q == PERSONALITY:
            continue
        if q != 'experience':
            require(isinstance(cats.get(q), list) and 0 < len(cats[q]) <= 50 and
                    all(isinstance(c, str) and c for c in cats[q]) and len(set(cats[q])) == len(cats[q]), '선택지 확인 필요')
    for p in people:
        for q in selected:
            v = p.get('answers', {}).get(q)
            if q == 'experience':
                ok = type(v) is int and 1 <= v <= 5
            elif q == PERSONALITY:
                ok = isinstance(v, dict) and set(v) == {t['id'] for t in traits} and all(
                    type(v[t['id']]) is int and t['size'] <= v[t['id']] <= 5*t['size'] for t in traits)
            elif q == 'role':
                ok = isinstance(v, str) and v in cats[q]
            else:
                ok = isinstance(v, list) and bool(v) and all(isinstance(c, str) for c in v) and len(v) == len(set(v)) and set(v) <= set(cats[q])
            require(ok, f'{p["id"]}: {q} 응답 요청 또는 질문 전체/참가자 제외가 필요합니다')
    for t in teams:
        require(t.get('capacity') is None or type(t['capacity']) is int and t['capacity'] > 0, '정원 확인 필요')
    s['weights'] = learned_weights(priority, s.get('weightFactors'))
    s['published'] = {i:t for i,t in s.get('published', {}).items() if i in ids}
    s['draft'] = {i:t for i,t in s.get('draft', {}).items() if i in ids and t is not None}
    s.setdefault('locks', {})
    require(all(i in ids and isinstance(v, dict) and v.get('type') in ('manual','default') for i,v in s['locks'].items()), '고정 확인 필요')
    scope = s.get('scopeTeamIds')
    if scope is not None:
        require(isinstance(scope, list) and scope and len(scope) == len(set(scope)), '재편성 범위 확인 필요')
        require(set(scope) <= set(tids)|set(s['published'].values()), '알 수 없는 범위')
        if s['published']:
            require((set(tids)^set(s['published'].values())) <= set(scope), '추가·삭제 팀을 재편성 범위에 포함해 주세요')
    fixed = {}
    for i, lock in s['locks'].items():
        t = lock.get('teamId')
        if lock['type'] == 'manual':
            require(t in tids, '삭제할 팀의 수동 고정을 먼저 해제해 주세요')
            fixed[i] = t
    if scope is not None:
        for i,t in s['draft'].items():
            if t not in scope:
                require(t in tids, '삭제 팀을 재편성 범위에 포함해 주세요')
                require(i not in fixed or fixed[i] == t, '범위 밖 고정 충돌')
                fixed[i] = t
    s['fixed'] = fixed
    s.setdefault('required_roles', [])
    for r in s['required_roles']:
        require('role' in selected and r.get('team') in tids and r.get('role') in cats['role'] and type(r.get('minimum')) is int and r['minimum'] > 0, '필수 역할 확인 필요')
    require(type(s.get('require_common_time', False)) is bool, '공통 시간 조건 확인 필요')
    require(not s.get('require_common_time') or 'time' in selected, '시간 질문이 필요합니다')
    edges, outgoing = set(), {}
    for e in s.get('private_preferences', []):
        if not e.get('confirmed') or e.get('withdrawn'):
            continue
        a,b = e['source'],e['target']
        if a not in ids or b not in ids:
            continue
        require(a != b, '비공개 입력 확인 필요')
        outgoing.setdefault(a,set()).add(b)
        require(len(outgoing[a]) <= 2, '비공개 입력 확인 필요')
        edges.add(tuple(sorted((a,b))))
    s['edges'] = sorted(edges)
    require(type(s.get('seed',42)) is int and 0 <= s.get('seed',42) < 2**31, '시드 확인 필요')
    limit = s.get('limit',10)
    require(type(limit) in (int,float) and math.isfinite(limit) and 0 < limit <= 30, '탐색 한도 확인 필요')
    return s


def assess(s, assignment):
    """Independent rational formulas; permits incomplete drafts, never invents scores."""
    people, teams = s['participants'], s['teams']
    ids, tids = {p['id'] for p in people}, {t['id'] for t in teams}
    errors = []
    if set(assignment) != ids or any(t not in tids for t in assignment.values()):
        errors.append('미배정 또는 명단·팀 불일치')
    grouped = {t['id']: [p for p in people if assignment.get(p['id']) == t['id']] for t in teams}
    for t in teams:
        n = len(grouped[t['id']])
        if not n: errors.append(f'{t["id"]}: 빈 팀')
        if t.get('capacity') is not None and n > t['capacity']: errors.append(f'{t["id"]}: 정원 초과')
    for i,t in s['fixed'].items():
        if assignment.get(i) != t: errors.append(f'{i}: 고정 위반')
    if s.get('scopeTeamIds') is not None:
        for i,t in assignment.items():
            if i not in s['fixed'] and t not in s['scopeTeamIds']:
                errors.append('선택한 재편성 범위 위반')
    for r in s['required_roles']:
        if sum(p['answers'].get('role') == r['role'] for p in grouped[r['team']]) < r['minimum']:
            errors.append(f'{r["team"]}: 필수 역할 희망자 부족')
    N,K = len(people),len(teams)
    summary, weighted = {},[]
    for tid,members in grouped.items():
        n = len(members)
        item = {'members': sorted(p['id'] for p in members), 'size': n}
        summary[tid] = item
        if not n:
            item['losses'] = None
            continue
        d = max(Fraction(N-K+1)-Fraction(N,K), Fraction(N,K)-1)
        losses = {'size': rounded(1000*abs(Fraction(n)-Fraction(N,K))/d) if d else 0}
        for q in s['selected_questions']:
            vals = [p['answers'][q] for p in members]
            if q in ('role','interest'):
                cats = s['categories'][q]
                counts = [sum(v == c if q == 'role' else c in v for v in vals) for c in cats]
                totals = [sum(p['answers'][q] == c if q == 'role' else c in p['answers'][q] for p in people) for c in cats]
                if s['method'] == 'similar':
                    loss = rounded(1000*(1-Fraction(max(counts),n)))
                else:
                    loss = rounded(500*sum(abs(Fraction(a,sum(counts))-Fraction(b,sum(totals))) for a,b in zip(counts,totals)))
                item['rolePreferences' if q == 'role' else 'interests'] = dict(zip(cats,counts))
            elif q == PERSONALITY:
                A = len(s['traits']); loss = 0; profile = {}
                for t in s['traits']:
                    tv = [v[t['id']] for v in vals]; k = t['size']
                    if s['method'] == 'balanced':
                        total = sum(p['answers'][q][t['id']] for p in people)
                        loss += rounded(250*abs(Fraction(sum(tv),n)-Fraction(total,N)), k*A)
                    else:
                        loss += rounded(250*(max(tv)-min(tv)), k*A)
                    profile[t['id']] = {'sum': sum(tv), 'items': k, 'respondents': n, 'mean': sum(tv)/(n*k)}
                item['personality'] = profile
            elif q == 'time':
                counts = {c:sum(c in v for v in vals) for c in s['categories'][q]}
                item['commonTimes'] = [c for c,v in counts.items() if v == n]
                item['timeAvailability'] = counts
                if s.get('require_common_time') and not item['commonTimes']: errors.append(f'{tid}: 전원 공통 시간 없음')
                loss = rounded(1000*(1-Fraction(max(counts.values()),n)))
            else:
                loss = rounded(250*abs(Fraction(sum(vals),n)-Fraction(sum(p['answers'][q] for p in people),N))) if s['method'] == 'balanced' else 250*(max(vals)-min(vals))
                item['selfReportedExperience'] = {'sum':sum(vals),'respondents':n,'mean':sum(vals)/n}
            losses[q] = loss
        item['losses'] = losses
        weighted.append(sum(s['weights'][q]*v for q,v in losses.items()))
    pub = {'publicSummary':summary, 'requiredStatus':{'valid':not errors,'conflicts':sorted(set(errors))}}
    if errors:
        return pub, None
    V = sum(assignment[a] == assignment[b] for a,b in s['edges'])
    J = 18*N*(3*K*max(weighted)+2*sum(weighted))+5000*K*sum(s['weights'].values())*V
    mp = sum(assignment[i] != t for i,t in s['published'].items())
    md = sum(assignment[i] != t for i,t in s['draft'].items())
    return pub, {'J_int':J,'V':V,'M_pub':mp,'M_draft':md,'key':(mp,J,md) if s['published'] else (J,)}


def build(s, scoring=True, diagnostic=False):
    model = cp.CpModel()
    people, teams = s['participants'],s['teams']
    ids,tids = [p['id'] for p in people],[t['id'] for t in teams]
    N,K = len(ids),len(tids)
    x = {(i,t):model.new_bool_var(f'x_{a}_{b}') for a,i in enumerate(ids) for b,t in enumerate(tids)}
    labels = {}
    def hard(c,label):
        if diagnostic:
            lit = model.new_bool_var(f'a_{len(labels)}')
            c.only_enforce_if(lit); model.add_assumption(lit); labels[lit.index] = label
    for i in ids: model.add_exactly_one(x[i,t] for t in tids)
    sizes = {}
    for t in teams:
        tid = t['id']; n = model.new_int_var(0,N,f'n_{tid}')
        model.add(n == sum(x[i,tid] for i in ids)); sizes[tid]=n
        hard(model.add(n >= 1),f'{tid}: 빈 팀 금지')
        if t.get('capacity') is not None: hard(model.add(n <= t['capacity']),f'{tid}: 최대 정원')
    for i,t in s['fixed'].items(): hard(model.add(x[i,t] == 1),f'{i}: 고정 배치')
    if s.get('scopeTeamIds') is not None:
        for i in ids:
            if i not in s['fixed']:
                for t in tids:
                    if t not in s['scopeTeamIds']:
                        hard(model.add(x[i,t] == 0), '선택한 재편성 범위')
    for r in s['required_roles']:
        hard(model.add(sum(x[p['id'],r['team']] for p in people if p['answers'].get('role') == r['role']) >= r['minimum']),f'{r["team"]}: 필수 역할 {r["role"]}')
    for t in tids:
        if s.get('require_common_time'):
            hs=[]
            for c in s['categories']['time']:
                h=model.new_bool_var('common'); u=sum(x[p['id'],t] for p in people if c not in p['answers']['time'])
                model.add(u == 0).only_enforce_if(h); model.add(u >= 1).only_enforce_if(h.Not()); hs.append(h)
            hard(model.add(sum(hs) >= 1),f'{t}: 전원 공통 시간')
    if not scoring: return model,x,{},labels
    serial = [0]
    def var(lo=0,hi=10**12):
        serial[0]+=1
        return model.new_int_var(lo,hi,f'v{serial[0]}')
    def absolute(expr):
        out=var(); model.add_abs_equality(out,expr); return out
    def rounded_var(numer,denom):
        out=var(0,1000); num=var(); den=var(1)
        model.add(num == 2*numer+denom); model.add(den == 2*denom)
        model.add_division_equality(out,num,den); return out
    Lt=[]
    for t in tids:
        n=sizes[t]
        model.add(n >= 1)
        d=max(Fraction(N-K+1)-Fraction(N,K),Fraction(N,K)-1)
        sz=var(0,1000)
        model.add_allowed_assignments([n,sz],[(a,rounded(1000*abs(Fraction(a)-Fraction(N,K))/d) if d else 0) for a in range(1,N+1)])
        loss={'size':sz}
        for q in s['selected_questions']:
            if q == PERSONALITY:
                A=len(s['traits']); parts=[]
                for tr in s['traits']:
                    k=tr['size']; vals={p['id']:p['answers'][q][tr['id']] for p in people}
                    if s['method'] == 'balanced':
                        tsum=var(0,5*k*N); model.add(tsum == sum(vals[i]*x[i,t] for i in ids))
                        parts.append(rounded_var(250*absolute(tsum*N-sum(vals.values())*n),n*N*k*A))
                    else:
                        highs=[]; lows=[]
                        for i in ids:
                            h=var(0,5*k); l=var(1,5*k+1)
                            model.add(h == vals[i]*x[i,t]); model.add(l == vals[i]*x[i,t]+(5*k+1)*(1-x[i,t]))
                            highs.append(h); lows.append(l)
                        hi=var(k,5*k); lo=var(k,5*k)
                        model.add_max_equality(hi,highs); model.add_min_equality(lo,lows)
                        parts.append(rounded_var(250*(hi-lo),k*A))
                total_p=var(0,1000); model.add(total_p == sum(parts)); loss[q]=total_p
            elif q in ('role','interest','time'):
                cats=s['categories'][q]
                counts=[]; totals=[]
                for c in cats:
                    count=var(0,N)
                    selected=[p for p in people if (p['answers'][q] == c if q == 'role' else c in p['answers'][q])]
                    model.add(count == sum(x[p['id'],t] for p in selected)); counts.append(count); totals.append(len(selected))
                maximum=var(0,N); model.add_max_equality(maximum,counts)
                if q == 'time' or s['method'] == 'similar':
                    loss[q]=rounded_var(1000*(n-maximum),n)
                else:
                    mentions=var(1,N*len(cats)); model.add(mentions == sum(counts))
                    total=sum(totals)
                    dev=[absolute(c*total-C*mentions) for c,C in zip(counts,totals)]
                    loss[q]=rounded_var(500*sum(dev),mentions*total)
            else:
                values={p['id']:p['answers']['experience'] for p in people}
                if s['method'] == 'balanced':
                    exp=var(0,5*N); model.add(exp == sum(values[i]*x[i,t] for i in ids))
                    loss[q]=rounded_var(250*absolute(exp*N-sum(values.values())*n),n*N)
                else:
                    highs=[]; lows=[]
                    for i in ids:
                        h=var(0,5); l=var(1,6)
                        model.add(h == values[i]*x[i,t]); model.add(l == values[i]*x[i,t]+6*(1-x[i,t]))
                        highs.append(h); lows.append(l)
                    hi=var(1,5); lo=var(1,5)
                    model.add_max_equality(hi,highs); model.add_min_equality(lo,lows)
                    loss[q]=250*(hi-lo)
        L=var(0,1000*sum(s['weights'].values())); model.add(L == sum(s['weights'][q]*v for q,v in loss.items())); Lt.append(L)
    worst=var(); model.add_max_equality(worst,Lt)
    violations=[]
    for a,b in s['edges']:
        same=[]
        for t in tids:
            z=model.new_bool_var('edge'); model.add(z <= x[a,t]); model.add(z <= x[b,t]); model.add(z >= x[a,t]+x[b,t]-1); same.append(z)
        violations.extend(same)
    J=var(); model.add(J == 18*N*(3*K*worst+2*sum(Lt))+5000*K*sum(s['weights'].values())*sum(violations))
    mp=var(0,N); md=var(0,N)
    model.add(mp == sum(1-x[i,t] if t in tids else 1 for i,t in s['published'].items()))
    model.add(md == sum(1-x[i,t] if t in tids else 1 for i,t in s['draft'].items()))
    return model,x,{'pub':mp,'quality':J,'draft':md},labels


def solve(raw):
    """Never use this internal return value directly as an API response."""
    try:
        s=prepare(raw)
        model,x,obj,_=build(s)
        phases=['pub','quality','draft'] if s['published'] else ['quality']
        best=None; proof={'pub':False,'quality':False,'draft':False}; stages=[]
        class Observer(cp.CpSolverSolutionCallback):
            def on_solution_callback(self):
                nonlocal best
                assignment={i:t for (i,t),v in x.items() if self.value(v)}
                public,internal=assess(s,assignment)
                if internal is None or any(self.value(obj[k]) != internal[v] for k,v in [('pub','M_pub'),('quality','J_int'),('draft','M_draft')]):
                    raise RuntimeError('Independent verification failed')
                if best is None or internal['key'] < best[2]['key']:
                    best=(assignment,public,internal)
        for phase in phases:
            if best:
                if phase in ('quality','draft') and s['published']: model.add(obj['pub'] <= best[2]['M_pub'])
                if phase == 'draft': model.add(obj['quality'] <= best[2]['J_int'])
                model.clear_hints()
                for (i,t),v in x.items(): model.add_hint(v,int(best[0][i] == t))
            elif s['published']:
                for (i,t),v in x.items():
                    if i in s['published'] and s['published'][i] in {t['id'] for t in s['teams']}: model.add_hint(v,int(s['published'][i] == t))
            model.minimize(obj[phase]); solver=cp.CpSolver()
            solver.parameters.num_search_workers=1; solver.parameters.random_seed=s.get('seed',42)
            solver.parameters.max_deterministic_time=s.get('limit',10)
            status=solver.solve(model,Observer())
            stages.append({'phase':phase,'status':solver.status_name(status),'bound':solver.best_objective_bound,'candidate':solver.objective_value if status in (cp.OPTIMAL,cp.FEASIBLE) else None})
            if status == cp.MODEL_INVALID: raise RuntimeError('MODEL_INVALID')
            if status == cp.INFEASIBLE:
                if best: raise RuntimeError('Incumbent excluded by model')
                diag,_,_,labels=build(s,False,True)
                ds=cp.CpSolver(); ds.parameters.num_search_workers=1; ds.parameters.max_deterministic_time=s.get('limit',10)
                result=ds.solve(diag)
                if result in (cp.OPTIMAL,cp.FEASIBLE): raise RuntimeError('Scoring/diagnostic mismatch')
                if result == cp.MODEL_INVALID: raise RuntimeError('Diagnostic MODEL_INVALID')
                return {'status':'INFEASIBLE' if result == cp.INFEASIBLE else 'LIMIT_NO_CANDIDATE','stageProof':proof,'conflicts':[labels.get(i,'필수 조건') for i in ds.sufficient_assumptions_for_infeasibility()] if result == cp.INFEASIBLE else [],'internal':{'stages':stages}}
            proof[phase]=status == cp.OPTIMAL
            if status == cp.OPTIMAL: model.add(obj[phase] == round(solver.objective_value))
        if not best: return {'status':'LIMIT_NO_CANDIDATE','stageProof':proof,'conflicts':[],'internal':{'stages':stages}}
        public,check=assess(s,best[0])
        if check is None or check['key'] != best[2]['key']: raise RuntimeError('Final verification failed')
        return {'status':'OPTIMAL' if all(proof[p] for p in phases) else 'FEASIBLE','stageProof':proof,'assignments':best[0],**public,'conflicts':[],
                'internal':{**check,'stages':stages,'engineVersion':ENGINE_VERSION,'solverVersion':ortools.__version__,'seed':s.get('seed',42),'scoreEncoding':'linear-rational-division'}}
    except Exception as e:
        return {'status':'ERROR','stageProof':{'pub':False,'quality':False,'draft':False},'conflicts':[], 'internal':{'errorType':type(e).__name__,'error':str(e)}}
