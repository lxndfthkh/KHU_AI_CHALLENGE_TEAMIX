# 4~5단계: 활동 진행·후기·자유 서술 태깅 (main 스키마)

기준: 편성학습_v3 1-3·3·4-1·7·12장, 개발단계 가이드 4·5단계. 저장 구조는 main `docs/FIRESTORE.md`를 따르고, 없는 필드만 추가했다(`firestore.schema.json`에 기록).

## 4단계 명령 (functions/src/activity.js)

| 명령 | 누가 | 하는 일 |
|---|---|---|
| startActivity | 임원진 | `closed` + 공개됨 → `active`, `startedAt` |
| endActivity | 임원진 | `active` → `ended`, `endedAt`, `endedVersion`(그때의 공개 버전). 종료 버전에 속한 사람에게 `feedbackRequested` 알림 |
| submitFeedback | 종료 버전에 속한 승인 회원 | `feedback/{a}_{uid}` 저장·수정 (후기 마감 전까지), 팀 집계 갱신 |
| closeFeedback | 임원진 | `feedbackClosedAt` 기록 → 태깅 시작 |
| setLearningConsent | 본인 | `consents/{uid}.learning` |
| closeExpiredFeedback (매시간) | 서버 | 종료 7일 뒤 자동 마감 |

- 상태는 앞으로만 진행: recruiting → closed → active → ended (+ `feedbackClosedAt`). main의 status 값은 바꾸지 않았고, 명세의 `review_closed`는 `feedbackClosedAt`으로 표현한다.
- 후기 연결(3-2): 팀은 `endedVersion` 공개 버전에서 서버가 정한다. 앱이 보낸 팀·버전은 무시한다.
- `membershipRatio`: 활동 기간(`startedAt`~`endedAt`) 중 그 팀(팀 ID 기준)에 있던 시간 비율. 공개 버전의 `validFrom`/`validTo`로 계산한다(3단계가 공개할 때 기록).
- 후기 문항 `r1`: overall·schedule·roles·rejoin(1~5, 필수) + comment(선택, 최대 1,000자). main의 `rating` = overall.
- 동의: 작성할 때의 동의 값을 `learningConsent`로 복사한다. 동의를 바꾸면 그 뒤에 쓰거나 고친 후기부터 적용된다.
- 임원진에게 보이는 것: `activities/{a}/feedbackSummary/current`의 팀별 평균과 태그 수뿐. 응답자 3명 미만 팀은 아예 넣지 않는다. 개별 후기는 main 규칙상 작성자만 읽는다.
- 화면용 집계에는 동의 여부·소속 기간과 관계없이 모든 후기를 넣는다(학습 포함 조건은 6단계에서 적용).

## 5단계 태깅 (functions/src/tagging.js)

후기가 마감되면(`feedbackClosedAt` 기록) `tagClosedFeedback` 트리거가 실행된다.
1. `learningConsent == true`이고 comment가 있는 후기만 처리한다.
2. 같은 소모임 신청자의 모임 표시 이름과 프로필 이름을 `[팀원]`으로 바꾼다(2자 이상, 긴 이름부터, 대소문자 무시). 한 글자 이름은 일반 단어를 가릴 수 있어 바꾸지 않는다.
3. 언어 AI에는 태그 집합 `ctag1`(9개 × pos/neg/neutral), 지시문, `temperature: 0`만 보낸다.
4. 집합 밖 태그·감정은 버리고, 형식이 틀리면 1회 재시도, 그래도 실패하면 `{status: "failed"}`.
5. 결과 `commentTags = {version: "ctag1", status: "ok", tags, model, modelVersion}`. 이미 ok인 후기는 다시 보내지 않는다. 후기 원문을 고치면 태그를 지운다.
6. 끝나면 팀 집계(태그 수 포함)를 다시 계산한다.

원문은 로그에 남기지 않는다. 제공자 오류 메시지도 기록하지 않는다.

### ⚠ 언어 AI 제공자는 아직 정하지 않았다
명세상 미정(🔒)이므로 고르지 않았다. `configuredProvider()`가 `null`을 돌려주는 동안은 태깅하지 않고(`no_provider`) 후기는 태그 없이 남는다. 제공자를 정하면:
- `classify({text, tags, sentiments, instructions, temperature})` → `{tags, model, modelVersion}` 어댑터 하나를 만들고 `configuredProvider()`에서 돌려준다.
- 입력 데이터를 보관·학습하지 않는 조건으로 계약·설정한다(12장).
- API 키는 Secret Manager에 두고 코드·저장소에 넣지 않는다.
- 이미 마감된 소모임은 관리자가 다시 실행해야 태깅된다(재실행 명령은 아직 없음).

## 검증 (2026-10-30, 실제 실행)
```sh
cd functions
npm test               # 18개: 1~2단계 검증 13 + 4~5단계 순수 로직 5
npm run test:emulator  # 20개: 1~2단계 9 (1~4단계 끝까지 포함) + 4~5단계 11
cd .. && npm run test:rules   # 15개 (consents 규칙 포함)
```
가이드 통과 기준 대응:

| 기준 | 테스트 |
|---|---|
| 상태가 정해진 순서로만 | `4: state only moves forward ...` |
| ended 진입 시 종료 버전 기록 | `4: ending records endedVersion ...` |
| 활동 중 재공개가 있어도 종료 버전에 연결, membershipRatio | `4: feedback links to the ending version ...`, `membershipRatio` 순수 테스트 |
| 임원진이 후기 원문·개별 점수를 못 읽음 | `4: summary only for teams with 3+ ...` (main 규칙으로 실제 읽기 시도) |
| 응답자 3명 미만 팀은 집계 없음 | 같은 테스트 + `summary` 순수 테스트 |
| 이름이 `[팀원]`으로 바뀐 뒤 전달 | `5: names masked ...` |
| 집합 밖 태그 버림 | `5: names masked ...`, `validTags` 순수 테스트 |
| 동의하지 않은 후기는 태깅 안 함 | `5: names masked ...` |
| 실패 시 failed, 다른 처리는 계속 | `5: names masked ...`, `classify` 순수 테스트 |
| 같은 입력 같은 결과 (온도 0) | `5: same input ...`, `classify` 순수 테스트 |

## 이번에 하지 않은 것
- 공개 뒤 참가 철회 처리, leaveGroup / deleteAccount (9단계 삭제 처리와 함께)
- 마감된 소모임 태깅 재실행 명령, 관리자 화면
- Flutter 화면 연결 (`lib/data/feedback_learning_api.dart`에 호출 함수만 추가)

배포하지 않았다.
