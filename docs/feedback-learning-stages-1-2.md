# 편성학습 v3 — 1~2단계 구현

## 기준과 구현 범위

2026-10-30 편성학습_v3, 화면흐름_정리_v7, 팀편성흐름 통합_v4를 읽고 반영했다. 최신 명세의 용어는 임원진(officer) / 참가원(participant). 모임 생성자는 officer, 초대 참여자는 pending이며 임원진 승인을 거친다. 로그인 수단은 기존 Firebase Auth를 그대로 사용하며 새 공급자를 정하지 않는다.

이번 변경은 **서버 데이터 계층 + Security Rules + Flutter API 어댑터**다. 기존 onboarding.dart / DemoGroupRepository는 그대로이며 화면은 아직 이 API 어댑터로 교체하지 않았다. 그러므로 현 앱의 화면을 클릭한다고 새 서버 함수가 자동 호출되는 상태는 아니다. 앱 전체 1~2단계 E2E 완료나 운영 배포 완료로 보지 않는다.

포함: initializeProfile, setLearningConsent, createGroup, previewInvite, requestJoin, decideJoin, listMyGroups, createActivity, updateActivitySettings, submitApplication, withdrawApplication(공개 전), setPrivatePreference, withdrawPrivatePreference. 승인 결과는 본인만 읽는 notifications 문서로 기록하며 FCM 푸시 발송은 하지 않는다.

제외: 편성 엔진, 초안 수정/공개, 활동 상태 전환, 후기, 태깅, 학습/모델 승인, 삭제 파이프라인. 이 단계에서는 정원을 기본 ceil(N/K)로 채우지 않고 null로 유지한다. 3단계 마감 시 최초 기본값을 채운다.

## 파일

- functions/src/index.js: 인증/active/역할/소모임 상태 재검증, 트랜잭션, 비공개 선호 2건 상한.
- functions/src/validation.js: 선택 질문/응답 버전/선택지/설정 검증.
- firestore.rules: 기본 거부. 모든 서비스 쓰기는 서버, 본인 displayName 수정만 직접 허용.
- firestore.indexes.json: 비공개 선호 및 멤버 상태 검색 인덱스.
- lib/data/feedback_learning_api.dart: Firebase ID 토큰을 붙여 callable 프로토콜 호출. 새 로그인 수단 도입 없음. http 직접 의존성을 pubspec에 추가.

## 버전 의미와 상충 문구

명세 13장 완료 기준은 '응답 수정 시 answerVersion·rosterVersion 증가'라고 요약하지만 2-1/4-1에서는 rosterVersion은 참가 명단 변경 시만 증가한다고 명시한다. **상세 필드 정의를 우선**해 응답만 수정하면 answerVersion만 증가하며 최초 신청/철회/재신청 시 rosterVersion이 증가한다. 함수 응답으로 두 값을 확인할 수 있다. 질문이 변경되면 questionVersion도 갱신하며 예전 버전 응답은 거부한다.

settings 변경은 임의 patch 대신 전체 settings와 expectedSettingsVersion을 받아 서버가 허용 필드만 골라 저장한다. 서버 관리 필드 주입 불가. 질문 삭제 후 같은 ID를 다시 추가해도 옛 응답을 재사용할 수 없도록 settingsVersion을 질문 새 버전의 기준으로 사용한다.

## 비공개 선호

setPreference 호출은 confirmed:true라는 UI의 명시적 확인을 요구한다. 별도 재인증은 이번에 정하지 않았다. 본인과 대상은 해당 소모임의 active 신청자여야 한다. 본인 대상 불가. owner/group/activity 범위의 활성 최대 2건. 동일 대상 재등록은 멱등 처리. private/meta를 같은 트랜잭션에서 갱신하여 동시 등록 충돌 시 재시도하고 상한을 다시 검증한다. 문서 ID는 4개 식별자의 JSON을 SHA-256으로 만든 서버 내부 키이다.

임원진이 선호 목록/존재/건수/대상/버전이나 private/meta를 읽지 못한다. 임원진 본인이 직접 등록한 선호는 본인 자격으로만 읽을 수 있다. 클라이언트 선호 조회는 반드시 ownerUid == 현재 uid 조건을 사용한다.

