# main 통합 상태 및 검증

## 기준
main 107775b를 feature/feedback-learning에 PR #12로 병합했다(9014744).
main 자체를 수정한 작업은 아니다. 이후 서버 함수, 저장 어댑터와 Flutter API를 canonical main 데이터 계약에 맞췄다.

- groups/{g}/memberships/{uid}: owner / admin / member
- groups/{g}/joinRequests/{uid}: pending / approved / rejected
- activities/{a}: questions, matchingSettings, responseVersion, settingsVersion
- activities/{a}/applications/{uid}: submitted / withdrawn, raw answers
- activities/{a}/drafts/current: 서버 초안 및 revision
- activities/{a}/publications/{id}: 불변 공개 결과
- privatePreferences/{uid}/groups/{g}: 모임 단위 targets, 본인만 접근

엔진 내부의 officer/applied/teamVersions 이름은 어댑터를 통해 변환되며 그대로 저장하지 않는다.

## 서버 구분 — 혼용 금지
algorithm/server.py는 main에서 온 로컬 시연 /solve 서버다. 원본 참가자 입력을 받으므로 실데이터/공개 배포에 사용하지 않는다.
algorithm/server_v3.py가 Firebase ID 토큰을 검사하고 서버에서 입력을 조회하는 실제 편성 API다.
Dockerfile.stage3는 server_v3:app을 실행한다. 기존 시연 화면/TeamMatchingService는 그대로 두었다.
Flutter FormationApi는 실제 API용 별도 경계이며 화면 연결이 끝났다는 뜻은 아니다.

## 재현 가능한 단위 테스트
저장소 algorithm 폴더에서 requirements-stage3.txt 의존성 준비 후:

```sh
python -m unittest discover -s tests -p test_main_adapter.py -v
```

이 커밋에 포함한 8개 어댑터 테스트: owner/admin 변환, 잘못된 역할 차단, 정원 검증, 필수 조건 변환, canonical 저장 경로, 실행→공개 메모리 왕복, 질문 변경 제한, 변경 지문 검사.
실제 Firestore가 아닌 메모리 모사 테스트다.

functions 폴더에서:

```sh
node --test test/validation.test.js
```

기존 validation 테스트를 main 계약에 맞는 14개 테스트로 교체했다.

작업 공간 전체 Python 테스트 38개 및 Node 14개가 통과했다. 38개 중 추가 어댑터 테스트 8개를 이번 커밋에 반영하며, 나머지 작업 공간 테스트가 모두 저장소에 추가되었다는 의미는 아니다.

## 미완료 및 배포 차단 사항
1. Firestore Rules 에뮬레이터 검증 및 기존 functions/test/rules.test.cjs의 레거시 경로 정리 필요.
2. main 규칙의 클라이언트 직접 초안 수정/공개 권한과 서버 전용 편집 정책의 통합 필요. 현재 원격 rules는 main 기준이며, 서버만으로 편집이 강제된 상태가 아니다.
3. profileSettings/notifications의 클라이언트 읽기 권한 추가 및 검증 필요. 기본 거부 상태로 개인정보 노출보다는 기능이 제한된다.
4. Flutter analyze/test 및 화면의 실제 API 연결 미완료.
5. 실제 Firebase 토큰·Firestore 트랜잭션/동시성·STALE 처리 통합 검증 미완료.
6. 기존 저장소의 레거시 실데이터 마이그레이션 미구현. 경로만 바꿔 기존 데이터가 자동 이전되지는 않는다.
7. 공개 후 참가 철회·실제 푸시 전송·캐시·전체 명세 적합성 검증은 별도 잔여 작업이다.

따라서 Git 충돌 해소/데이터 계약 통합과 전체 3단계 완성을 구분한다. 이 상태를 실서비스 배포 완료로 취급하지 않는다.
