# 6단계: 학습 데이터 추출 (main 스키마)

기준: 편성학습_v3 6장, 개발단계 가이드 6단계. 코드: `algorithm/learning/extract.py`, 실행 이미지: `algorithm/Dockerfile.learning`.

## 언제
후기가 마감되고(`feedbackClosedAt`) 태깅이 끝나면 팀 집계(`feedbackSummary/current.updatedAt`)가 갱신된다. 추출 작업은 마감된 소모임 중 **처음이거나 집계가 바뀐 것**만 다시 뽑는다. 언어 AI가 아직 없어도 돌아가며, 나중에 태깅되면 집계가 바뀌어 자동으로 다시 뽑힌다.
```sh
python -m learning.extract              # 대상 전체 (Cloud Run 작업, 예: 매시간)
python -m learning.extract --activity A # 한 소모임
```

## 한 행 = 종료 시점 공개 버전의 한 팀
- 저장: `trainingDatasets/fx1/rows/{a}_v{n}_{teamId}` (서버 전용)
- 열: 편성학습_v3 6장 그대로. `loss_*` = 공개 문서의 `losses` / 1000 (3단계 독립 검증기가 계산한 값), 쓰지 않은 기준은 0
- `tagrate_*`: 포함된 후기 중 태그가 붙은 후기 기준 비율. 태그된 후기가 없으면 null
- `activityType`: main에 소모임 종류 필드가 없어 지금은 null (schema.json에 선택 필드 `type`으로 적어 둠)

## 포함 조건 (✅ 확정값)
- 후기: `learningConsent == true` 그리고 `membershipRatio ≥ 0.5`
- 행: 포함 후기 ≥ 2 그리고 응답률 ≥ 0.5
- 다시 뽑을 때 조건을 못 채우게 된 행은 지운다

## 넣지 않는 것
사용자 ID, 응답 값, 비공개 선호, 내부 점수, 자유 서술 원문, 이름. `sourceRefs`는 후기 경로의 SHA-256이라 uid가 드러나지 않으며, 9단계 삭제 처리에서 같은 방식으로 찾는다.

## 검증 (2026-10-30, 실제 실행)
`algorithm/tests/test_extract.py` 10개 (순수 7 + 에뮬레이터 3), Python 전체 101개 통과.

| 가이드 기준 | 테스트 |
|---|---|
| 같은 팀 버전에서 `loss_*`가 `teams.losses`와 같음 | `test_losses_equal_publication_and_independent_verifier` (공개 문서 값 + 엔진 검증기 재계산 둘 다와 비교) |
| 동의하지 않은 후기, 소속 기간 0.5 미만 후기 제외 | `test_unconsented_and_short_membership_reviews_excluded` |
| 응답 2명 미만 / 응답률 50% 미만 팀 제외 | `test_rows_need_two_reviews_and_half_response` |
| 개인 ID·원문·비공개 선호 없음 | `test_no_personal_data_in_rows` |

## 남은 일
- Cloud Run 작업과 Cloud Scheduler 배포 (개발 프로젝트에서 확인 후)
- 7단계: 이 행들로 학습·검증·관리자 승인
