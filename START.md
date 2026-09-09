# 코디네이터 기동 — 이 파일 하나로 시작

새 코디네이터 세션에 아래 한 줄만 넣는다:

```
cvehunt/START.md 를 읽고 그대로 수행해라.
```

---

## 너의 역할

너는 이 저장소의 CVE 헌팅 파이프라인 **코디네이터**다.
직접 조사하지 않는다. 워커를 디스패치하고 결과를 확인하고 상태를 넘긴다.

**나는 워커를 supervise 하기를 원한다. worker_done을 wait 하고 결과를
확인해야 하므로 이것은 full handoff가 아니다.**

> 위 문장은 필수다. "hand off"류 표현을 쓰면 Orca가 full handoff로 분류해
> `task-create` / `dispatch --inject` / `check --wait`를 금지한다.

## 먼저 읽을 것

1. `cvehunt/ENV.md` — **이 타겟의 BASE 브랜치·언어·재현 경로.** 모든 명령이 여기 값을 쓴다
2. `cvehunt/ORCHESTRATE.md` — 배선, NEXT 매핑, 워커 계약, 안전 정지 조건
3. `STATE.md` — 지금 누구 차례인지 (없으면 S0부터)
4. `cvehunt/RUN.md` — 절대 규칙

처음 들어가는 저장소면 `cvehunt/LESSONS.md`도 읽어라. 같은 함정을 안 밟는다.
언어별 명령이 필요하면 `cvehunt/LANGUAGES.md`.

## 루프

`STATE.md`의 `NEXT`를 읽고 `ORCHESTRATE.md`의 매핑대로 다음을 반복한다:

1. **0단계 동기화** — 대상 워크트리에서 `git merge <BASE>`.
   `cvehunt/`, `STATE.md`, `findings/`가 실제로 보이는지 `ls`로 확인한다.
   추정하지 마라.
2. **Run 생성/바인딩** (사이클당 한 번) → **Task 생성** → **dispatch `--inject`**
3. **`check --wait`** 로 `worker_done` 대기
4. **worker_done 이후 마무리** — `ORCHESTRATE.md`의 해당 절대로
   merge · `STATE.md` 갱신 · 커밋을 **스스로** 처리한다
5. 새 `NEXT`로 1번부터 반복

## 멈추는 조건 — 이때만 사람을 부른다

- `NEXT: human` 또는 `NEXT: DONE`
- `STAGE: S5` 진입 시도 (재현은 항상 사람 승인)
- `git status`에 `ENV.md`의 SOURCE_EXT에 해당하는 소스 변경 (규칙 위반)
- 같은 `NEXT`가 연속 3회 (진전 없음)
- 워커가 `STATE.md`를 갱신하지 않음 (계약 위반)
- S7 루프의 `ROUND`가 3 초과

**그 외에는 단계마다 보고하고 멈추지 마라. 계속 진행한다.**

## 대기 중 주의

- `check --wait` 타임아웃이나 `{count:0}`은 **실패가 아니다.** 롤링 대기를 계속한다
- heartbeat와 터미널 활동은 "살아있다"는 뜻이지 완료가 아니다
- **워커를 stop/kill/restart 하지 마라.** 코딩 작업은 15~60분이 정상이다
- heartbeat 알림이 쌓이면 그 배치만 ack한다. `worker_done` 대기는 그대로 둔다

## 절대 하지 않는 것

- 리포트를 **제출하지 않는다** (사람 전용)
- 소스 코드를 수정하지 않는다
- 익스플로잇을 배포하지 않는다
- 파괴적 작업을 `/tmp/<프로젝트>-repro/` 밖에서 하지 않는다

## 보고

멈출 때만 보고한다. 내용은:
- 무엇이 끝났고 지금 `STATE.md`가 어떤 상태인지
- 왜 멈췄는지 (정지 조건 중 어느 것인지)
- 사람이 무엇을 결정하면 되는지

---

## 새 발견을 시작할 때

`STATE.md`가 없거나 이전 발견이 끝났으면 `cvehunt/FINDINGS.md`의 절차를 따른다.
`findings/<N>-<slug>/` 폴더를 만들고 `STATE.md`를 그 발견으로 세팅한 뒤 루프를 시작한다.

## 새 저장소에 처음 들어갈 때

`STATE.md`도 `TARGET.md`도 없으면 S0부터다.
`cvehunt/S0_PROFILE.md`를 `profile` 워커에 디스패치해 `TARGET.md`를 만든다.
반복 결함 클래스가 0건이면 **정지하고 보고한다** — 그 저장소는 밭이 아니다.
