# tools — MAR/EOS 이관 작업 도구 모음

> 정리: 2026-08-13
> 두 계열이 한 소스에 함께 적용된다.
> **A 계열** = AS-IS 경로/IP 치환 · **B 계열** = 한글 인코딩 진단

---

## 폴더 지도

```
tools/
├── asis-replace/          A 계열 — 경로/IP 치환
│   ├── RootList/          일괄 실행 목록 (roots.dat, replace_targets.dat)
│   └── mapping/           매핑표 양식 (path_mapping_예시.dat, ip_mapping_예시.dat)
├── encoding/              B 계열 — 인코딩 진단·변환
├── docs/                  절차서·가이드
├── common/                (예정) ClassParser.psm1 — 상수풀 파서 공용 모듈
└── _deprecated/           폐기. 실행하지 말 것. 삭제도 하지 말 것
```

모든 `.ps1`·`.dat`은 **UTF-8 with BOM / CRLF**로 저장돼 있다.
PS 5.1은 BOM 없는 파일을 MS949로 읽어 엉뚱한 구문 오류를 낸다 — 편집 후 저장할 때 이 인코딩을 유지할 것.

각 스크립트 첫 15줄에 **표준 헤더**(계열/단계/역할/입력/출력/선행/상태)가 붙어 있다.
파일을 열면 무슨 일을 하는 물건인지 바로 보이도록 한 것이다.

---

## 소스 1건 처리 순서

```
[1회]  0. 착수 준비        Phase0 + Phase6 + 배너/BOM 확인
─────────────────────────────────────────────────────────────
[반복]  1. 원본 동결        스냅샷 복사 + SHA256
        2. 인벤토리        구조 / 컴파일 레벨 / build.xml encoding 수집
        3. 세대 대조 ★     Compare-SourceTrees → lev1 → lev2 → Phase2
        4. 현황 조사       Scan-JavaSources / Scan-ClassFiles / Find-AsisPath(all)
                           Phase1(파일명 실측) / Phase3(가설 판정)
─────── 여기까지 전부 읽기 전용. 아래부터 파일을 건드린다 ───────
        5. 인코딩 통일     Phase4 -Convert
        6. 경로·IP 치환    Extract-MappingDraft → Replace-AsisPath → Replace-AsisIp
        7. 재빌드          ant clean compile war
        8. 검증            Scan-ClassFiles(Broken 0) / Replace 재DryRun 0건
                           Find -Scope build / Phase2 배포 대조
```

### ★ 5번이 6번보다 먼저인 이유

`Replace-AsisPath -Apply`는 소스 옆에 `<소스명>_backup_path_<시각>\` 롤백용 백업을 만든다.
Find/Replace는 이 폴더를 자동 제외하지만, `Phase4-Convert-SourceEncoding.ps1`에는
그 제외가 **없었다**(2026-08-13 패치로 추가). 순서가 뒤바뀌면 인코딩 변환이 백업까지 훑어서
**롤백용 백업이 원본과 다른 인코딩으로 오염된다.**

인코딩 변환을 먼저 하면 이 문제가 원천적으로 발생하지 않는다.

### ★ 3번이 관문인 이유

배포 class와 다른 세대의 소스를 아무리 정확히 인코딩 판별해도 결과는 무의미하다.
`소스없음` / `시그니처불일치`가 유의미하게 나오면 **여기서 멈춘다.**
그 목록이 곧 디컴파일(CFR) 회부 명단이 된다.

---

## 단계별 명령

### 0. 착수 준비 (전체 1회 — 소스별 반복 아님)

```powershell
Set-ExecutionPolicy -Scope Process Bypass
. .\encoding\Phase0-Init-EncodingConsole.ps1          # 점(.) 소싱 필수
.\encoding\Phase6-Invoke-ReproMatrix.ps1 -JavacHome "C:\java\jdk-1.8.0.332"
```

Phase6를 **여기서** 돌리는 이유: 검출기가 고장난 채 30개를 스캔하면 "깨짐 0건"이 전부 거짓이고
30개를 다시 돌려야 한다. 2026-08-12에 실제로 겪은 사고다.
대조군에서 `깨짐(Latin1)`이 제대로 나오는 걸 확인한 뒤 시작한다.

스크립트 BOM 확인:

```powershell
Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { "BOM 없음: $($_.FullName)" }
}
```

### 1~2. 원본 동결 · 인벤토리

읽기전용 사본 + SHA256 목록을 뜬다. 이후 모든 쓰기 작업은 사본에서.
이중 변환 사고는 `.bak`으로 못 되돌린다(이미 UTF-8인 걸 MS949로 재해석하면 백업도 오염 세대).

소스별로 수집:

| 항목 | 확인 방법 |
|---|---|
| 받은 구성 | 소스만 / 소스+배포본 / 배포본만 |
| 컴파일 레벨 | `javap -verbose ... \| Select-String major` (50=1.6, 51=1.7, 52=1.8) |
| javac encoding | `build.xml`의 `<javac encoding>` — **속성 자체가 없으면 플랫폼 기본(MS949)** |
| 소스 레이아웃 | Maven 표준 / 레거시 Ant(WebContent) |

### 3. 세대 대조 ★

```powershell
.\encoding\Compare-SourceTrees.ps1 -LeftRoot <형상> -RightRoot <WAS>
.\encoding\Compare-SourceToClass-lev1.ps1 -ClassRoot "<WAS>\WEB-INF\classes" -SrcRoot "<형상>\src"
.\encoding\Compare-SourceToClass-lev2.ps1 -SrcRoot ... -ClassRoot ... -LibDir ... -JdkHome ... -TargetFile .\targets.txt
.\encoding\Phase2-Compare-Deployment.ps1 -LocalClasses ... -DeployRoot ...
```

lev2는 **lev1이 추린 대상만.** `-All`은 30개 소스에서 비현실적이다.

### 4. 현황 조사 (읽기 전용)

```powershell
.\encoding\Scan-JavaSources.ps1 -Root "<형상>\src"
.\encoding\Scan-ClassFiles.ps1  -Root "<WAS>\WEB-INF\classes" -SourceRoot "<형상>\src"
.\asis-replace\Find-AsisPath.ps1 -Root "<소스루트>"                # Scope 생략 = all
.\encoding\Phase1-Get-TargetFilenameBytes.ps1 -Path "D:\upload" -Recurse
.\encoding\Phase3-Invoke-Diagnosis.ps1 -AllDat ... -ConstantsPattern ... -ControllerPattern ...
```

운영 jar/war 내부까지 볼 때:

```powershell
.\encoding\Expand-ArchivesForScan.ps1 -Root "D:\lena\...\webapps" -Out .\_arc
.\encoding\Scan-ClassFiles.ps1 -Root .\_arc
```

**게이트 둘**
- 소스 `손상(FFFD)` → 변환해도 복구 불가. 원본 재확보 대상으로 분리
- class `손실(FFFD)` → 재컴파일로만 해소. 대응 소스 없으면 3단계 명단에 합류

### 5. 인코딩 통일

```powershell
.\encoding\Phase4-Convert-SourceEncoding.ps1 -SrcPath "<소스>\src"                      # 분류만
.\encoding\Phase4-Convert-SourceEncoding.ps1 -SrcPath "<소스>\src" -Convert -StripBom `
    -BackupRoot "D:\backup\src"                                                          # 변환
```

