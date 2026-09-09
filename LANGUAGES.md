# 언어별 매핑

파이프라인은 언어 무관이다. 언어에 따라 달라지는 것만 여기 모은다.
`ENV.md`의 `LANG` 값에 해당하는 행을 쓴다.

`LANG`이 목록에 없으면 코디네이터가 저장소를 보고 아래 4개 칼럼을
직접 채워 `ENV.md`에 적고 진행한다. 추측하지 말고 실제 매니페스트를 확인한다.

## 의존성 소스 확보 (S3 외부 모듈 확인용)

| LANG | 의존성 받기 | 소스 위치 |
|------|-------------|-----------|
| go | `go mod download` | `$(go env GOMODCACHE)` |
| node | `npm ci` 또는 `pnpm i` | `node_modules/` |
| python | `pip download -d /tmp/deps -r requirements.txt` | `$(python -c 'import site;print(site.getsitepackages()[0])')` |
| rust | `cargo fetch` | `$(cargo metadata --format-version 1 \| jq -r .workspace_root)` / `~/.cargo/registry/src/` |
| php | `composer install` | `vendor/` |
| ruby | `bundle install` | `$(bundle show --paths)` |
| java | `mvn dependency:sources` | `~/.m2/repository/` |
| csharp | `dotnet restore` | `~/.nuget/packages/` |

**S3 규칙은 언어와 무관하다:** 실제 소스 파일:줄을 인용해야 판정이다.
인용 없으면 불명으로 남긴다.

## 소스 파일 확장자 (안전 검사 — "코드 수정 금지" 확인용)

| LANG | 확장자 |
|------|--------|
| go | `.go` |
| node | `.js .ts .jsx .tsx .mjs .cjs` |
| python | `.py` |
| rust | `.rs` |
| php | `.php` |
| ruby | `.rb` |
| java | `.java` |
| csharp | `.cs` |

코디네이터의 안전 검사:

```bash
git status --short | grep -E '\.(<확장자들>)$' && echo "규칙 위반 — 정지"
```

## sink 패턴 (S0의 P0-3 인벤토리용)

결함 클래스는 언어와 무관하다. 표현만 다르다.

| 클래스 | go | node | python | php | java |
|--------|-----|------|--------|-----|------|
| SQL 식별자/문자열 조합 | `goqu.I` `goqu.L` `fmt.Sprintf`+`Query` | 템플릿 리터럴+`query(` `knex.raw` | f-string/`%`+`execute(` | `$sql .=` `mysqli_query` | `createQuery` 문자열 연결 |
| 명령 실행 | `exec.Command` `os/exec` | `child_process.exec` `spawn` | `subprocess` `os.system` | `system` `exec` `shell_exec` | `Runtime.exec` `ProcessBuilder` |
| 경로 결합 | `filepath.Join` `+` 후 `os.*` | `path.join` `+` 후 `fs.*` | `os.path.join` `open(` | `.` 연결 후 `file_*` | `Paths.get` `File(` |
| 역직렬화 | `gob` `json.Unmarshal`(타입 혼동) | `JSON.parse`+`eval` `vm.` | `pickle` `yaml.load` | `unserialize` | `readObject` `XMLDecoder` |
| SSRF | `http.Get` `http.Client` | `fetch` `axios` `request` | `requests` `urllib` | `curl_exec` `file_get_contents` | `HttpClient` `URL.openStream` |
| 템플릿 인젝션 | `text/template` | `ejs` `pug` 동적 | `Template(` `render_template_string` | `eval` `preg_replace /e` | `FreeMarker` `Velocity` |

**리터럴 인자는 제외하고, 변수·문자열 연결만 조사 대상이다.**
`"prefix" + var` 형태는 리터럴 필터에 걸려 빠져나가므로 별도로 잡는다.

## 서버 기동 (S5 재현용)

프로젝트마다 다르다. `ENV.md`의 `START_CMD` / `STOP_CMD`에 적는다.
저장소에 `CONTRIBUTING.md`, `Makefile`, `docker-compose.yml`,
`.claude/CLAUDE.md`, `AGENTS.md` 같은 개발 문서가 있으면 거기서 찾는다.

기동에 쓰는 포트도 `ENV.md`에 적어둔다 — S5 종료 시 정리해야 한다.
