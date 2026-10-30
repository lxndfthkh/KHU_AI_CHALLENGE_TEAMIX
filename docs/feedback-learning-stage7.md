# 7단계: 학습·검증·모델 승인

기준: 편성학습_v3 8·10장, 개발단계 가이드 7단계. 언어 AI는 필요 없다(태그 보조 모델만 데이터 없음으로 건너뜀).

## 학습 (algorithm/learning/train.py, Cloud Run 작업 `python -m learning.train`)
- 언제: 매월, 또는 마지막 학습 뒤 행이 10개 이상 늘었을 때. `--force`로 즉시.
- 최소 조건 ✅: 행 30개 이상, 서로 다른 소모임 5개 이상. 미달이면 `trainingRuns`에 `insufficient_data`만 남긴다.
- 특성: `loss_*`(5), `active_*`(4), `teamSize`, 편성 방식·소모임 종류 원-핫. 표준화.
- 목표 `y_overall`, 표본 가중치 `n_reviews`. Ridge, alpha ∈ {0.1, 1, 10, 100}을 소모임 단위 5겹 교차 검증으로 고른다.
- 중요도 `s_q = max(0, −β_q)`, 소모임 단위 부트스트랩 200회, 80% 구간이 0을 포함하면 `b_q = 1`.
- `b_q = clip(1 + λ(s_q/mean(s) − 1), 0.5, 2.0)`, `λ = min(1, 행 수/100)`. 구간 판정은 마지막에 덮어쓴다(평균 s에는 모든 기준이 들어간다).
- 같은 데이터·시드면 같은 결과(행 순서와 무관).

## 검증 (10장)
- 기준 1: 평균만 예측, 기준 2: v3 기본 가중치로 계산한 팀 가중 손실 하나만 쓴 회귀. 6단계 행에 활동별 기본 가중치 `weight_*` 열을 추가했다.
- 후보 조건: 학습 모델의 가중 RMSE가 두 기준보다 모두 5% 이상 낮음. 아니면 `not_better_than_baselines`로 기록만 하고 모델을 만들지 않는다.
- 보조 모델(보고서 전용): `y_schedule`, `y_roles`, `y_rejoin`, 기준 연결 태그 부정 비율. 태그는 `n_comments ≥ 2` 행만, 부족하면 건너뜀. `b_q > 1.1`인데 연결 태그 모델에서 손실 계수가 0 이하면 `directionMismatches`에 표시.
- 최근 소모임 3개 재편성 검사는 엔진이 보정 가중치를 받아야 하므로 8단계에서 한다(`reformationCheck: "stage8"`).

순수 잡음 데이터에서도 80% 구간 때문에 기준 하나쯤은 우연히 "확실"로 나올 수 있다(약 1/5). 그래서 후보 조건(5%)이 최종 관문이고, 테스트로 확인했다.

## 승인 (functions/src/models.js) — 서비스 관리자만 (Auth 커스텀 클레임 `admin: true`)
| 명령 | 상태 |
|---|---|
| approveModel | candidate → approved |
| activateModel | approved 또는 retired → active. 기존 active는 retired. `appConfig/learning`에 `activeModelId`, `b` |
| deactivateModel | active → retired, `activeModelId = null` (기본 가중치) |

되돌리기 = 이전 모델을 다시 activate 하거나 deactivate. 학습 작업은 후보까지만 만들고 절대 적용하지 않는다.

## 검증 (2026-10-30, 실제 실행)
- `algorithm/tests/test_train.py` 9개 (순수 7 + 에뮬레이터 2), Python 전체 110개
- `functions/test/models.emulator.test.js` 4개, functions 에뮬레이터 전체 24개
- 규칙 테스트 16개: 학습 데이터·모델·실행 기록은 임원진도 못 읽음, `appConfig/learning`은 로그인 사용자 읽기

| 가이드 기준 | 테스트 |
|---|---|
| 팀 30개·소모임 5개 미만이면 학습하지 않음 | `test_too_little_data_does_not_train`, `test_insufficient_data_is_logged_without_a_model` |
| 공통 시간 ↑ → 만족 ↑ 관계를 넣으면 `b_time > 1` | `test_planted_time_effect_gives_b_time_above_one` |
| 후보 → 승인 → 적용 → 되돌리기 | `candidate -> approved -> active`, `one active model ... rollback` |
| admin 클레임이 아니면 승인 불가 | `only a service admin ...` |

이 결과는 연결이 작동한다는 확인이지 만족도 개선의 입증이 아니다.

## 남은 일
- 8단계: 엔진이 `appConfig/learning.b`로 가중치 보정(순위 유지), 재편성 검사
- 관리자 화면, Cloud Run 작업·Scheduler 배포, 서비스 관리자 클레임 부여 절차
