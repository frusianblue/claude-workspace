# Find-AsisPath v8 실행 가이드

AS-IS 하드코딩 경로(d:/ 형태) 전수 검색 → 증적 리포트(.dat) 생성.
경로/IP 치환 작업의 **0단계(전수 조사)** 와 **최종 검증(치환 후 0건 확인)** 에 사용.

---

## 1. 실행 방법 (자주 쓰는 순서)

```powershell
# ① 소스 1개 전수조사 (Scope 생략 = all: 텍스트+CLASS+아카이브 전부)
.\Find-AsisPath-v8.ps1 -Root "D:\src\portal"

# ② 소스 1개, 소스 파일만 (치환 직전·직후 증적용 — 빌드산출물 제외)
.\Find-AsisPath-v8.ps1 -Root "D:\src\portal" -Scope src

# ③ 소스 여러 개 일괄 조사 (목록 파일 사용, 증적은 소스별 파일로 분리)
.\Find-AsisPath-v8.ps1 -RootList ".\RootList\roots.dat"

# ④ 일괄 조사 + 증적을 지정 폴더에 모으기 (폴더 없으면 자동 생성)
.\Find-AsisPath-v8.ps1 -RootList ".\RootList\roots.dat" -Out ".\증적\asis.dat"

# ⑤ 재빌드 후 산출물 검증 (구경로 0건 목표)
.\Find-AsisPath-v8.ps1 -Root "D:\src\portal" -Scope build -Out ".\증적\portal_after.dat"

# ⑥ 특정 하위 폴더만 조사 (예: exploded 배포 WEB-INF — 반드시 기본 Scope로!)
.\Find-AsisPath-v8.ps1 -Root "D:\deploy\portal\WEB-INF"
```

실행하면 첫 줄에 `===== Find-AsisPath v8 =====` 배너 + 검색 범위·제외 목록이 출력된다.
배너에 v8이 안 보이면 예전 파일을 실행한 것.

---

## 2. 파라미터와 기본값

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `-Root` | `C:\pgms` | 조사할 폴더 1개. 하위 전체 재귀 검색. 소스 루트가 아닌 하위 폴더(WEB-INF 등)도 가능 |
| `-RootList` | (없음) | 소스 목록 파일. **지정하면 -Root는 무시**되고 일괄 모드로 동작 |
| `-Scope` | `all` | 검색 범위. `all` / `src` / `build` (아래 3번 표) |
| `-Out` | `asis_path_report.dat` | 리포트 파일. csv 아닌 **.dat** 유지(회사 DRM). 폴더 경로 포함 시 폴더 자동 생성 |
| `-Pattern` | `(?<![a-zA-Z0-9])[dD]:[/\\]` | 검색 정규식. 치환 후 특정 구경로 검증 시 교체 가능 (예: `"d:[/\\]eos"` — `\.` 이스케이프 주의) |
| `-ExcludeDirs` | `.git .svn .metadata node_modules bak backup` | 제외 폴더명. `-Scope src`이면 `target bin build classes dist` 자동 추가 |
| `-ExcludeFiles` | `*.bak, *.back` | 제외 파일명 패턴. 예: `-ExcludeFiles @('*.bak','*.back','*_old.*','*백업*')` |

- 치환 스크립트가 만드는 백업 폴더(`*_backup_path_*`, `*_backup_ip_*`)는 항상 자동 제외.
- `-ExcludeDirs`를 직접 주면 기본값을 **대체**하므로 기본 목록에 추가하는 형태로 쓸 것.
- 주의: `backup`/`bak`이라는 이름의 폴더에 실제 코드가 있는 소스라면 해당 소스만 `-ExcludeDirs`에서 그 이름을 빼고 실행.

---

## 3. Scope 선택 기준

| Scope | 검색 대상 | 용도 |
|---|---|---|
| `all` (기본값) | 텍스트 + .class + jar/war/ear/zip | 소스 1건 **최초 전수조사** (전체 그림 + 소스유실 탐지), WEB-INF 등 배포 폴더 조사 |
| `src` | 텍스트 파일만 (빌드산출물 폴더 제외) | 치환 **직전·직후 소스 증적** |
| `build` | .class + 아카이브만 | **재빌드 후 검증** — 구경로 0건 확인 |

**[함정] WEB-INF 조사 시 `-Scope src` 금지.** src 모드는 `classes` 폴더를 제외하므로
`WEB-INF\classes`의 properties/xml을 전부 놓친다 → 기본값(all)으로 실행할 것.

---

## 4. RootList 일괄 모드

`roots.dat` 형식 — 한 줄에 폴더 경로 하나, `#` 주석 가능:

```
# 30개 소스 목록
D:\AppDev\workspace-egov\portal
D:\AppDev\workspace-egov\admin
D:\AppDev\workspace-old\web
```

- 목록의 **폴더 하나당 증적 파일 하나** 생성: `<소스폴더명>_<Out파일명>`
  - 예: `-Out ".\증적\asis.dat"` → `증적\portal_asis.dat`, `증적\admin_asis.dat`, ...
- 폴더명이 중복되면 자동 순번(`web_asis.dat`, `web_2_asis.dat`) + 경고 출력.
  가급적 roots.dat에서 상위 폴더명이 다른 경로로 구분해 둘 것.
- 존재하지 않는 경로는 경고 후 건너뜀. 마지막에 소스별 검출 건수 요약표 출력.

---

## 5. 리포트(.dat) 읽는 법

컬럼: `FoundIn / Action / Container / Category / Ext / RelPath / File / Entry / Line / Match`

| FoundIn | Action | 의미 |
|---|---|---|
| FILE | 직접수정 | 텍스트 파일 — **치환 대상** (Replace 스크립트/이클립스) |
| CLASS | 재빌드 | 컴파일된 class — 소스 수정 후 재빌드로 해소 |
| WAR/JAR/EAR/ZIP | 재패키징 | 아카이브 내부 — 재패키징으로 해소. Container 컬럼 = 아카이브 체인 |

- **CLASS에서만 검출 + 대응 java 없음 = 소스 유실분** → 디컴파일(CFR) 회부 목록으로.
- 엑셀 확인은 **텍스트 나누기(쉼표)로 조회 전용** — 엑셀에서 저장 금지(DRM 암호화됨).

---

## 6. 환경별 실행

**집 (테스트 환경)**
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Find-AsisPath-v8.ps1 -Root "D:\src\portal"
```

**회사 (폐쇄망, bat 차단)**
1. 스크립트를 텍스트로 반입 → PowerShell ISE에 붙여넣기 (UTF-8 BOM 유지)
2. 콘솔에서 `Set-ExecutionPolicy -Scope Process Bypass`
3. F5 실행 — 파라미터는 못 넘기므로 상단 `param()` 블록의 기본값을 직접 수정:
   ```powershell
   [string]$Root     = "D:\src\portal",        # 또는
   [string]$RootList = "D:\작업\roots.dat",     # 일괄 모드
   [string]$Out      = "D:\작업\증적\asis.dat",
   ```

---

## 7. 표준 흐름에서의 위치 (소스 1건당)

```
0. Find (기본 Scope=all)        → 전수조사 증적 + 매핑표 재료 + 소스유실 탐지
1. 경로 매핑표 작성              → Replace-AsisPath DryRun→Apply→재DryRun 0건
2. IP 매핑표                    → Replace-AsisIp DryRun→Apply→재DryRun 0건
3. 재빌드
4. Find -Scope build            → 구경로/OldIP 0건 확인 (치환 후 증적)
5. 파일 외 확인                  → DB 설정 테이블 / LENA·workers.properties / hosts / 방화벽
```
