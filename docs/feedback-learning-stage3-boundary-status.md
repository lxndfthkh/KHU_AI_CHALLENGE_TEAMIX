# 편성학습 v3: 편성 API 경계 보완 상태

## 기준
- 확인한 main HEAD: `107775b84cfd8ba65062aeca12f667ae754823a2`.
- 이 커밋은 작업 브랜치 `13fc4778bf57b9a0a892420b08205912f21696c0`의 조상에 포함되어 추가 병합할 main 변경이 없었음.
- 기존 Flutter 저장 구조와 어댑터를 유지한다. 이 변경은 1~3단계 전체 완료 선언이 아니다.

## 변경
- 운영 API가 ValidatedFormationService를 사용하도록 연결.
- 서비스 진입점에서 로그인, 역할, 요청 구조, 재편성 종류와 범위를 검사.
- 모집 중 설정 변경 허용, 공개 후 설정 변경 차단.
- 솔버 결과의 배정과 공개 지표를 독립 검증/재계산.
- 원본 솔버 충돌 문자열과 비정상 stageProof를 공개 응답/formationRuns로 복사하지 않음. INFEASIBLE은 일반 공개 안내로 대체.
- 솔버 예외/잘못된 배정은 ERROR로 반환하고 기존 초안을 보존.

## 실제 실행한 테스트
`cd algorithm && python -m unittest discover -s tests -p 'test_main_adapter.py' -v`
`cd algorithm && python -m unittest discover -s tests -p 'test_stage3_boundary.py' -v`

두 대상에 해당하는 로컬 테스트를 함께 실행: 기존 어댑터 8개 + 경계 회귀 23개 = 중복 없는 31개 통과.
STALE 테스트는 메모리 저장소에서 명단/설정/초안/응답/선호/비공개 버전이 실행 도중 바뀌는 경우를 주입했다. 실제 Firestore 재시도/동시성 검증은 아니다.
기존 test_engine.py 전체, Firebase Rules 에뮬레이터, Flutter 통합, 실제 인증/Cloud Run 배포는 이번 검증에 포함하지 않았다.

## 13-1 사례 검증 (step-3-claude)
운영 경로(`formation.py`, `service.py`, `repository.py`)에서 편성알고리즘 v3 13-1 사례 1~22를 번호별로 검증했다.

| 13-1 | 테스트 |
|---|---|
| 1 기본 편성 | `test_spec_13_1.test_01_basic_twenty` |
| 2 부분 재편성 | `test_02_partial_keeps_outside_scope_and_manual_lock` |
| 3 최소 변경 | `test_03_minimum_change_new_participant_fills_open_seat` (전수 탐색 비교) |
| 4 품질 우선 | `test_04_quality_before_draft` (전수 탐색 비교) |
| 5 초안 존중 | `test_05_draft_respected_among_quality_ties` |
| 6 필수 역할 충돌 | `test_06_required_role_conflict_is_infeasible`, 사전 검사 `test_precheck_role_shortage` |
| 7 비공개 선호 충돌 | `test_07_private_preference_blocked_by_lock_does_not_block`, `test_07_service_lock_with_private_preference_still_publishes` |
| 8 버전 변경 | 메모리: `test_stage3_boundary.test_stale_*` 6개 / 실제 Firestore: `test_firestore_emulator.test_*_stale*` 2개 |
| 9 탐색 한도 | `test_09_limit_without_candidate_is_not_conflict`, `test_stage3_boundary.test_failed_solver_keeps_previous_draft` |
| 10 수동 수정 | `test_10_manual_edit_recomputes_public_metrics_and_required_status` |
| 11 정원 기본값 | `test_11_default_capacity_is_upper_bound_ceil_n_over_k` |
| 12 정원 자동 변경 금지 | `test_12_capacity_not_changed_when_roster_grows` |
| 13 재현성 | `test_13_reproducible` |
| 14 단계별 최적성 | `test_14_feasible_stage_never_reported_optimal`, `test_14b_status_matches_stage_proofs` |
| 15 후보 보존 | `test_15_and_21a_limit_in_later_stage_keeps_incumbent` |
| 16 비공개 선호 비포화 | `test_16_private_loss_not_saturated` (V=6 vs V=10) |
| 17 진단 분리 | `test_17_scoring_infeasible_but_diagnostic_feasible_is_error` |
| 18 후속 단계 비악화 | `test_18_final_candidate_not_worse_than_any_stage_candidate`, `test_18b_small_instance_matches_exhaustive_lexicographic_optimum` |
| 19 이동 0명 정책 | `test_19_zero_move_policy_keeps_valid_publication`, `test_19_zero_move_notice` |
| 20 정원 없음 | `test_20_uncapped_team_is_not_hidden_capacity`, `test_20_precheck_with_uncapped_team` |
| 21 오류 구분 | `test_15_and_21a_*`, `test_21b_solver_exception_blocks_candidate`, `test_21c_verifier_mismatch_blocks_candidate` |
| 22 팀 수 변경 | `test_22_team_add_delete_keeps_ids`, `test_22b_*`, `test_22_deleted_team_moves_reported_and_locks_conflict` |

