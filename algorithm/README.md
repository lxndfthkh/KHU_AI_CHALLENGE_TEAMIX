# TEAMIX 처음 편성 엔진 — 1단계

`편성알고리즘_v3.md` 1~13장 중 **공개 전 처음 편성**을 구현한 Python 참고 엔진입니다. 기존 Flutter 앱과 분리되어 있으며 앱/API/DB 연결은 하지 않았습니다.

## 실행

Python 3.11 이상에서 저장소의 algorithm 폴더로 이동한 뒤:

```bash
python -m pip install -r requirements.txt
python -m teamix_engine examples/initial_20.json --public-output run/public.json --internal-output run/internal.json
python -m unittest discover -s tests -v
```

종료 코드: 유효 후보(OPTIMAL/FEASIBLE)는 0, 입력 오류·충돌·한도·처리 오류는 1. JSON 공개 출력과 내부 기록 파일은 반드시 분리합니다. 내부 파일은 가능한 OS에서 0600 권한으로 기록합니다. 실제 서비스에서는 별도의 서버 접근 제어가 필요합니다. `solve()`의 전체 반환값을 클라이언트로 보내지 마세요.

## 모듈

- `teamix_engine/schema.py`: JSON 스냅샷 검증·정규화, 누락 응답 및 사전 충돌 검사.
- `teamix_engine/scoring.py`: Fraction 기반 정확한 유리수/정수 점수 계산, 반올림, 점수표와 100,000행 한도. `verify()`는 솔버 변수나 점수표를 사용하지 않고 배정에서 필수 조건과 점수를 재계산합니다. 수식 함수는 모델 표 생성과 공유합니다.
- `teamix_engine/engine.py`: CP-SAT 필수 조건, 정확한 점수 등식, J_int 최소화, 독립 검증, 별도 필수조건 진단 모델.
- `teamix_engine/__main__.py`: JSON 입출력 CLI.
- `tests/test_engine.py`: 요청한 명세 13-1의 1·6·11·13·20번과 추가 경계 검증.
- `examples/initial_20.json`: 이 구현 검증을 위해 만든 가상 20명·4팀 데이터. 기존 프로토타입 원본 데이터를 복원한 것은 아닙니다.
- `examples/result_public.json`: 실제 예제 실행의 공개 팀 요약.
- `examples/result_internal.json`: 가상 데이터 전용 내부 실행 기록. 실제 서비스의 비공개 정보를 Git에 커밋하면 안 됩니다.

## JSON 입력

정확한 전체 형태는 `examples/initial_20.json` 참고.

- `mode`: `initial`만 지원. `published_assignment`가 있으면 거부합니다.
- `method`: `balanced` 또는 `similar`.
- `participants`: `{id, answers}` 배열. ID는 고유 문자열. 답변 키는 `role`, `time`, `experience`, `interest`.
- `teams`: `{id, capacity}` 배열. `capacity`는 양의 정수, 미지정/null이면 명시 정원 없음. 엔진은 입력 정원을 자동 변경하거나 기본값을 덮어쓰지 않습니다. 설정 화면에서 최초 기본값 ceil(N/K)를 정한 뒤 전달하세요.
- `selected_questions`: 사용할 질문 키 배열. 미선택 응답은 계산·필수 역할·요약에서 제외합니다.
- `priority`: 선택 질문과 `size`를 각각 한 번 포함한 순서. 가중치는 m-r+1.
- `categories`: role/time/interest 선택지. 역할은 단일 선택, 시간·관심은 최소 1개 복수 선택, 경험은 1~5 정수.
- `fixed`: `{participant, team}` 배열. 처음 편성의 고정 배치를 필수로 준수.
- `required_roles`: `{team, role, minimum}` 배열. 동일 팀·역할의 중복 조건은 동시에 적용(가장 큰 minimum과 동일).
- `require_common_time`: true이면 모든 팀의 전원 공통 시간 최소 1개 필수.
- `private_preferences`: `{source, target, confirmed, withdrawn?}`. 활성·확인된 선호만 사용. 명단 외 관계는 제외, 방향 제거·중복 통합, 발신자당 활성 대상 최대 2명. 자신 지목은 오류.
- `versions`: 실행 기록에 보존할 버전 객체.
- `solver`: `seed` 기본 42, `max_deterministic_time` 기본 10. 작업자 수는 1로 고정.

선택 질문의 미응답은 ERROR로 반환하며 0/평균으로 채우지 않습니다. 응답 요청·질문 전체 제외·참가자 제외는 호출자가 명시적으로 처리한 뒤 새 스냅샷을 제출해야 합니다.

## 계산·범위

- 공개 공정성: 최악 팀 60% + 평균 40%; 공개/비공개 명목 비중 90:10.
- `F_int = 3K max(L_t) + 2 sum(L_t)`.
- `P = 1000 V / (2N)`: 내부 JSON에는 정수 numerator/denominator로 기록.
- `J_int = 18N F_int + 5000 K W V`만 최소화.
- 모든 점수·목적식 계산은 정수/Fraction이며 실수 점수 계산을 하지 않습니다. 처리 시간·결정적 시간·솔버가 제공하는 하한은 메타데이터이므로 실수일 수 있습니다.
- 정원 없음은 안전 상한 U_t=N-K+1; 정원이 있으면 min(capacity,N-K+1). 잘못된 고정 반영 축소로 숨은 정원이 생기지 않도록 기본 상한을 사용합니다.
- 점수표 **각 테이블당** 최대 100,000행. 100,001번째 행을 추가하기 전에 오류. 이번 단계에서는 선형화 전환을 하지 않습니다.
- 표의 등식, max/min 등가 제약으로 점수값을 정확히 결정한 뒤 독립 재계산과 비교합니다.
- 출력 `public`에는 V/P/J_int 등 비공개 반영 지표가 없습니다. 내부 기록에만 L_t/F_int/V/P/J_int와 솔버 버전·시드·하한 등을 남깁니다.
- 공개 후 재편성, 부분 재편성, DB 버전 비교/적용 트랜잭션, 캐시, 인증·서버 권한은 이번 단계 밖입니다. 버전은 기록만 하며 STALE 판정/초안 적용을 수행하지 않습니다.
- 품질 우선 재편성 모드, 균등 인원 보장 옵션, 집중 지목 대응은 구현하지 않았습니다.
- 진단은 충분한 충돌 집합을 반환하며 최소 충돌 집합은 보장하지 않습니다.

## 검증 결과

OR-Tools 9.14.6206 / 작업자 1 / 시드 42 / 결정적 한도 10.

14개 테스트 통과. 명세 번호 매핑: `test_01_basic_twenty`, `test_06_insufficient_role`, `test_11_capacity`, `test_13_reproducible_without_cache`, `test_20_uncapped_team_can_exceed_five`.

예제 결과: **FEASIBLE**, 실제 시간 약 5.72초(실행 환경에 따라 변동), 20명 누락·중복 없이 5명씩 편성. 최적성 미증명이며 "추천 편성안"입니다. 각 팀에 전원 공통 가능 시간이 있고 경험 자가 응답 평균은 15/5입니다. 상세 역할 희망·관심 분포는 공개 JSON에 있습니다. 재현성 테스트는 캐시 없이 두 번 탐색하여 배정과 목적값을 비교합니다.

이 결과는 구현 동작 확인이며 실제 협업 만족도나 공정성의 실증 검증이 아닙니다. 가중치 민감도·무작위 후보 비교 실험은 아직 수행하지 않았습니다.