`-BackupRoot`는 반드시 **소스 트리 밖**으로. 안쪽이면 스크립트가 중단시킨다.

### 6. 경로·IP 치환

```powershell
.\asis-replace\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Path
# → New 열을 채워 mapping\path_mapping_portal.dat 로 저장 (UTF-8 BOM)

.\asis-replace\Replace-AsisPath.ps1 -Root "<소스>" -Map .\mapping\path_mapping_portal.dat
.\asis-replace\Replace-AsisPath.ps1 -Root "<소스>" -Map .\mapping\path_mapping_portal.dat -Apply
.\asis-replace\Replace-AsisPath.ps1 -Root "<소스>" -Map .\mapping\path_mapping_portal.dat   # 재DryRun 0건 확인

.\asis-replace\Replace-AsisIp.ps1 -RootList .\RootList\roots.dat -Map .\mapping\ip_mapping_운영.dat -Apply
```

### 7~8. 재빌드·검증

| 단계 | 완료 판정 |
|---|---|
| 5 | 재스캔 시 `MS949(추정)` 0건, BOM 0건 |
| 6 | Replace **재DryRun 치환 0건** (Find 재실행이 아님 — 새 경로도 `d:/`라 검출된다) |
| 7 | `ant clean compile war` 성공 + `bootstrap class path not set` 경고 없음 |
| 8 | `Scan-ClassFiles` Broken **0** / `Find -Scope build` 구경로 0건 / Phase2 해시 일치 |

부분 빌드 금지 — `static final String`은 컴파일 타임에 참조 클래스로 인라이닝되므로
반드시 clean 후 전체 빌드한다.

---

## 이번 정리에서 적용한 패치