추가: `b_q = 1` 가중치 ×10 동일 결과(`test_weights_times_ten_same_result`), 운영진이 읽는 기록·응답에 비공개 값 없음(`test_private_values_never_reach_operator_records`).

### 실제 에뮬레이터 검증 (`test_firestore_emulator.py`)
- 실제 Firestore 트랜잭션으로 실행·초안 적용·공개
- 탐색 중 응답 수정, 비공개 선호 철회 → STALE, 초안 미적용
- `server_v3` HTTP: 토큰 없음·잘못된 토큰 401, 참가원 403, 임원진 200, 응답에 비공개 값 없음
- demo- 프로젝트 ID에서만 실행되며 실제 Firebase 프로젝트에 접근하지 않음

### 코드 변경
- 사전 검사(12-1)에 역할 희망자 부족, 선택 범위 남은 자리 부족 추가
- 이동 0명 안내 문구를 명세 9-2 문장으로 변경

### 실행
```bash
cd algorithm && python3.12 -m venv .venv && .venv/bin/pip install -r requirements-stage3.txt
.venv/bin/python -m unittest discover -s tests -v          # 에뮬레이터 테스트 5개는 건너뜀
cd .. && npx firebase emulators:exec --only firestore,auth --project demo-teamix-stage3 \
  "cd algorithm && .venv/bin/python -m unittest discover -s tests -v"   # 83개 전체
```
OR-Tools 9.14.6206은 Python 3.14 휠이 없으므로 3.11~3.12를 쓴다. Firestore 에뮬레이터는 Java가 필요하다.

### 결과 (2026-10-30)
- Python 83개 통과 (기존 45 + 13-1 33 + 에뮬레이터 5)
- 루트 Rules 테스트 `npm run test:rules` 24개 통과
- `functions` 단위 테스트 14개 통과

## 남은 완료 조건
- `functions/test/rules.test.cjs` 9개 중 5개 실패. 이번 변경 전 커밋(1f3467d)에서도 같은 5개가 실패한다. 원인: d0cee67에서 `firestore.rules`를 main 버전으로 바꿨지만 이 테스트는 1~2단계 설계의 경로·필드를 기대한다. 1~2단계 스키마(main 기준 vs 편성학습_v3 기준) 결정 후 정리 필요.
- 소모임 단위 비공개 선호 저장/상태 제한/서버 전용 prefVersion 및 앱 계약 변경.
- 개인 answerVersion과 응답 수정 시 버전 증가 규칙 정합성.
- 앱의 초안/공개 직접 쓰기를 서버 경로로 전환한 후 Rules 강화 및 에뮬레이터 검증.
- Flutter 앱에서 인증된 편성 API 호출 통합 검증.
- INFEASIBLE 시 운영진 안내는 일반 문구로만 제공한다(12-3의 구체 문장 변환은 미구현).

배포하지 않았으며 운영 데이터 마이그레이션도 수행하지 않았다.
