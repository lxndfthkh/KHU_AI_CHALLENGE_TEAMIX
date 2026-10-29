# 편성학습 v3: 편성 API 경계 보완 상태

## 기준
- 확인한 main HEAD: `107775b84cfd8ba65062aeca12f667ae754823a2`.
- 이 커밋은 작업 브랜치 `13fc4778bf57b9a0a892420b08205912f21696c0`의 조상에 포함되어 추가 병합할 main 변경이 없었음.
- 기존 Flutter 저장 구조와 어댑터를 유지한다. 이 변경은 1~3단계 전체 완료 선언이 아니다.

## 변경
- 운영 API가 ValidatedFormationService를 사용하도록 연결.
- 서비스 진입점에서 로그인, 역할, 요청 구조, 재편성 종류와 범위를 검사.
- 모집 중 설정 변경 허용, 공개 후 설정 변경 차단.
- 솔버 결과의 배정과 공개 지표를 독립 검증/재계산.
- 원본 솔버 충돌 문자열과 비정상 stageProof를 공개 응답/formationRuns로 복사하지 않음. INFEASIBLE은 일반 공개 안내로 대체.
- 솔버 예외/잘못된 배정은 ERROR로 반환하고 기존 초안을 보존.

## 실제 실행한 테스트
`cd algorithm && python -m unittest discover -s tests -p 'test_main_adapter.py' -v`
`cd algorithm && python -m unittest discover -s tests -p 'test_stage3_boundary.py' -v`

두 대상에 해당하는 로컬 테스트를 함께 실행: 기존 어댑터 8개 + 경계 회귀 23개 = 중복 없는 31개 통과.
STALE 테스트는 메모리 저장소에서 명단/설정/초안/응답/선호/비공개 버전이 실행 도중 바뀌는 경우를 주입했다. 실제 Firestore 재시도/동시성 검증은 아니다.
기존 test_engine.py 전체, Firebase Rules 에뮬레이터, Flutter 통합, 실제 인증/Cloud Run 배포는 이번 검증에 포함하지 않았다.

## 남은 완료 조건
- 소모임 단위 비공개 선호 저장/상태 제한/서버 전용 prefVersion 및 앱 계약 변경.
- 개인 answerVersion과 응답 수정 시 버전 증가 규칙 정합성.
- 앱의 초안/공개 직접 쓰기를 서버 경로로 전환한 후 Rules 강화 및 에뮬레이터 검증.
- 편성알고리즘 v3 13-1 전체 사례 검증.
- 실제 Firestore 트랜잭션 및 인증된 API/Flutter 통합 검증.

배포하지 않았으며 운영 데이터 마이그레이션도 수행하지 않았다.