## 스키마에 없는 보조 저장소와 제안값

- invites/{code}: 서버 전용. 모임 생성 시 144-bit 무작위 코드 발급. **7일 만료는 이번 구현의 임시 제안값**이며 서비스 확정 사항 아님. 링크 형식/공유 도메인/초대 재발급 UI는 미연결.
- notifications/{id}: ownerUid만 읽기. 승인/거절 앱 내 알림을 위한 최소 보조 경로.
- 거절/탈퇴 후 모임 재요청 정책 미정이므로 자동 복원하지 않고 failed-precondition 반환.
- 기본 학습 동의 false, l1은 명세 문구에 대응하는 구현 버전. 법적 약관 문안 확정을 대신하지 않는다.
- listMyGroups는 pending 사용자에게 groups 문서를 직접 열어주지 않고 최소 DTO를 서버에서 반환한다. 현재는 collectionGroup members 상태 검색 후 uid로 필터링하는 초기 구현이다. 데이터 증가 전 members.uid 복합 인덱스나 사용자별 projection으로 바꿔 전체 스캔을 제거해야 한다.

## 의도적인 안전 제한 / 후속 단계

1. 공개 후 withdrawApplication은 공개 팀·초안·고정을 원자적으로 함께 수정해야 하므로 이번에는 recruiting/forming에서만 허용한다. published/in_progress에서는 거부한다. 3단계 구현 전 서버가 공개 팀만 남기는 불완전 철회를 만들지 않도록 한 제한이다.
2. forming 중 질문 변경은 응답 재요청 흐름이 필요하므로 거부한다. recruiting에서는 변경 가능하다.
3. extraRequirements는 3단계 엔진 규격 연결 전 빈 배열만 허용한다. 필수 역할 등 조건을 받은 척하며 무시하지 않는다.
4. Firestore는 문서 일부 필드만 숨기지 못한다. 명세의 teams.reviewSummary(임원진 전용)를 같은 팀 문서에 넣으면 참가원 읽기 권한과 충돌한다. 현재 Rules는 reviewSummary가 있는 팀 문서의 참가원 읽기를 안전하게 거부한다. 4단계에서 집계를 임원진 전용 별도 경로로 분리한 뒤 확장해야 한다.
5. 초대 정보를 로그인 동안 유지/결과 후 삭제하는 v7 화면 상태와 기존 시연 데이터의 서버 전환은 **미연결**이다. Flutter API 계층만 추가했으며 화면/라우팅은 바꾸지 않았다.
6. Auth App Check 강제, 요청 rate limiting, 초대 재발급, 네트워크 재시도용 멱등 키, 푸시 알림, 운영 로깅 정책은 운영 배포 전에 별도 검토한다. 이 구현은 운영 보안 감사를 대신하지 않는다.

## 실행과 검증

```sh
# 저장소 루트
flutter pub get
flutter analyze
flutter test
cd functions
npm install
npm test
# Rules emulator 테스트는 functions 폴더에서
npm run test:rules
# 루트로 돌아온 뒤 실제 배포는 담당자가 별도로 실행
cd ..
firebase deploy --only functions,firestore
```

일반 배포 전에 함수 트랜잭션/동시성 통합 검증이 반드시 필요하다. 추천 시나리오: 프로필 생성 → 모임 생성 → 초대 확인 → 다른 사용자 pending → officer 승인 → 소모임 생성 → 응답 신규/수정 버전 비교 → 3개 대상 선호 동시 등록 시 활성 2건 이하 → 철회 후 재등록. 통합 검증과 Rules 에뮬레이터 테스트가 통과하기 전 단계 완료로 표시하지 않는다.

구현 시 실제 실행: 순수 검증 단위 테스트 10개 통과. Rules 테스트 9개는 작성했으나 에뮬레이터에서는 실행하지 않았다. Firebase Functions 배포/호출, Flutter analyze/test 및 실제 화면 통합은 실행하지 않았다. pubspec.lock은 flutter pub get으로 갱신해야 한다.
