# TEAMIX Firestore 연결 기준

프로젝트: `teamix-309c0`, 데이터베이스: `(default)`, 위치: 서울 `asia-northeast3`.

## 실제 배포 상태
- 컬렉션 접근 규칙과 7개 복합 인덱스 배포 완료.
- `appConfig/teamix`: 공통 팔레트·모임 가입 승인·설문 잠금·팀 사이즈 입력 기준.
- `_schema/*`: 관리용 데이터 구조 설명. 실제 사용자나 모임이 아님. 클라이언트 접근 불가.
- 상세 필드는 `firestore.schema.json` 참조.
- Firestore는 스키마를 강제 생성하는 테이블 DB가 아니다. 실제 사용자·모임 컬렉션은 첫 유효 데이터 저장 때 생긴다.
- 앱 연결: 로그인 시 `users/{uid}` 생성, 내 모임 홈 조회, 모임 만들기, 초대 코드 발급·참여 요청(아래 '서버 없이 처리하는 명령'). 가입 승인 등 나머지 서버 비즈니스 로직은 아직 없다.

## 확정 기준
- `targetTeamSize`: 소모임을 만들 때 입력받는 팀당 목표 인원. 별도 팀 수 입력을 요구하지 않는다.
- 모임·소모임 각각 `themeColor`: mint / peach / lilac. 목록 카드와 내부 화면이 같은 값을 사용한다.
- 소모임 생성 시 모임 색을 기본값으로 복사하고 선택한 다른 색으로 저장할 수 있다.
- `activities`는 회원이 읽는 정보만 포함. 편성 방식은 `activities/{id}/settings/matching`에서 임원진만 읽는다.
- 편성안 `drafts`와 공개 이력 `publications`를 분리. 일반 참가자는 본인의 `teamViews/{activityId}_{uid}`만 읽는다.
- 사용자 역할은 `memberships/{groupId}_{uid}`가 유일한 기준. 사용자 프로필에 관리자 여부를 넣지 않는다.
- 클라이언트에 등록된 Firebase 로그인 계정은 앱 운영진과 다르다. Firebase 콘솔 프로젝트 관리자는 특권 접근을 갖는다.

## 앱 연결 순서
1. 회원가입 후 `users/{uid}`에 displayName, createdAt, updatedAt 저장. 시각에는 serverTimestamp 사용.
2. 홈: memberships에서 userId == 로그인 UID, status in [approved, pending] 조회.
3. 승인된 모임의 groups 문서 조회. 대기 모임 미리보기는 서버에서 안전한 필드만 반환.
4. 모임 홈: activities에서 groupId와 status로 조회.
5. 각 소모임의 참가/마감/편성/공개 기능을 서버 호출로 연결.

## 아직 구현해야 하는 서버 명령
이 명령들이 구현되기 전에는 users의 안전한 프로필 쓰기, notifications의 읽음 처리, 아래 createGroup 배치 외 직접 클라이언트 쓰기는 거절된다. 보안 규칙을 전체 허용으로 바꾸지 않는다.

### 서버 없이 처리하는 명령 (무료 Spark 요금제 시뮬레이터용)
- createGroup: 앱이 `groups/{id}`와 `memberships/{id}_{uid}`(role admin, status approved)를 한 배치로 쓴다. 규칙이 서로의 존재(existsAfter/getAfter), 본인 uid, 정해진 필드·길이, 새 모임 여부를 검사하므로 기존 모임에 자신을 운영진으로 넣을 수 없다. 구현: `lib/data/firestore_group_writer.dart`. Cloud Functions를 쓰게 되면 이 규칙을 지우고 서버 명령으로 옮긴다.
- issueInvitation: 운영진이 `invitations/{코드}`를 만든다. 코드는 8자리(헷갈리는 I·O·0·1 제외), 만료는 7일 이내, 모임 이름·소개는 `groups` 값과 같아야 한다. 운영진은 `active: false`로 끌 수 있다.
- previewInvitation: 로그인 사용자가 아는 코드 문서 하나를 `get`한다. 목록 조회는 막혀 있어 코드를 훑어볼 수 없다. 만료·비활성 코드는 거절된다. 인원 수는 서버 없이 유지할 수 없어 보여주지 않는다.
- requestJoin: 앱이 `memberships/{groupId}_{uid}`를 role member, status pending, `invitationId`(코드)와 함께 만든다. 규칙이 코드의 모임·유효 기간을 확인한다. 문서가 이미 있으면(가입·대기·거절) 덮어쓸 수 없다. 대기 중에는 모임을 읽을 수 없어 홈 카드 이름은 초대 문서에서 가져온다.
- 구현: `lib/data/firestore_invitations.dart`. 가입 승인·거절(approveJoin/rejectJoin)은 아직 없다.

- approveJoin / rejectJoin: 해당 그룹 admin 확인 후 전이 및 알림 생성.
- createActivity: admin 확인, 양의 capacity/targetTeamSize와 deadline 검증. 질문과 설정을 함께 저장.
- submitRegistration / updateRegistration / cancelRegistration: 트랜잭션에서 승인 회원·상태·서버 시간·정원 검증. 처음 제출할 때만 인원 증가. 질문 구조는 첫 제출 후 영구 잠금.
- closeRecruitment: admin 확인, 상태 전이. 자동 마감 작업이 늦어져도 제출 서버가 deadline을 검사.
- generateDraft / moveMember: 서버에서만 비공개 선호 조회, 누락·중복·인원 검증. 임원진 응답에는 민감 원인·건수 포함 금지.
- publishTeams: 검증된 편성안을 별도 버전으로 복사. 공개 이력·각 참가자의 내 팀 뷰·공개 버전을 함께 갱신. 변경 알림은 실제 팀원 구성이 변경된 사람만.
- endActivity / submitFeedback: 종료 및 참가 여부 검사. 원문은 작성자, 운영진은 집계만 읽음.
- setPlacementPreference / revokePlacementPreference: 작성자와 모임 관계 검증. 본인 대상 불가. 공개하지 않고 다음 편성에 반영.
- leaveGroup / deleteAccount: 유일한 운영진의 이탈 차단, 종속 데이터 처리. 부모 문서 삭제만으로 하위 데이터가 정리된다고 가정하지 않음.

Firestore Admin SDK는 보안 규칙을 우회한다. 모든 서버 명령은 인증 UID·역할·입력·전이 조건을 직접 검증해야 한다.
편성 알고리즘의 세부 인원 분배 기준은 아직 서버에 구현되지 않았다.

## 배포
```sh
firebase deploy --only firestore --project teamix-309c0
```
현재 확인: Firebase 배포 시 규칙 컴파일 통과, 인덱스 배포 성공, appConfig 읽기 재확인.
미확인: 에뮬레이터 권한 시나리오 테스트 및 실제 앱의 종단 간 동작. 서버 기능을 연결하기 전에 허용/거절 테스트를 추가해야 한다.
