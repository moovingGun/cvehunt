# 오케스트레이션 배선 (Orca)

코디네이터 에이전트 하나가 Orca orchestration CLI로 워커를 디스패치하고
`worker_done`을 기다린다. `STATE.md`의 `NEXT`가 누구를 깨울지 결정한다.

---

## ★ 가장 중요한 함정 — "hand off"라고 말하지 마라

Orca 오케스트레이션 스킬은 이렇게 분류한다:

- **"hand off" / "handoff" / "give this to another agent" / "another worktree"**
  → **full handoff로 분류**된다. 그 경우 스킬은 `task-create`,
  `dispatch --inject`, `check --wait`를 **쓰지 말라고 지시한다.**
  결과: lifecycle 추적 없이 프롬프트만 전달되고 끝난다.

- **"supervise" / "monitor" / "wait for worker_done" / "track completion" /
  "coordinate" / "DAG" / "decision gate"**
  → **supervised orchestration**으로 분류되어 정식 Run/Task/Dispatch가 생긴다.

**코디네이터 프롬프트는 반드시 "supervise"와 "wait for worker_done"을
명시적으로 포함해야 한다.** 이 단어가 없으면 오케스트레이션이 작동하지 않는다.

이 한 단어 때문에 첫 배선이 실패한 적이 있다 (`LESSONS.md` 8번).

## ★ 두 번째 함정 — 하니스 내장 도구로는 다른 모델에 도달 못 한다

에이전트 하니스의 내장 메시징 도구는 **같은 하니스 세션끼리만** 도달한다.
다른 종류의 에이전트는 별개 프로세스라 잡히지 않는다.

**Orca CLI는 모든 터미널에 도달한다.** 에이전트 종류와 무관하다:

```bash
orca terminal list --json                    # agentIdentity로 에이전트 종류 구분
orca terminal send --terminal <handle> --text "<프롬프트>" --enter --json
orca orchestration dispatch --task <id> --to <handle> --inject --json
```

그룹 주소도 있다: `@claude`, `@codex`, `@all`, `@idle`, `@worktree:<id>`

---

## 전제조건

```bash
orca status --json
```

- `runtime.state: "ready"`
- capabilities에 `orchestration.contract.v1` 포함

## 워커 핸들 확인

```bash
orca terminal list --json
```

`worktreePath`와 `agentIdentity`로 매칭한다. 예:

| 워크트리 | agentIdentity | 역할 |
|----------|---------------|------|
| `.../review` | 검토자 모델 | 검토자 |
| `.../coordinator` | 작성자 모델 | 코디네이터 |
| `.../repro` | 작성자 모델 | 재현 |
| `.../finding-NNN` | 작성자 모델 | 탐색/외부모듈 |

한 워크트리에 터미널이 여러 개일 수 있다(에이전트 + 셸).
**`agentIdentity`가 있는 것만 워커로 쓴다.**

---

## 코디네이터 루프

```bash
# 1. Run 생성 (사이클당 한 번)
orca orchestration run-create --objective "<목표>" --json

# 2. Task 생성
orca orchestration task-create --spec "<TASK 블록 전문>" --json

# 3. 기존 워커에 디스패치 (핸들이 있을 때 — 컨텍스트 유지됨)
orca orchestration dispatch --task <task_id> --to <handle> --inject --json

#    또는 새 워커 기동 (핸들이 없을 때)
orca orchestration worker-start --task <task_id> \
  --worktree <worktree selector> --agent <검토자 모델> --json

# 4. 완료 대기 (sleep/poll 금지)
orca orchestration check --wait \
  --types worker_done,escalation,question --timeout-ms 900000 --json

# 5. 확인 — orchestrated됐다고 주장하기 전에 반드시
orca orchestration task-list --json
orca orchestration dispatch-show --task <task_id> --json
```

**타임아웃은 실패가 아니다.** 코딩 작업은 15~60분이 정상이다.
`{count:0}`이면 체크포인트로 보고 롤링 대기를 계속한다.
heartbeat와 터미널 활동은 살아있다는 뜻이지 끝났다는 뜻이 아니다.

**워커를 죽이지 마라.** 완료 메시지가 아직 없다는 이유로
stop/close/kill/restart 하지 않는다.

---

## worker_done 이후 — 코디네이터 마무리 (자동)

`check --wait`가 `worker_done`을 받으면 코디네이터가 **다음 워커를 부르기 전에**
아래를 스스로 처리한다. 사람을 부르지 않는다.

