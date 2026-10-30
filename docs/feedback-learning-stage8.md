# 8단계: 학습 보정 → 편성 엔진

기준: 편성학습_v4 9·10장, 개발단계 가이드 8단계.

## 가중치 (algorithm/formation.py `learned_weights`)
1. `b_q`: 적용 중인 모델(`appConfig/learning.activeModelId`, `b`)이 있고 소모임 스위치(`settings/matching.learningEnabled`, 기본 true)가 켜져 있으면 그 값, 아니면 모두 1
2. `w'_q = round(10 × w_q × b_q)` (0.5 올림), `w_q = m − r + 1`
3. 순위 유지: 우선순위 순서대로 `w'_r = min(w'_r, w'_(r−1))` — 임원진 순서는 절대 뒤집히지 않는다. 위 기준을 아래 기준과 같은 수준까지 낮출 수는 있다
4. `w'_q ≥ 1`, 보정 계수는 0.5~2.0만 받는다(벗어나면 입력 오류)

모델이 없으면 모든 가중치가 v3의 정확히 10배라 편성 결과가 v3와 같다(테스트로 확인).

## 서비스 (service.py, repository.py)
- 실행 기록 `formationRuns`에 `weightsUsed`(실제 정수 가중치)와 `modelId`, `serverRuns` 스냅샷에 `weightFactors`
- `/precheck` 응답의 `learning`: `{enabled, modelId, directions}` — 기준별 `up`(b>1.1) / `down`(b<0.9) / `same`. 계수 값과 학습 데이터는 보여주지 않는다
- `/updateMatchingSettings`의 `patch.learningEnabled`로 소모임별 끄기
- 실행 도중 적용 모델이 바뀌면 STALE (스냅샷 비교에 포함)
- 이미 공개된 팀은 모델이 바뀌어도 건드리지 않는다. 모델 적용·해제 명령은 공개·초안 문서를 쓰지 않고, 이후 재편성도 공개 이동 최소화가 먼저다

## 재편성 검사 (learning/train.py `reformation_check`, 7단계 후보 조건)
후보 모델이 나오면 최근 소모임 3개의 마지막 유효 실행 스냅샷(`serverRuns`)을 처음 편성처럼 `b`를 넣어 다시 돌린다. 필수 조건 충족 + 30초 이하가 아니면 `failed_reformation_check`로 후보에서 뺀다. 보고서에는 상태·팀 크기·시간만 남긴다.

## 검증 (2026-10-30, 실제 실행)
`algorithm/tests/test_stage8.py` 14개 + `functions/test/models.emulator.test.js`의 8단계 확인 1개.

| 가이드 기준 | 테스트 |
|---|---|
| 모델이 없을 때 3단계와 같은 결과 | `test_without_model_weights_are_ten_times_v3_and_result_is_the_same` |
| 보정 후에도 우선순위 순서가 안 뒤집힘 | `test_priority_order_is_never_reversed` (무작위 2,000회), `test_spec_examples` |
| `weightsUsed`, `modelId` 기록 | `test_run_records_weights_used_and_model_id` |
| 소모임 끄기 스위치 | `test_activity_switch_off_uses_default_weights`, `test_switch_*` |
| 공개된 팀은 모델이 바뀌어도 다시 편성 안 됨 | `test_published_teams_are_not_re_formed_when_a_model_arrives`, functions `8: activating ... never touches published teams` |

추가: `test_factors_change_the_trade_off` — 같은 8명에서 기본 가중치는 역할 손실 0·시간 손실 500, 역할 `b=0.5`면 역할 500·시간 0. 보정이 실제로 결과를 바꾼다.

전체 (에뮬레이터 포함): Python 123개, functions 단위 15·에뮬레이터 21, 규칙 16, Flutter analyze 문제 없음·테스트 26.
