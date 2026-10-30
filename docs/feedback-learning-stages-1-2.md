# 1~2단계 서버 명령 (main 스키마)

## 기준
- main `docs/FIRESTORE.md`, `firestore.schema.json`, `firestore.rules`가 기준이다.
- **모임 만들기, 초대 코드 발급·확인, 가입 요청, 가입 승인·거절은 main 앱이 규칙 아래에서 직접 쓴다** (`lib/data/firestore_group_writer.dart`, `firestore_invitations.dart`, `firestore_join_requests.dart`). 서버에는 이 명령들이 없다(2026-10-30, main PR #15·#17에 맞춰 제거).
  - 초대: `invitations/{8자 코드}` (모임 이름·소개 포함, 7일 이내 만료, 목록 조회 불가)
  - 가입 요청: `memberships/{g}_{uid}` pending + `invitationId`(코드). 이미 문서가 있으면(가입·대기·거절·탈퇴) 다시 요청할 수 없다.
  - 승인·거절: 그 모임 임원진이 status만 approved/rejected로 바꾼다. 알림은 아직 없다.
- 규칙이 막아 두어 앱이 직접 쓸 수 없는 것만 서버 명령으로 남긴다.

## 남은 명령 (functions/src/commands.js, index.js가 callable로 노출)

| 명령 | 누가 | 쓰는 문서 |
|---|---|---|
| createActivity | 임원진 | `activities/{a}`, `activities/{a}/questions/{qid}`, `activities/{a}/settings/matching` |
| submitRegistration / updateRegistration / cancelRegistration | 승인된 회원 | `registrations/{a}_{uid}`, `activities/{a}.participantCount`, `questionsLockedAt` |
| setPlacementPreference / revokePlacementPreference | 승인된 회원 | `placementPreferences/{g}_{uid}_{target}` |

모든 명령은 한 트랜잭션에서 로그인 → 승인된 회원 → 역할 → 대상 상태 순으로 검사한다. Admin SDK는 규칙을 우회하므로 이 검사가 유일한 보호다.

## createActivity가 3단계에 넘기는 것
`settings/matching`: `method`, `enabledQuestionIds`, `questionCriteria {질문ID: role|time|experience|interest}`, `priority`(생략 시 질문 순서 + size), `requireCommonTime`, `requiredRoles: []`, `capacityInitialized: false`, `settingsVersion: 1`. 팀 ID와 정원은 closeRecruitment가 정한다.
- 질문 형식: role=single, time·interest=multiple, experience=scale(1~5). 편성 기준 질문은 반드시 필수 응답.

## 정한 값
- 신청 취소: 모집 중과 마감 후 공개 전까지. 공개 뒤에는 거부한다(공개 팀 수정은 재편성 흐름에서).
- 같은 응답으로 다시 제출해도 인원은 한 번만 센다.

## 실행
```sh
cd functions && npm install
npm test               # 검증 단위 테스트
npm run test:emulator  # Firestore 에뮬레이터 명령 테스트 (Java 필요)
```
에뮬레이터 테스트는 모임·초대·가입·승인을 **main 앱과 같은 방식(규칙 아래 앱 쓰기)**으로 만든 뒤, 그 데이터에서 서버 명령과 3·4단계가 끝까지 동작하는지 확인한다. 거절된 사람이 다시 요청할 수 없는 main 정책과, 임원진만 승인할 수 있는 규칙도 함께 확인한다.

배포하지 않았다.
