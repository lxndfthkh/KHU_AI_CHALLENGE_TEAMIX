# TEAMIX Firestore 규칙 테스트

## 실행

Node.js 22 이상과 Firestore 에뮬레이터가 지원하는 Java(21 권장)가 필요합니다.
저장소 루트에서 `npm install` 후 `npm run test:rules`를 실행하세요.
이 명령은 demo-teamix-rules 프로젝트의 로컬 Firestore 에뮬레이터에서만 테스트합니다.
에뮬레이터를 별도 실행하려면 `npm run emulators:rules`를 사용하고,
다른 터미널에 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080을 설정한 뒤
`npm run test:rules:unit`를 실행하세요. 환경변수 설정 문법은 셸에 따라 다릅니다.
프로덕션 배포는 자동 수행하지 않습니다. 테스트 데이터를 실제 프로젝트에 넣지 않습니다.


## 기준 구조

`firestore.rules`와 `firestore.indexes.json`은 `docs/FIRESTORE.md`, `firestore.schema.json`과 같은
최상위 컬렉션 구조를 따릅니다. 역할의 기준은 `memberships/{groupId}_{uid}` 하나입니다.
예전 하위 컬렉션 구조(`groups/{g}/memberships`, `joinRequests`, `invites`, `inviteCodes`,
`activities/{a}/applications`, `privatePreferences`)는 더 이상 쓰지 않으며 규칙에서 모두 막힙니다.

## 테스트 범위

- 사용자 프로필: 본인만 읽기, 허용 필드(displayName, createdAt, updatedAt)로만 생성·수정, 삭제 금지.
- 모임·소모임 본문·질문: 승인된 회원만 읽기. 편성 설정과 후기 집계는 운영진(admin)만 읽기.
- 멤버십: 본인 문서, 운영진은 모임 전체, 회원은 승인된 회원만 읽기. 홈 화면용 본인 멤버십 조회.
- 참가 신청: 본인과 운영진만 읽기. 편성안·공개 이력: 운영진만 읽기.
- 내 팀 뷰: 제출 상태 신청이 있는 본인만 읽기. 후기 원문·배치 선호: 작성자만 읽기(운영진 불가).
- 알림: 본인만 읽기, `readAt`만 서버 시각으로 변경.
- 앱 설정: 로그인 사용자 읽기. `_schema`, 초대 토큰, 정의되지 않은 경로: 전면 차단.
- 모임 만들기: 모임과 본인 운영진 멤버십을 한 배치로 만들 때만 허용. 한쪽만, 남의 uid로, 기존 모임에, 허용되지 않은 필드·값으로는 거절.
- 그 밖의 쓰기는 클라이언트에서 거절됩니다. 쓰기는 `docs/FIRESTORE.md`의 서버 명령이 담당합니다.

Admin SDK는 규칙을 우회하므로, 서버 명령은 인증 UID·역할·입력·상태 전이를 직접 검증해야 합니다.
에뮬레이터는 프로덕션 복합 인덱스 필요 여부를 완전히 재현하지 않으므로 인덱스 배포 후 별도 확인이 필요합니다.
