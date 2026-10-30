# TEAMIX 편성 엔진 — 편성알고리즘 v3

`편성알고리즘_v3.md`의 편성 엔진(처음 편성·부분 재편성·공개 후 재편성)과 `편성학습_v3.md` 9장 가중치를 구현한 Python(OR-Tools CP-SAT) 엔진입니다. Flutter 앱·Firestore·Cloud Run과는 연결하지 않았습니다(아래 "범위 밖").

## 실행

Python 3.11~3.13 (고정한 `ortools==9.14.6206`에는 3.14용 배포판이 없음). algorithm 폴더에서:

```bash
python -m pip install -r requirements.txt
python -m teamix_engine examples/initial_20.json --public-output run/public.json --internal-output run/internal.json
python -m unittest discover -s tests -v
```

종료 코드: OPTIMAL/FEASIBLE은 0, 그 밖은 1. 공개 출력과 내부 기록은 반드시 다른 파일이며 내부 파일은 0600 권한으로 씁니다. `solve()` 반환값 전체를 클라이언트에 보내지 마세요. `public`만 임원진에게 보일 수 있는 값입니다.

## API

| 함수 | 용도 | 대응 |
|---|---|---|
| `solve(snapshot, cache=None)` | 편성 실행 → `{"public", "internal"}` | `/run`, v3 11장 |
| `run_precheck(snapshot)` | 사전 검사만 → `{"ok", "issues": [{kind, message}]}` | `/precheck`, v3 12-1 |
| `evaluate(normalize(snapshot), assignment)` | 수동 수정 후 공개 지표·필수 조건 위반 (미배정 허용, 비공개 항목 없음) | `/draft/edit`, v3 13-1 #10 |

## 입력 스냅샷 (v3 2장)

전체 예시는 `examples/initial_20.json`.

| 키 | 내용 |
|---|---|
| `mode` | `initial`(공개 전) 또는 `republish`(공개 후) |
| `participants` | `{id, answers}`. 답변 키 `role`(단일), `time`·`interest`(복수, 최소 1개), `experience`(1~5) |
| `setup` | 편성 설정 ① `{team_count, max_per_team, total_invites}`. 생략 가능. 아래 "편성 설정" 참고 |
| `teams` | `{id, capacity}`. `capacity: null` = 정원 없음(3-1). 엔진은 정원을 바꾸지 않음. `setup`이 있으면 생략 가능 |
| `selected_questions`, `priority`, `method` | 사용할 질문, 우선순위(`size` 포함, 기본 순서는 5장), `balanced`/`similar` |
| `required_roles`, `require_common_time` | 추가 필수 조건 |
| `fixed` | 수동 고정 `{participant, team}` 목록 |
| `draft` | 작업 초안 `{assignments: {uid: teamId\|null}, locks: {uid: {team, type: manual\|default}}}` |
| `scope_team_ids` | 재편성 범위(생략 = 전체). 일부만이면 `draft` 필요 |
| `published` | (republish) `{team_ids, assignments}` 현재 공개 배정 |
| `deleted_team_ids` | (republish) 운영진이 고른 삭제 팀 (3-2) |
| `private_preferences` | `{source, target, confirmed, withdrawn?}`. 확인된 활성 관계만, 방향 제거·중복 통합, 1인당 2명 |
| `learning` | `{multipliers: {기준: b_q}, model_id}` 생략 시 모든 `b_q = 1`. 범위 0.5~2.0 |
| `versions`, `solver` | 기록용 버전, `{seed(42), max_deterministic_time(단계별, 10)}` |

## 구현한 v3 규칙

