# 9단계: 삭제 처리·모니터링

기준: 편성학습_v4 11·12장, main `docs/FIRESTORE.md`의 leaveGroup / deleteAccount, 개발단계 가이드 9단계.

## 명령 (functions/src/privacy.js)
| 명령 | 누가 | 하는 일 |
|---|---|---|
| deleteFeedback | 작성자 | 후기 삭제 → 팀 집계 재계산 → 학습 데이터셋 `dirty`. 집계가 바뀌므로 추출 작업이 그 소모임을 다시 뽑아 학습 행을 재계산(조건 미달이면 행 삭제) |
| leaveGroup | 본인 | 멤버십 `left`. **유일한 임원진이면 거부.** 본인이 쓰거나 본인을 지목한 비공개 선호 해제. 공개 전 소모임 신청은 취소(인원 감소), 공개된 소모임 기록은 유지 |
| deleteAccount | 본인 (`confirm: true`) | 유일한 임원진이면 거부. 아래 표대로 처리 후 마지막에 Firebase Auth 계정 삭제 |

### deleteAccount가 처리하는 것
| 대상 | 처리 |
|---|---|
| `users`, `consents`, `memberships`, `registrations`, `feedback`, `placementPreferences`(작성·지목 모두), `notifications`, 본인 `teamViews`, `rateLimits` | 삭제 |
| `publications`의 팀 구성 | uid → `deleted-user`, 이름 → "삭제된 사용자" (팀 기록 보존) |
| 다른 사람의 `teamViews` 팀원 목록 | 같은 방식으로 바꿈 |
| `drafts`, `formationRuns.publicSummary` | 초안에서 빼고, 요약의 uid는 `deleted-user` |
| `serverRuns` 스냅샷 | 응답 사본·공개/초안 배정·고정·비공개 선호에서 해당 uid 제거 (이를 위해 3단계가 `serverRuns`에 `activityId`를 기록) |
| 공개 전 소모임 인원 | 감소 |
| 팀 집계, 학습 데이터셋 | 집계 재계산, `dirty` |

여러 문서를 나눠 쓰므로 원자적이지 않지만, 같은 명령을 다시 실행하면 남은 것을 마저 처리한다(멱등).

## 학습 쪽 (algorithm/learning)
- 학습: 데이터셋이 `dirty`면 다음 학습 작업이 바로 학습하고(주기와 무관), 끝나면 `dirty`를 지운다. 이미 적용된 모델은 즉시 폐기하지 않고 다음 학습 결과로 바뀐다(12장).
- 모니터링 `monitor.py` (추출 작업 뒤 실행): 후기가 마감된 소모임마다 `learningMonitor/{a}`에 쓴 모델(종료 공개 버전을 만든 실행의 `modelId`, 수동 편집 공개는 `manual`)과 만족도 평균을 기록. 어떤 모델이 소모임 10개 이상 쌓이면 `learningReports/latest`에 기본 가중치와 비교. "결론을 단정하지 않고 상관을 인과로 해석하지 않는다"는 문구를 함께 남긴다.
- 둘 다 서버 전용(규칙 테스트로 확인).

## 검증 (2026-10-30, 실제 실행)
| 가이드 기준 | 테스트 |
|---|---|
| 후기 삭제 시 학습 행·`reviewSummary` 재계산, `dirty` | functions `9: deleting a review ...`, Python `test_deleted_review_leaves_the_training_row` |
| 계정 삭제 시 응답·선호·멤버 삭제, 공개 팀 기록은 `deleted-user` | functions `9: account deletion removes personal data ...` |
| `serverRuns` 응답 사본에서도 삭제 | 같은 테스트 |

추가: 유일한 임원진 차단, 확인값 필요, 모임 나가기, dirty 재학습, 모니터링 기록·보고.

전체 (에뮬레이터 포함): Python 129, functions 단위 15·에뮬레이터 25, 규칙 16, Flutter analyze 문제 없음·테스트 26.
