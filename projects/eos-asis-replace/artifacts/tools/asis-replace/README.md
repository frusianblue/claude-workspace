# asis-replace — AS-IS 경로/IP 치환 (A 계열)

| 파일 | 단계 | 역할 |
|---|---|---|
| `Find-AsisPath.ps1` (v9) | A-1 | 전수조사. `-Kind path,unc,ip,port,domain,host`, `-Scope all/src/build`, `-RootList` 일괄, jar/war 중첩 내부까지 |
| `Extract-MappingDraft.ps1` (v2) | A-2 | Find 리포트에서 매핑표 초안 추출 (`-Mode Path\|Ip\|Domain\|Port`) |
| `Replace-AsisPath.ps1` (v4) | A-3 | 경로 치환(드라이브 + UNC/NAS). DryRun 기본, `-Apply` 시 자동 백업 |
| `Replace-AsisIp.ps1` (v5) | A-4 | IP 치환. `-UsePort`로 `IP:포트` 규칙 우선 |
| `RootList/roots.dat` | 입력 | Find·ReplaceIp 일괄 목록 (한 줄 = 소스 경로) |
| `RootList/replace_targets.dat` | 입력 | ReplacePath 일괄 목록 (`소스경로,매핑파일`) |
| `mapping/path_mapping_예시.dat` | 입력 | 경로 매핑표 양식 (드라이브 + UNC) |
| `mapping/ip_mapping_예시.dat` | 입력 | IP 매핑표 양식 (내용은 예시 데이터) |

## v9/v4/v2에서 추가된 것

**1. NAS·네트워크 폴더**

- 조사: `-Kind unc` — `\\nas\share`, `\\192.168.1.50\backup`, `\\\\nas\\share`(java 리터럴), `//nas/share`
- 조사: `-Kind path` 의 드라이브가 `d:` 고정에서 **A-Z 전부**로 (`W:\ Z:\ X:\ T:\ Y:\` 자동 검출).
  좁히려면 `-Drives "d,w,x,y,z"`
- 치환: 매핑표 OldPath/NewPath에 UNC를 쓸 수 있고, **드라이브↔UNC 교차 매핑**도 된다
  (`w:/data,\\nas01\data` / `\\nas-old\pub,x:/pub`)

**2. IP·포트·도메인**

- `-Kind ip` IPv4 / `-Kind port` `port=8080`·`server.port: 9090`·`<host|ip>:8080` /
  `-Kind domain` `xxx.co.kr`·`api.company.com` / `-Kind host` 점 없는 서버명(`-Hosts WDAAD11,...`)
- 초안: `Extract-MappingDraft -Mode Domain|Port` → 인벤토리(.dat).
  포트 치환은 ReplaceIp의 `OldPort/NewPort` + `-UsePort`, 도메인은 아직 전용 치환 스크립트 없음(수동/체크리스트)

**3. 리포트 컬럼**: `Kind`(무엇이) / `Value`(매칭된 값 그 자체) / `Target`(뿌리: `d:` `\\nas01` `192.168.1.11` `8080`)
추가. A-2가 줄 텍스트를 다시 파싱하지 않고 이 컬럼을 바로 먹는다 (v8.2 리포트를 넣으면 자동 폴백).

## 표준 흐름

```
A-1 Find (-Kind all)  → 전수조사 증적 + 매핑표 재료 + 소스유실 탐지
A-2 Extract -Mode Path/Ip → 초안 .dat (New 열 비어 있음, 사람이 채움)
A-3 Replace-AsisPath  DryRun → 리포트 검토 → -Apply → 재DryRun 0건
A-4 Replace-AsisIp    DryRun → -Apply → 재DryRun 0건
    재빌드 → Find -Scope build 로 산출물 검증 → 파일 외(DB·WAS·hosts·방화벽)
```

## 규칙

- **DryRun → 리포트 검토 → `-Apply` → 재DryRun 0건** 순서를 건너뛰지 않는다
- 치환 완료 증적은 **Replace 재DryRun 0건**으로 남긴다.
  치환 후 Find를 전체 패턴으로 다시 돌리면 새 경로(`d:/app/...`)도 `d:/`라 검출된다
- 조사는 전체(all), 치환은 텍스트만 — class/jar/war는 재빌드·재패키징으로 해소
- 매핑 `.dat`도 **UTF-8 BOM** 저장 (PS 5.1이 BOM 없는 UTF-8을 ANSI로 읽어 한글 비고가 깨짐)
- `-ExcludeDirs`를 직접 지정하면 기본값이 **대체**된다 (추가 아님)
- **[함정] WEB-INF 단독 조사 시 `-Scope src` 금지** — classes 폴더 제외 때문에 `WEB-INF\classes`를 놓친다
- **[한계] 구분자가 백슬래시 3개 이상**(이중 이스케이프 `d:\\\\eos`)인 표기는 치환되지 않고
  **UNMAPPED로 올라온다** — 리포트에서 보고 수동 처리할 것 (조사(Find)에서는 잡힌다)
- **[한계] IP 조사는 버전번호(`1.2.3.4`)·`127.0.0.1`을 걸러주지 않는다** — 매핑표에 넣기 전 눈으로 선별
- UNC 매핑에 공유명 없이 서버만 쓰면(`\\nas-old`) 그 서버로 시작하는 **모든 경로**가 바뀐다 → 경고가 뜬다

## 회사(폐쇄망, bat 차단)

스크립트를 텍스트로 반입 → ISE에 붙여넣기(**UTF-8 BOM 유지**) → `param()` 기본값 직접 수정 후 F5.
실행 첫 줄 배너(`===== Replace-AsisPath v4 =====`)로 버전을 확인한다 — 안 보이면 구버전이다.

`powershell -File` 로 돌릴 땐 배열 파라미터가 문자열 하나로 뭉개지는데,
v9/v4/v2는 콤마를 직접 쪼개므로 `-Kind ip,port,domain` `-Drives "d,w,z"` 가 그대로 먹는다.

## 검증 상태 (2026-08-18)

- PS 7.4(컨테이너)에서 v9/v4/v2 실행 검증: UNC·매핑드라이브·교차매핑 풀사이클
  (DryRun → Apply → **재DryRun 치환 0건**), 백업본 md5 = 원본, EUC-KR 한글 파일 바이트 보존,
  java 리터럴 `\\\\nas\\share` ↔ 일반 `\\nas\share` 스타일 각각 보존,
  `http://nasweb/share`·`forward:/eos`·`d:/eosdata` 오탐 0
- **PS 5.1 실기기 검증은 아직** — 반입 전에 집에서 한 바퀴 돌려볼 것
