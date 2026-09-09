#!/usr/bin/env bash
# CVE 헌팅 파이프라인 설치
# usage: ./cvehunt/bootstrap.sh /path/to/target-repo [LANG]

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
LANG_HINT="${2:-}"

if [ -z "$TARGET" ]; then
  echo "usage: $0 /path/to/target-repo [LANG]" >&2
  echo "  LANG: go | node | python | rust | php | ruby | java | csharp" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

if [ ! -d "$TARGET/.git" ]; then
  echo "ERROR: $TARGET is not a git repository." >&2
  echo "worktree 격리가 git 위에서 동작하므로 git 저장소여야 합니다." >&2
  exit 1
fi

echo "==> cvehunt 설치: $TARGET"
mkdir -p "$TARGET/cvehunt"
for f in START.md RUN.md ORCHESTRATE.md PIPELINE.md VERIFY.md REVIEW.md \
         LOOP.md S0_PROFILE.md LANGUAGES.md LESSONS.md bootstrap.sh; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$TARGET/cvehunt/$f"
done
chmod +x "$TARGET/cvehunt/bootstrap.sh" 2>/dev/null || true

# 인스턴스 파일은 템플릿에서 (있으면 덮어쓰지 않는다)
for f in FINDINGS.md METRICS.md; do
  if [ ! -f "$TARGET/$f" ] && [ -f "$SRC/templates/$f" ]; then
    cp "$SRC/templates/$f" "$TARGET/$f"
    echo "==> 생성: $f"
  fi
done

cd "$TARGET"

PROJ="$(basename "$TARGET")"
BASE="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
REPRO="/tmp/${PROJ}-repro"

# 언어 자동 감지 (힌트가 없으면)
if [ -z "$LANG_HINT" ]; then
  if   [ -f go.mod ];              then LANG_HINT=go
  elif [ -f package.json ];        then LANG_HINT=node
  elif [ -f Cargo.toml ];          then LANG_HINT=rust
  elif [ -f composer.json ];       then LANG_HINT=php
  elif [ -f Gemfile ];             then LANG_HINT=ruby
  elif [ -f pom.xml ] || [ -f build.gradle ]; then LANG_HINT=java
  elif ls ./*.csproj >/dev/null 2>&1; then LANG_HINT=csharp
  elif [ -f requirements.txt ] || [ -f pyproject.toml ]; then LANG_HINT=python
  else LANG_HINT=unknown
  fi
fi

case "$LANG_HINT" in
  go)     EXT=".go" ;;
  node)   EXT=".js .ts .jsx .tsx .mjs .cjs" ;;
  python) EXT=".py" ;;
  rust)   EXT=".rs" ;;
  php)    EXT=".php" ;;
  ruby)   EXT=".rb" ;;
  java)   EXT=".java" ;;
  csharp) EXT=".cs" ;;
  *)      EXT="(코디네이터가 LANGUAGES.md 보고 채울 것)" ;;
esac

cat > "$TARGET/cvehunt/ENV.md" <<EOF
# 이 타겟의 환경

bootstrap.sh가 생성. 값이 틀리면 코디네이터가 확인 후 고친다.

| 키 | 값 |
|----|-----|
| PROJECT | $PROJ |
| REPO | $TARGET |
| BASE | \`$BASE\` |
| LANG | $LANG_HINT |
| SOURCE_EXT | $EXT |
| REPRO_ROOT | \`$REPRO\` |
| INSTALLED_AT | $(git rev-parse --short HEAD 2>/dev/null || echo unknown) |

## BASE
모든 문서에서 "base 브랜치"는 \`$BASE\`를 뜻한다.
워크트리 동기화는 \`git merge $BASE\`.

## REPRO_ROOT
S5의 파괴적 작업은 전부 \`$REPRO\` 안에서만. 그 밖은 금지.

## SOURCE_EXT
안전 검사용. 코디네이터는 매 턴 아래를 확인한다:

\`\`\`bash
git status --short | grep -E '\\.(${EXT// /|})\$' && echo "규칙 위반 — 정지"
\`\`\`

## 미확정 — 코디네이터가 채울 것

| 키 | 값 |
|----|-----|
| START_CMD | (S5 서버 기동 명령) |
| STOP_CMD | (S5 종료·포트 정리) |
| PORTS | (기동에 쓰는 포트) |

저장소의 CONTRIBUTING.md / Makefile / docker-compose.yml /
.claude/CLAUDE.md / AGENTS.md 에서 찾는다. S5 전에 확정한다.
EOF

git add cvehunt FINDINGS.md METRICS.md 2>/dev/null || git add cvehunt
if git diff --cached --quiet; then
  echo "==> 변경 없음 (이미 최신)"
else
  git commit -q -m "add cvehunt pipeline"
  echo "==> 커밋: $(git rev-parse --short HEAD)"
fi

cat <<EOF

설치 완료.

  프로젝트: $PROJ
  base 브랜치: $BASE
  언어: $LANG_HINT  (소스 확장자: $EXT)
  재현 격리: $REPRO

언어 감지가 틀렸으면: $0 $TARGET <lang>

다음 단계:
  1. Orca에서 이 저장소를 열고 'coordinator' 워크트리를 만든다 (base = $BASE)
  2. 그 세션에 아래 한 줄:

     cvehunt/START.md 를 읽고 그대로 수행해라.

  코디네이터가 STATE.md가 없는 것을 보고 S0 프로파일링부터 시작한다.
  반복 결함 클래스가 0건이면 정지 — 그 저장소는 밭이 아니다.
EOF
