# 1~2단계 서버 명령 (main 스키마)

## 기준
- main `docs/FIRESTORE.md`, `firestore.schema.json`, `firestore.rules`(dca8e20)이 기준이다. 예전 중첩 구조(`groups/{g}/memberships`, `activities/{a}/applications`, `privatePreferences/{uid}/groups/{g}`)는 쓰지 않는다.
- main 규칙은 프로필(`users/{uid}`)과 알림 읽음 표시 외의 앱 직접 쓰기를 모두 막는다. 아래 명령이 그 쓰기를 대신한다.
- 명령 이름은 FIRESTORE.md "아직 구현해야 하는 서버 명령"과 같다. 편성 명령(closeRecruitment, generateDraft, moveMember, publishTeams 등)은 `algorithm/server_v3.py`가 맡는다.

## 명령 (functions/src/commands.js, index.js가 callable로 노출)

| 명령 | 누가 | 쓰는 문서 |
|---|---|---|
| createGroup | 프로필 있는 로그인 사용자 | `groups/{g}`, `memberships/{g}_{uid}` (admin, approved) |
| issueInvitation | 임원진 | `invitations/{sha256(code)}`. 코드는 응답으로 한 번만 돌려주고 저장하지 않음 |
| previewInvitation | 코드가 있는 사람, 또는 이미 요청한 사람(groupId) | 읽기만. 이름·설명·색·회원 수·내 상태 |
| requestJoin | 프로필 있는 사용자 + 유효한 코드 | `memberships/{g}_{uid}` pending |
| approveJoin / rejectJoin | 임원진 | membership approved/rejected + `notifications` joinApproved/joinRejected |
| createActivity | 임원진 | `activities/{a}`, `activities/{a}/questions/{qid}`, `activities/{a}/settings/matching` |
| submitRegistration / updateRegistration / cancelRegistration | 승인된 회원 | `registrations/{a}_{uid}`, `activities/{a}.participantCount`, `questionsLockedAt` |
| setPlacementPreference / revokePlacementPreference | 승인된 회원 | `placementPreferences/{g}_{uid}_{target}` |

모든 명령은 한 트랜잭션에서 로그인 → 승인된 회원 → 역할 → 대상 상태 순으로 검사한다. Admin SDK는 규칙을 우회하므로 이 검사가 유일한 보호다. 예상하지 못한 오류는 내용 없이 "처리 중 오류가 발생했어요"로만 돌려준다.

## createActivity가 3단계에 넘기는 것
`settings/matching`: `method`, `enabledQuestionIds`, `questionCriteria {질문ID: role|time|experience|interest}`, `priority`(생략 시 질문 순서 + size), `requireCommonTime`, `requiredRoles: []`, `capacityInitialized: false`, `settingsVersion: 1`. 팀 ID와 정원은 closeRecruitment가 정한다.
- 질문 형식: role=single, time·interest=multiple, experience=scale(1~5). 편성 기준 질문은 반드시 필수 응답.
- 편성에 쓰지 않는 질문(예: MBTI)도 만들 수 있고, 선택 응답으로 둘 수 있다.

## 정한 값과 정책 (명세에 없어서 정함, 바꾸기 쉬움)
- 초대 코드: 10자(헷갈리는 0/O/1/I 제외), 기본 7일, 1~30일. 같은 코드를 링크에도 쓴다.
- 코드 확인 시도 제한: 사용자당 10분에 20회(previewInvitation + requestJoin 합산, 틀린 코드도 셈). 기록은 `rateLimits/{uid}_invite`(규칙상 클라이언트 접근 불가).
- 거절됐거나 나간 사람도 유효한 코드로 다시 요청할 수 있다(pending으로 돌아감).
- 신청 취소: 모집 중과 마감 후 공개 전까지. 공개 뒤에는 거부한다(공개 팀 수정은 재편성 흐름에서).
- 같은 응답으로 다시 제출해도 인원은 한 번만 센다.

## 이번에 하지 않은 것
- leaveGroup / deleteAccount (9단계 삭제 처리와 함께)
- endActivity / submitFeedback (4단계)
- 초대 비활성화 명령, 푸시 알림 전송, App Check
- 학습 활용 동의: 예전 구현의 profileSettings는 main 스키마에 없어서 뺐다. 후기(4단계) 전에 main 스키마에 자리를 정해야 한다.
- Flutter 화면 연결: `lib/data/feedback_learning_api.dart`에 호출 함수만 있다.

## 실행
```sh
cd functions && npm install
npm test               # 검증 단위 테스트 13개
npm run test:emulator  # Firestore 에뮬레이터 명령 테스트 9개 (Java 필요)
```
마지막 에뮬레이터 테스트는 1~2단계 명령으로 만든 모임·소모임·신청·선호를 3단계(`algorithm/.venv`)가 마감·편성·공개하는지 끝까지 확인한다. `algorithm/.venv`가 없으면 건너뛴다.

배포하지 않았다.
