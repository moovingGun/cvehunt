# 교차 검토 루프 — 자동 왕복

작성자와 검토자가 **파일을 통해** 주고받는다. 사람이 내용을 복사하지 않는다.
두 에이전트는 같은 저장소의 서로 다른 worktree에 있고, git이 통신 채널이다.

## 통신 규약

각 턴이 끝나면 **반드시 커밋한다.** 커밋하지 않으면 상대가 읽을 수 없다.

읽기:
```
git show <BASE>:REPORT_DRAFT.md
git show moovingGun/review:REVIEW.md
```

쓰기: 자기 worktree에 파일을 쓰고 커밋.

상태는 `LOOP_STATE.md` 하나에 모인다. 매 턴 이 파일을 갱신한다.

---

## LOOP_STATE.md 형식

```markdown
# LOOP STATE
ROUND: 1
NEXT: reviewer | author | human | DONE
COMMIT_UNDER_REVIEW: <SHA>

## 미해결 지적
| # | 라운드 | 지적 | 종류 | 상태 | 필요 조치 |
|---|--------|------|------|------|-----------|

## 해결된 지적
| # | 지적 | 판정 | 근거 |
|---|------|------|------|
```

지적 상태: `OPEN` / `RESOLVED` / `REJECTED` / `NEEDS_REPRO`

---

## 턴 정의

### 검토자 턴
1. `git show <BASE>:REPORT_DRAFT.md` 로 최신 초안을 읽는다
2. REVIEW.md의 검토자 프롬프트를 적용한다
   (메인테이너가 되어 **기각할 이유**를 찾는다)
3. 지적을 [F] 사실 / [J] 판단으로 분류해 `REVIEW.md`에 쓴다
4. **이전 라운드에서 REJECTED된 지적을 다시 제기하지 않는다.**
   재제기하려면 새로운 증거를 함께 제시해야 한다
5. LOOP_STATE.md의 미해결 표에 추가, `NEXT: author`, 커밋

### 작성자 턴
1. `git show <review-branch>:REVIEW.md` 로 지적을 읽는다
2. 각 지적을 **증거로** 판정한다. 표결 금지
   - [F] → 코드·커밋·자문을 직접 열어 확인. 검토자가 틀렸으면 근거와 함께 REJECTED
   - [J] → 과장을 줄이는 지적은 기본 수용, 논증을 늘리는 지적은 기본 기각
3. 수용한 것만 REPORT_DRAFT.md에 반영
4. 판정 근거를 LOOP_STATE.md 해결 표에 기록
5. 지적이 **새 재현을 요구하면** 그 항목을 `NEEDS_REPRO`로 두고
   `NEXT: human` 으로 바꾼다. 추측으로 답하지 않는다
6. `ROUND` 증가, `NEXT: reviewer`, 커밋

---

## 종료 조건 (엄격)

`NEXT: DONE` 은 아래를 **전부** 만족할 때만 쓴다:

1. 미해결 표에 `OPEN` 상태 지적이 0건
2. `NEEDS_REPRO` 항목이 0건
3. 마지막 검토자 턴에서 **새로운 [F] 지적이 0건**
   (기존 지적의 재표현은 새 지적이 아니다)

!! "둘 다 좋다고 본다"는 종료 조건이 아니다.
   합의는 정확성의 증거가 아니며, 라운드가 길어질수록 수렴 압력만 커진다.
   종료는 **증거로 닫힌 지적의 수**로만 판단한다.

## 강제 중단

- **ROUND가 3을 넘으면 중단하고 `NEXT: human`.**
  3라운드에 안 닫히는 건 모델끼리 해결할 수 없는 문제라는 뜻이다
- `NEEDS_REPRO`가 하나라도 생기면 즉시 `NEXT: human`
  (재현은 파괴적 작업이라 사람 승인이 필요하다)
- 같은 지적이 두 라운드 연속 등장하면 그 항목만 `NEXT: human`

## 사람이 하는 것

- `NEEDS_REPRO` 승인 및 재현 실행
- 3라운드 초과 시 판정
- **제출** — 루프는 절대 제출하지 않는다

---

## 첫 턴 시작 프롬프트

검토자 세션에:
```
LOOP.md와 REVIEW.md를 읽어라. 너는 검토자다.
git show <BASE>:REPORT_DRAFT.md 로 초안을 읽고 검토자 턴을 수행해라.
끝나면 REVIEW.md와 LOOP_STATE.md를 커밋하고 멈춰라.
```

작성자 세션에:
```
LOOP.md를 읽어라. 너는 작성자다.
git show <review-branch>:LOOP_STATE.md 로 상태를 확인하고,
NEXT가 author면 작성자 턴을 수행해라.
끝나면 커밋하고 멈춰라.
```

Orca 오케스트레이션에 물릴 경우: 두 태스크를 `LOOP_STATE.md`의 `NEXT`
값에 따라 번갈아 깨우도록 구성한다. `NEXT: human` 또는 `DONE`이면 정지.