```bash
# 1. 워커 브랜치를 base 브랜치로 가져온다
cd <base 워크트리>
git merge <워커 브랜치> -m "merge <stage> result for <FINDING>"

# 2. 산출물이 실제로 들어왔는지 확인
ls findings/<FINDING>/

# 3. STATE.md 를 워커의 판정 결과에 맞게 갱신한다
#    (워커가 갱신했으면 그대로 두고, 누락했으면 코디네이터가 채운다)

# 4. 커밋
git add STATE.md findings/<FINDING>/ && git commit -m "<stage> result for <FINDING>"
```

**판정 → STATE.md 매핑:**

| 워커 판정 | STAGE | NEXT | BLOCKED_REASON |
|-----------|-------|------|----------------|
| PASS | S4 | `author` | (비움) |
| NEEDS_REPRO | S4 | `author` | (비움) — S4가 REPRO_PLAN.md와 부작용 등급을 만든다 |
| NEEDS_HUMAN (외부 모듈) | S3 | `external` | (비움) |
| FAIL 전부 | S1 | `hunter` | (비움) |

그다음 `NEXT` 값에 따라:
- `human` / `DONE` → **정지하고 사용자 호출**
- 그 외 → 0단계 동기화부터 다음 워커 디스패치 계속

**워커가 `STATE.md`를 갱신하지 않은 경우도 코디네이터가 채운다.**
그것 때문에 멈추지 마라. 다만 그 사실을 보고에 남겨라 — 태스크 spec에
"STATE.md 갱신은 worker_done 전 필수"를 명시해야 한다는 신호다.

## NEXT → 워커 매핑

| STATE.md의 NEXT | 워크트리 | agent |
|-----------------|----------|-------|
| `profile` | profile | 아무거나 |
| `hunter` | finding-NNN | 작성자 모델 |
| `external` | finding-NNN | 작성자 모델 |
| `reviewer` | review | **검토자 모델** (작성자와 달라야 함) |
| `author` | base 워크트리 | 작성자 모델 |
| `repro` | repro | 작성자 모델 |
| `human` | — | **정지, 사용자 호출** |
| `DONE` | — | **정지** |

코디네이터 규칙은 이 표가 전부다. 조건 분기를 추가하지 마라 —
판단은 워커가 `STATE.md`에 쓸 때 이미 끝나 있다.

---

## ★ 핸드오프 전 필수 — 워크트리 동기화

**디스패치 전에 대상 워크트리를 반드시 base 브랜치와 동기화한다.**

```bash
cd <대상 워크트리>
git merge <BASE> -m "sync with base"
ls cvehunt/ STATE.md findings/     # 셋 다 보여야 한다
```

워크트리는 **만들어진 시점의 커밋에 멈춰 있다.** base 브랜치는 계속 나가므로
오래된 워크트리는 최신 문서를 갖고 있지 않다.

건너뛰면 워커가:
- 참조 파일을 못 찾아 메인 체크아웃을 직접 읽는 우회를 한다 (산출물이 붕 뜬다)
- **옛 게이트 목록으로 판정한다** — 나중에 추가한 게이트가 빠진 채 통과시킨다

충돌은 보통 파이프라인 산출물(`REVIEW.md`, `LOOP_STATE.md`)에서만 난다.
**base 쪽을 택한다:**

```bash
git checkout --theirs <충돌파일>
git add <충돌파일> && git commit -m "sync with base"
```

이 실수는 실전에서 세 번 반복됐다. 자세한 것은 `cvehunt/LESSONS.md` 10번.
**동기화를 코디네이터 루프의 0단계로 넣어라.**

## ★ 추정 금지

코디네이터는 대상 워크트리 상태를 **직접 확인**한다. 자기 폴더만 보고
"거긴 파일이 없다"고 추정하면 안 된다. 실제로 `ls` 하거나
`git show <branch>:<path>`로 확인한다.

---

## STATE.md

```markdown
# STATE
FINDING: <N>-<slug>
STAGE: S2
NEXT: reviewer
UPDATED_BY: review
UPDATED_AT: <ISO8601>
BLOCKED_REASON:
```

`FINDING`은 산출물 경로를 정한다 — `findings/<FINDING>/` 아래에만 쓴다.
`BLOCKED_REASON`은 `NEXT: human`일 때만 채운다.

## 워커 계약

**턴 시작:** `git show <BASE>:STATE.md`로 `NEXT` 확인.
자기 역할이 아니면 **아무것도 하지 않고 멈춘다.**

**턴 종료:**
1. 산출물을 `findings/<FINDING>/` 아래에 쓴다
2. `STATE.md` 갱신
3. **커밋** — 안 하면 다음 워커가 못 읽는다
4. `worker_done` 전송 (dispatch 프리앰블이 있을 때만):

