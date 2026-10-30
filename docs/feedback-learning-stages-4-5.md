# 4단계: 활동 진행·후기 (main 스키마) — 5단계(자유 서술 태깅)는 없음

기준: 편성학습_v4 1-3·3·4-1·12장, 개발단계 가이드 4단계. 저장 구조는 main `docs/FIRESTORE.md`를 따르고, 없는 필드만 추가했다(`firestore.schema.json`에 기록).

> 2026-10-30 결정: 후기에서 자유 서술을 받지 않는다. 그래서 언어 AI를 쓰지 않고 5단계(태깅)가 없다. 파일 이름은 기존 링크를 위해 그대로 둔다.

## 명령 (functions/src/activity.js)

| 명령 | 누가 | 하는 일 |
|---|---|---|
| startActivity | 임원진 | `closed` + 공개됨 → `active`, `startedAt` |
| endActivity | 임원진 | `active` → `ended`, `endedAt`, `endedVersion`(그때의 공개 버전). 종료 버전에 속한 사람에게 `feedbackRequested` 알림 |
| submitFeedback | 종료 버전에 속한 승인 회원 | `feedback/{a}_{uid}` 저장·수정(후기 마감 전까지), 팀 집계 갱신. 자유 서술이 오면 거부 |
| closeFeedback | 임원진 | `feedbackClosedAt` 기록 |
| setLearningConsent | 본인 | `consents/{uid}.learning` (문구 버전 `l2`) |
| closeExpiredFeedback (예약) | 서버 | 종료 7일 뒤 자동 마감. 에뮬레이터에서는 예약이 자동 실행되지 않으므로 시연에서는 closeFeedback을 쓴다 |

- 상태는 앞으로만: recruiting → closed → active → ended (+ `feedbackClosedAt`). main의 status 값은 바꾸지 않았고, 명세의 `review_closed`는 `feedbackClosedAt`으로 표현한다.
- 후기 연결(3-2): 팀은 `endedVersion` 공개 버전에서 서버가 정한다. 앱이 보낸 팀·버전은 무시한다.
- `membershipRatio`: 활동 기간(`startedAt`~`endedAt`) 중 그 팀(팀 ID 기준)에 있던 시간 비율. 공개 버전의 `validFrom`/`validTo`로 계산한다(3단계가 공개할 때 기록).
- 후기 문항 `r2`: overall·schedule·roles·rejoin (1~5, 모두 필수). main의 `rating` = overall.
- 동의: 작성할 때의 동의 값을 `learningConsent`로 복사한다. 동의를 바꾸면 그 뒤에 쓰거나 고친 후기부터 적용된다.
- 임원진에게 보이는 것: `activities/{a}/feedbackSummary/current`의 팀별 점수 평균뿐. 응답자 3명 미만 팀은 넣지 않는다. 개별 후기는 main 규칙상 작성자만 읽는다.

## 검증 (2026-10-30, 실제 실행)
```sh
cd functions
npm test               # 15개: 1~2단계 검증 13 + 4단계 순수 로직 2
npm run test:emulator  # 21개: 1~2단계 9 (1~4단계 끝까지 포함) + 4단계 7 + 모델 승인 5
cd .. && npm run test:rules   # 16개
```

| 가이드 기준 | 테스트 |
|---|---|
| 상태가 정해진 순서로만 | `4: state only moves forward ...` |
| ended 진입 시 종료 버전 기록 | `4: ending records endedVersion ...` |
| 활동 중 재공개가 있어도 종료 버전에 연결, membershipRatio | `4: feedback links to the ending version ...`, `membershipRatio` 순수 테스트 |
| 임원진이 개별 후기를 못 읽음 | `4: summary only for teams with 3+ ...` (main 규칙으로 실제 읽기 시도) |
| 응답자 3명 미만 팀은 집계 없음 | 같은 테스트 + `summary` 순수 테스트 |

배포하지 않았다.
