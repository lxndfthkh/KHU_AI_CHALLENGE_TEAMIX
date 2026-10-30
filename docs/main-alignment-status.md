# main 통합 상태

## 기준
main 061b0ec(dca8e20 규칙 복구 포함)를 병합했다. 저장 구조는 main의 `docs/FIRESTORE.md`, `firestore.schema.json`, `firestore.rules`를 따른다.
예전 중첩 구조(`groups/{g}/memberships`, `activities/{a}/applications`, `activities/{a}/drafts`, `privatePreferences/{uid}/groups/{g}`)는 더 이상 쓰지 않는다.

| 범위 | 위치 | 문서 |
|---|---|---|
| 1~2단계 서버 명령 (소모임·신청·선호) | `functions/src/commands.js` | `docs/feedback-learning-stages-1-2.md` |
| 3단계 편성 API | `algorithm/server_v3.py`, `repository.py` | `docs/feedback-learning-stage3-boundary-status.md` |
| Flutter 호출 계층 | `lib/data/feedback_learning_api.dart`, `lib/services/formation_api.dart` | 화면 연결 전 |

## 서버 구분 — 혼용 금지
`algorithm/server.py`는 main의 시연용 `/solve` 서버다. 원본 참가자 입력을 받으므로 실데이터에 쓰지 않는다.
`algorithm/server_v3.py`가 Firebase ID 토큰을 검사하고 서버에서 입력을 조회하는 실제 편성 API다.

## 검증
- `npm run test:rules` (루트): main 규칙 14개
- `functions`: `npm test` 13개, `npm run test:emulator` 9개 (1~3단계 끝까지 포함)
- `algorithm`: 에뮬레이터 포함 91개
- `flutter analyze`, `flutter test`

## 남은 일
- Flutter 화면을 시연 데이터에서 위 호출 계층으로 바꾸기
- 4단계(활동 종료·후기) 전에 학습 활용 동의의 저장 위치를 main 스키마에 정하기
- 운영 배포 전: App Check, 푸시 알림, 운영 로깅 정책 검토. 배포는 담당자가 직접