```bash
orca orchestration send --type worker_done \
  --subject "<짧은 상태>" --body "<한 것, 찾은 것, 남은 것>" \
  --task-id <task_id> --dispatch-id <dispatch_id> \
  --outcome succeeded --files-modified "path/a,path/b" --json
```

실패면 `--outcome failed`. **본문에만 실패를 적지 마라.**
`worker_done` 후에는 턴을 끝내고 대기한다. 폴링하지 않는다.

---

## S4 → S5 재현 게이트 — 위험도별

재현이라고 다 위험한 게 아니다. **S4가 만든 `REPRO_PLAN.md`의 부작용 등급을
코디네이터가 읽고 판단한다.**

`REPRO_PLAN.md`는 반드시 아래 필드를 포함한다:

```markdown
## 부작용 등급
LEVEL: A | B | C
LEVEL_REASON: <왜 그 등급인지 한 줄>

## 부작용 목록
- <이 재현이 만들거나 바꾸거나 지우는 것을 전부. 경로 포함>

## 격리 확인
- 위 목록의 모든 경로가 <REPRO_ROOT> 하위인가: YES / NO
- NO인 항목: <있으면 전부 나열>
```

| 등급 | 내용 | 처리 |
|------|------|------|
| **A** | 읽기 전용, HTTP 요청, 임시 DB 생성, 로그 확인만 | **자동 진행** |
| **B** | `REPRO_ROOT` 안에서만 파일 생성·수정·삭제 | **자동 진행** (아래 검증 후) |
| **C** | `REPRO_ROOT` 밖 경로가 하나라도 등장 / 등급 판정 불가 / 계획이 부작용을 다 열거하지 못함 | **정지, 사람 승인** |

**B 등급 자동 진행 전 코디네이터가 직접 검증한다** (워커 신고를 믿지 마라):

```bash
# 계획의 모든 경로가 REPRO_ROOT 하위인지
grep -oE '(/[A-Za-z0-9._/-]+)' findings/<FINDING>/REPRO_PLAN.md \
  | grep -v "^<REPRO_ROOT>" | grep -vE '^/(api|action|tmp/<PROJECT>-repro)' \
  && echo "격리 밖 경로 발견 — C로 강등, 정지"
```

**등급과 무관하게 항상 사람을 부르는 경우:**

- **이 타겟의 첫 재현** — `ENV.md`의 `START_CMD`가 아직 검증 안 됐다.
  서버 기동 명령이 무엇을 하는지 한 번은 사람이 봐야 한다.
- 계획이 `sudo`, 시스템 경로(`/etc` `/usr` `/var`), 홈 디렉터리 직하,
  또는 저장소 자체를 건드린다고 명시한 경우
- 재현이 외부 네트워크로 나가는 경우 (SSRF 검증 등)

**첫 재현이 끝나고 `START_CMD`/`STOP_CMD`가 `ENV.md`에 확정되면,
그 뒤로는 A·B 등급이 자동으로 흐른다.**

## 안전 정지 조건

코디네이터가 **직접 검사**한다. 워커 자기 신고에 의존하지 마라.

- `NEXT: human` 또는 `DONE`
- `STAGE: S5` 진입 시 **C 등급 / 첫 재현 / sudo·시스템경로·외부네트워크** — 사람 승인
  (A·B 등급이고 첫 재현이 아니면 자동 진행)
- `git status`에 `ENV.md`의 SOURCE_EXT에 해당하는 소스 변경 — **규칙 위반**
- 같은 `NEXT`가 연속 3회 — 진전 없이 맴돌고 있다
- 워커가 `STATE.md`를 갱신하지 않음 — 계약 위반
- S7 루프의 `ROUND`가 3 초과

## 사람이 개입한 뒤 재개

1. `STATE.md`의 `NEXT`를 다음 역할로 바꾸고 `BLOCKED_REASON`을 비운다
2. 커밋
3. 코디네이터에 "계속" 전달

---

## 배선 검증 (첫 실행)

**한 단계만** 돌리고 확인한다:

- [ ] `orca orchestration task-list --json`에 task가 실재하나
- [ ] `dispatch-show --task <id>`에 dispatch가 실재하나
- [ ] 산출물이 `findings/<FINDING>/` 안에 생겼나 (루트에 흩어지면 계약 위반)
- [ ] `STATE.md`의 `NEXT`가 바뀌고 커밋됐나
- [ ] 검토 결과 표에 **G7·G8·G9 행이 있나** (동기화 검증 지표)

다섯 개 다 맞으면 연속 실행으로 넘어간다.
task/dispatch가 없으면 **orchestrated된 게 아니다** — 프롬프트에
"supervise/wait" 단어가 빠졌을 가능성이 가장 높다.