- **필수 조건(3장):** 정확히 한 팀, 빈 팀 없음, 최대 정원, 고정, 필수 역할, 전원 공통 시간(10-2).
- **고정 적용(3장):** 수동 고정은 항상 유지, 범위 밖 팀의 배정은 고정, 범위 안의 기본 고정은 해제, 고정되지 않은 참가자(신규·삭제 팀 소속 포함)는 범위 안 팀에만 배정. 명단에 없는 배정은 버림(탈퇴자).
- **손실(4장):** 0~1,000 정수, 유리수로 계산해 마지막에 한 번 반올림(절반은 올림).
- **가중치(편성학습 9장):** `w' = round(10·w·b)`, 순위 유지 `w'_r ≤ w'_(r−1)`, 최소 1. `weights_used`로 기록. 솔버에는 `w'`를 공약수로 나눈 값을 넣어, `b = 1`이면 v3 원래 가중치(5~1)와 **같은 모델**이 됩니다(목적식이 양의 상수배만 다름). `J_int`는 `w'` 기준입니다.
- **목적식(6~8장):** `F_int = 3K·max L + 2·ΣL`, `J_int = 18N·F_int + 5000·K·W·V`.
- **점수표(10-1, 3-1):** 팀 인원 1 ~ U_t를 빠짐없이 만들고, `U_t`는 고정을 반영한 실제 가능한 최댓값입니다. 표가 `TABLE_LIMIT`(100,000행)을 넘으면 **그 팀·항목만 정확한 선형화**(반올림까지 같은 정수 제약)로 바꾸고 `internal.linearized`에 기록합니다.
- **단계별 최적화(9장):** 처음 편성은 `J_int` 한 단계. 공개 후는 `M_pub → J_int → M_draft`. 모든 단계에서 찾은 후보를 독립 검증기로 다시 계산해 사전식 키로 **현재 최선 후보**를 유지하고(9-1), 다음 단계 제한은 그 값입니다. 공개 배정은 1단계 힌트(10-3)로 넣습니다.
- **증명 기록(9-3):** `stage_proof = {pub, quality, draft}`. 최종 후보 값이 그 단계의 증명된 최적값과 같을 때만 `true`. 모두 `true`일 때만 OPTIMAL입니다.
- **안내 문구:** 기존 참가자 이동 0명이면 9-2 안내. 공개 이동 최소가 증명되지 않으면 "탐색한 후보 중 이동이 가장 적은 안입니다." 삭제 팀 소속 이동은 "팀 삭제로 인한 이동 n명"으로 따로 표시합니다.
- **결과 상태(11장):** OPTIMAL / FEASIBLE / INFEASIBLE / LIMIT_NO_CANDIDATE / ERROR. 탐색 한도로 끝나면 후보를 보존하고, 솔버 예외·MODEL_INVALID·편성/진단 모델 불일치·독립 검증 실패·뒤 단계의 모순은 **적용 차단(ERROR)** 합니다(11-1). ERROR는 원인 없이 "처리 중 오류가 발생했습니다."만 공개합니다.
- **사전 검사(12-1):** 9종 전부(참가자 < 팀, 전체 정원(정원 없는 팀이 있으면 생략), 고정 > 정원, 동일인 고정 중복, 역할 희망자 부족, 선택 범위 정원 부족, 응답 누락(질문별 인원), 삭제 팀 수동 고정, 새 팀이 범위 밖). 추가로 범위 밖 빈 팀과, `setup.total_invites`보다 참가자가 많은 경우(`invite_total`)를 안내합니다.
- **편성 설정 `setup`:** 임원진이 처음에 정하는 세 값입니다.
  - `team_count`: 팀 수(1~100, 필수)
  - `max_per_team`: 팀별 최대 인원(1 이상, `null` = 제한 없음)
  - `total_invites`: 소모임 총 초대 인원(1 이상, `null` = 제한 없음)

  `teams`가 없으면 `team_1 … team_K`를 만들고 정원을 `max_per_team`으로 둡니다. `teams`가 있으면 개수가 `team_count`와 같아야 하고, 정원이 `null`인 팀에는 `max_per_team`을 채우며, 그보다 큰 정원은 입력 오류입니다. 설정 자체의 모순(`total_invites < team_count`, `total_invites > team_count × max_per_team`)은 참가자와 상관없이 입력 오류(ERROR)로 막습니다. 참가자가 `total_invites`를 넘는 것은 사전 검사 충돌(INFEASIBLE)입니다. 입력 검사를 통과하면 결과의 `public.setup`에 받은 값을 그대로 돌려줍니다.