| # | 파일 | 내용 |
|---|---|---|
| 1 | `encoding/Compare-SourceToClass-lev2.ps1` | `Get-ClassMajor`의 `-shl`에 `[int]` 캐스팅. 8/12에 전면 교체한 패턴이 여기만 남아 있었다. major가 256 미만이라 우연히 맞고 있었을 뿐 |
| 2 | `encoding/Phase4-Convert-SourceEncoding.ps1` | `-ExcludeDirs` 추가 + 치환 백업 폴더(`*_backup_path_*`, `*_backup_ip_*`) 자동 제외 + BackupRoot가 소스 트리 안이면 중단 |
| 3 | `asis-replace/Extract-MappingDraft.ps1` | 신규. `Folder-Check` + `Ip-Check` + 실행메모 본문 스니펫 3벌 통합. 기존 스니펫은 입력 파일명이 실제 리포트명과 달라 그대로는 실행되지 않았다 |
| 4 | `encoding/Expand-ArchivesForScan.ps1` | 신규. jar/war 내부 class 추출 → 기존 `Scan-ClassFiles`에 그대로 투입. `Check-ClassEncoding`의 `-IncludeArchives` 자리를 메운다 |
| 5 | 데이터 파일 | 2벌씩 있던 `roots.dat`/`replace_targets.dat`/`path_mapping_예시.dat` 단일화. `ip_mapping.dat` → `ip_mapping_예시.dat` 개명(내용이 예시인데 실물처럼 보였다) |
| 6 | 전 파일 | 표준 헤더 배너 삽입, UTF-8 BOM + CRLF 통일, 파일명 버전 접미사 제거 |
| 7 | `encoding/Phase6-Invoke-ReproMatrix.ps1` | `-ScanScript` 기본값을 `$PSScriptRoot` 기준으로 (폴더 분리 후 `.\Scan-ClassFiles.ps1`을 못 찾던 문제) + `WorkDir` 절대경로 확정 |
| 8 | 전 스크립트 (18개) | `[Environment]::CurrentDirectory` 를 PS 현재 위치와 동기화 — 아래 참조 |
| 9 | `common/ClassParser.psm1` | **신규.** 상수풀 파싱·깨짐 판정 단일 원본. 4벌 복제 구조 해소 시작 |
| 10 | `common/Test-ClassParser.ps1` | **신규.** 모듈 자체 검증(10항목). JDK 없이 판정 로직만 즉시 검증 — 도입 전 게이트 |
| 11 | `encoding/Compare-SourceToClass-lev1.ps1` | **오탐 수정.** 깨짐 판정을 모듈로 위임. 구 로직은 Latin-1 검사가 한글 검사보다 앞서 있어 `·`(U+00B7)가 섞인 정상 한글을 깨짐으로 오판했다 |
| 12 | `encoding/Compare-SourceToClass-lev2.ps1` | 자체 `Get-ClassMajor` 제거 → 모듈 사용 |

### ★ PowerShell 위치 ≠ .NET 위치

`New-Item` 같은 cmdlet은 PS의 `Get-Location` 기준으로 상대경로를 풀지만,
`[System.IO.File]::WriteAllText/WriteAllBytes/WriteAllLines` 같은 **.NET 정적 메서드는
`[Environment]::CurrentDirectory` 기준**으로 푼다. 이 값은 **프로세스 시작 시점에 고정**되고
`cd`(Set-Location)를 따라오지 않는다.

그래서 `C:\Users\<계정>`에서 powershell을 켠 뒤 `cd D:\tools`로 옮겨와 실행하면,
`New-Item`이 만든 `D:\tools\repro-matrix\`와 `WriteAllText`가 쓰려는
`C:\Users\<계정>\repro-matrix\`가 어긋나 `DirectoryNotFoundException`이 난다.

**폴더에서 바로 powershell을 열면 우연히 동작하고, cd로 들어가면 실패한다** — 재현이 들쭉날쭉해서
원인을 찾기 어려운 유형이다. 이 도구 모음의 리포트 출력은 대부분 .NET 쓰기라 광범위하게 영향받으므로,
`param()` 직후에 아래 한 줄을 넣어 두 세계를 일치시켰다.

```powershell
[Environment]::CurrentDirectory = (Get-Location).ProviderPath
```

앞으로 새 스크립트를 만들 때도 이 줄을 넣을 것. `Export-Csv`/`Out-File` 같은 cmdlet만 쓰면
문제가 없지만, 한 파일에 두 방식이 섞이면 반드시 어긋난다.

**패치 1·2는 PowerShell 실행 검증을 하지 못했다** (작업 환경에 PS 없음).
`Get-ClassMajor`는 반환값이 50/51/52로 나오는지, Phase4는 `-ExcludeDirs` 없이 분류만 돌려
건수가 이전과 같은지 먼저 확인하고 쓸 것. 두 변경 모두 표시가 `[PATCH 2026-08-13]`으로 남아 있다.

---

## 남은 조치 (미적용)

| # | 조치 | 이유 |
|---|---|---|
| 1 | `Scan-ClassFiles` / `Scan-JavaSources`에 `-RootList` 추가 | 30개 소스 일괄. Find v8.2의 규칙(소스별 리포트 분리, 폴더명 중복 시 `_2` + 경고) 그대로 이식 |
| 2 | `ClassParser.psm1` 공용 모듈화 | 상수풀 파서가 4벌(`Scan-ClassFiles`, `Check-ClassEncoding`, `lev1`, `lev2`)로 복제돼 있다. 이번 `-shl` 누락이 그 구조 때문에 생겼다 |
| 3 | `Convert-ToUtf8`의 `-Extensions`를 Phase4로 이식 | `.properties`/`.jsp`/`.xml`까지 한 번에 훑는 기능이 Phase4엔 없다 |
| 4 | `docs/IP치환_전체과정_가이드.md` v5 기준 갱신 | v4 시절 문서라 백업 폴더명·리포트 경로·`-RootList`가 실제와 다르다 |

1~2는 첫 소스를 돌려보면서 병행해도 되지만, **2번은 다음 파서 버그가 나기 전에** 끝내는 게 좋다.