- **충돌 진단(10-5, 12-2):** 필수 조건만 있는 진단 모델에서 정원·수동 고정·필수 역할·재편성 범위·공통 시간에 가정 리터럴을 붙여 충돌 집합을 구하고, 진단 한도 안에서 하나씩 빼 보며 불필요한 조건을 지웁니다. 비공개 선호는 넣지 않습니다.
- **재현성(10-4):** 작업자 1, 시드 고정, ID 정렬, 결정적 연산량 한도. `solve(..., cache=dict)`로 같은 실행 입력(`run_id` 제외) 결과를 재사용합니다. ERROR는 저장하지 않습니다.
- **노출 금지(7장):** `public`에 V·P·J_int·비공개 선호 관련 값과 오류 원인이 없습니다. 비공개 선호 입력 오류도 일반 오류로만 안내합니다.

## 명세 해석 (명세에 직접 정의가 없어 택한 것)

- **응답 누락이 있는 스냅샷으로 `solve()`를 부르면** 탐색하지 않고 `ERROR` + 질문별 누락 안내를 돌려줍니다. v3 4장은 이를 "설정 검증"에서 처리할 입력 문제로 두고 11장의 탐색 결과에는 해당 상태가 없습니다. 정상 흐름에서는 `run_precheck()`가 먼저 잡습니다.
- 사전 검사에서 걸리는 조건 충돌은 계산으로 불가능이 확정되므로 `INFEASIBLE`로 돌려줍니다.
- 진단 모델이 한도 안에 불가능을 다시 확인하지 못하면 `ERROR`로 처리합니다(INFEASIBLE은 진단 재확인이 전제).
- 공개 전에 초안이 있어도(부분 재편성 포함) v3 9장대로 `J_int` 한 단계만 실행합니다.

## 13-1 검증 사례

`tests/test_engine.py`의 테스트 이름 번호가 13-1 번호입니다. 엔진 단계에서 확인할 수 있는 21개(1~7, 9~22)를 테스트합니다. **#8(탐색 중 버전 변경 → STALE)은 Firestore 트랜잭션에서 판정하는 편성 서비스의 몫**이라 이 엔진 테스트에 없습니다. 그 밖에 선형화 정확성, 가중치 ×10 동등성, 사전 검사, 응답 누락 테스트가 있습니다. 실행 결과는 `test_results.txt`.

## 범위 밖 (아직 구현하지 않음)

- 편성 서비스(편성학습 4-2): `/precheck`, `/run`, `/draft/edit`, `/publish`, `/draft/discard` 엔드포인트, Firebase ID 토큰·임원진 확인, `formationRuns`/`serverRuns` 저장, STALE 트랜잭션, 재공개 알림 판정
- 정원 기본값 ⌈N/K⌉ 채우기(편성학습: `forming` 진입 시 서버가 한 번), Firestore 응답 형식(`questionId → {questionVersion, value}`)을 이 입력 형식으로 바꾸는 변환
- 13-2 비교 실험, 60:40·90:10·5~1·지목 상한의 조정, 품질 우선 재편성 모드, 균등 인원 보장 옵션, 집중 지목 대응(v3 16장 남은 결정)

## 예제 결과

`examples/result_public.json`, `examples/result_internal.json`은 이 저장소의 가상 20명·4팀 데이터로 실행한 결과입니다(OR-Tools 9.14.6206, 작업자 1, 시드 42, 한도 10, macOS arm64). 결과는 **FEASIBLE**(최적성 미증명)입니다. 같은 입력이라도 실행 환경이 다르면 다른 후보가 나올 수 있습니다(v3 10-4). 내부 기록 파일은 가상 데이터 전용이며, 실제 서비스의 비공개 정보는 Git에 커밋하면 안 됩니다.
