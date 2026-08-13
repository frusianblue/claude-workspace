# RUNBOOK — MAR/EOS 한글 인코딩 이슈 실행 절차서

> HANDOFF.md의 A~E 순서를 **Phase 0~6**으로 재배열하고, 각 단계의 실행 스크립트를 분리한 문서
> 최초 작성: 2026-08-04 · **최종 갱신: 2026-08-12**

---

## 현재 상태 (2026-08-12 측정 기준)

| 항목 | 결과 |
|---|---|
| 측정 대상 | `lena-encoding-test` 빌드 산출물 (`build/classes`, 8개 클래스) |
| 상수 풀 깨짐 | **0건** (major 50 / 1.6 타깃 확인) |
| 판정 | **가설 3** — 상수 풀 정상, 컴파일 단계 무혐의 |
| 다음 조치 | Phase 2-3·2-4 확인 → **Phase 5 D-1(런타임)으로 직행** |

> **판정 근거가 갱신되었다.** 8/4 버전 Phase 2-1 파서에는 결함이 있었고(아래 참조),
> 그 파서로 나온 이전 측정치는 근거로 쓸 수 없다. 위 결과는 교체된 파서로 재측정한 값이다.

### 8/4 판정 도구의 결함 (재측정이 필요했던 이유)

구 Phase 2-1 파서와 `Scan-ClassFiles.ps1` 초판은 상수 풀의 2바이트 값을 이렇게 읽었다.

```powershell
$cpCount = ($b[8] -shl 8) -bor $b[9]     # 잘못됨
```

PowerShell은 `-shl`의 결과 타입을 **왼쪽 피연산자 타입으로 유지**한다.
`[byte]`를 8비트 밀면 byte 범위를 넘어 **0으로 잘린다.** 결과적으로 모든 2바이트
big-endian 값이 하위 바이트만 읽혔다.

| 영향 | 증상 |
|---|---|
| `major` | 50, 52 등 256 미만이라 **우연히 맞았음** (그래서 발견이 늦음) |
| `cpCount` | 상수 풀 256개 이상 클래스에서 루프가 조기 종료 → **리터럴 누락** |
| Utf8 `len` | 256바이트 이상 문자열에서 desync → 파일이 결과에서 **통째로 누락** |

실측: 실제 jar에서 추출한 class 4,658개 대상 → 파싱 실패 **39건**, 리터럴 수 불일치 **582건**.
`[int]` 캐스팅 후 → 파싱 실패 **0건**, 불일치 **0건**.

**"깨짐 0건"이 진짜인지 못 읽은 것인지 구분되지 않으므로, 8/4~8/11 사이의 측정 결과는 전부 무효로 간주한다.**

또한 구 판정 로직은 문자 범위(`[\u00A1-\u00FF]`)로 깨짐을 추정해서,
`·`(U+00B7) `é` `€` 같은 **정상 특수문자를 깨짐으로 오판**했다.
현재는 역변환 검증 방식으로 교체되어 오탐이 없다.

---

## 스크립트 구성

| Phase | 스크립트 | 필수 여부 |
|---|---|---|
| 0 | `scripts/Phase0-Init-EncodingConsole.ps1` | 필수 · 최우선 |
| 1 | `scripts/Phase1-Get-TargetFilenameBytes.ps1` | 필수 |
| 1 | `scripts/Phase1-Test-LegacyMangle.ps1` | 필수 |
| 2 | `scripts/Scan-ClassFiles.ps1` | 필수 (핵심 도구) |
| 2 | `scripts/Phase2-Compare-Deployment.ps1` | 가설 3 판별용 |
| 3 | `scripts/Phase3-Invoke-Diagnosis.ps1` | 필수 |
| 4 | `scripts/Phase4-Convert-SourceEncoding.ps1` | 가설 2일 때만 |
| 5 | (수동 절차 — 아래 참조) | 가설 1·2일 때 |
| 6 | `scripts/Phase6-Invoke-ReproMatrix.ps1` | 병렬 가능 |

---

## 실행 전 공통 준비

### 1) 실행 정책

```powershell
# 가장 간단 — 별도 프로세스로 우회 (관리자 권한 불필요)
powershell -ExecutionPolicy Bypass -File .\scripts\Scan-ClassFiles.ps1 -Root "D:\..."

# 또는 현재 창에서만 (창 닫으면 원복)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

`Get-ExecutionPolicy -List`에서 `MachinePolicy`에 값이 박혀 있으면 GPO 강제라
`-ExecutionPolicy Bypass`도 무시될 수 있다. 그때는 스크립트 내용을 콘솔에 붙여넣어 실행한다
(붙여넣기는 정책 적용 대상이 아니다).

`RemoteSigned`인데 막히면 인터넷 출처 마크 때문이므로 `Unblock-File .\스크립트.ps1`.

### 2) 스크립트 파일은 UTF-8 with BOM 저장 ★

Windows PowerShell 5.1은 **BOM 없는 파일을 시스템 ANSI(MS949)로 읽는다.**
그러면 주석·문자열의 한글이 깨지고, 깨진 바이트가 닫는 따옴표를 삼켜서
`"예기치 않은 토큰"` 같은 엉뚱한 구문 오류가 무더기로 발생한다.

```powershell
# 확인 — 239 187 191 이면 정상
[System.IO.File]::ReadAllBytes(".\Scan-ClassFiles.ps1")[0..2]

# 복구
$p = ".\Scan-ClassFiles.ps1"
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))
```

PowerShell 7은 BOM 없어도 UTF-8로 읽으므로 이 문제가 없다.

### 3) 결과 파일 확장자는 `.dat`

회사 PC DRM이 `csv`/`txt`를 자동 암호화한다. 모든 스크립트의 기본 출력은 `.dat`이다.

### 4) 엑셀에서 열기

Power Query / 웹 가져오기를 쓰지 말 것 (HTML로 오판한다).

> 엑셀 → 파일 → 열기 → 찾아보기 → 파일 형식 **"모든 파일"** → `.dat` 선택
> → 텍스트 마법사 자동 실행 → 구분 기호 "기타"에 `|` 입력 → 마침

---

# Phase 0 — 계측 환경 고정

> **목적**: MS949 콘솔이 `U+FFFD`와 실제 `0x3F`를 똑같이 `?`로 보여주는 문제를 차단.
> 이 단계를 건너뛰면 Phase 2·3의 **육안 판독**이 무효가 된다.

```powershell
. .\scripts\Phase0-Init-EncodingConsole.ps1     # 반드시 점(.) 소싱
```

코드 페이지, `[Console]::OutputEncoding`, `$OutputEncoding`(네이티브 프로그램 전송용),
`PSDefaultParameterValues`를 한 번에 UTF-8로 맞추고 실행 정책까지 처리한다.

**게이트**: 스크립트가 출력하는 세 줄(한글 / U+FFFD / 물음표)이 **서로 다르게** 보여야 한다.
U+FFFD와 `?`가 똑같이 보이면 콘솔 폰트를 D2Coding·Consolas 등으로 교체한다.

> 콘솔이 깨져도 **스크립트의 판정 결과 자체는 영향받지 않는다.** 판정은 바이트 기반이고
> 파일 저장은 항상 UTF-8 BOM이다. Phase 0은 육안 확인의 신뢰성을 위한 것이다.

---

# Phase 1 — 목표값 확정 (정답지 확보)

> **목적**: "UTF-8로 통일"이 목표가 아니다. **디스크에 실제로 존재하는 파일명 바이트**가 목표다.
> 여기서 나오는 결과가 Phase 5의 `CommExcelView` 처리 방침(D-1)을 사전 결정한다.

## 1-1. 디스크 파일명 바이트 덤프

```powershell
.\scripts\Phase1-Get-TargetFilenameBytes.ps1 -Path "D:\upload" -Recurse -OutFile ".\target-bytes.dat"
```

NTFS는 파일명을 UTF-16으로 저장한다. .NET이 읽어온 시점의 문자열이 '진실'이다.

| Verdict | 의미 | Phase 5 D-1 방침 |
|---|---|---|
| `정상` | 디스크 파일명이 정상 한글 | `getBytes("8859_1")` **제거** |
| `AS-IS깨짐저장` | 구 서버 방식으로 저장된 레거시 | 제거 시 기존 파일 접근 불가 → **양방향 fallback 또는 rename 배치** |
| `디스크손상` | 파일명 자체가 이미 파괴됨 | **파일 rename 선행** 필요 |
| 혼재 | 이관 전후 파일이 섞임 | **양쪽 fallback 로직** 필요 |

## 1-2. 레거시 파괴 로직 시뮬레이션

```powershell
'매출현황.xls' | .\scripts\Phase1-Test-LegacyMangle.ps1 | Format-List

(Import-Csv .\target-bytes.dat -Delimiter '|').FileName |
    .\scripts\Phase1-Test-LegacyMangle.ps1 |
    Format-Table 원본, 레거시결과, 소실여부, 왕복일치 -AutoSize
```

`new String(s.getBytes("8859_1"), "UTF-8")`이 실제로 만드는 값을 Java 없이 재현한다.

- `소실여부 = 소실(비가역)` → 그 코드 경로는 파일을 **절대** 찾을 수 없다
- `왕복일치 = Y` → 구 서버에서 동작했던 이유가 설명된다 (커넥터가 Latin-1이었음)

## 1-3. 게이트

D-1 방침을 위 표에서 확정한 뒤 Phase 2로 진행한다.

---

# Phase 2 — 현재값 측정 (상수 풀)

> **원칙**: `Scan-ClassFiles.ps1` 결과가 **1순위 근거**, `javap`은 대조용 참고.
> `Constants.class`와 참조 클래스를 **반드시 함께** 측정한다. 하나만 보면 가설 1을 검증할 수 없다.

## 2-1. 상수 풀 스캔 (핵심 도구)

```powershell
# 기본
.\scripts\Scan-ClassFiles.ps1 -Root "D:\...\WEB-INF\classes"

# 소스까지 연계 — 원본 인코딩(SrcEnc) + 리터럴 소스 라인번호(Line)
.\scripts\Scan-ClassFiles.ps1 -Root "D:\...\build\classes" `
                              -SourceRoot "D:\...\src\main\java"
```

산출물 2종이 `.\Scan-ClassFiles\` 아래에 자동 생성된다.

- `<프로젝트명>_<일시>.dat` — 파일 단위 요약
- `<프로젝트명>_<일시>-literals.dat` — 리터럴 상세 (라인번호 포함)

### 판정값

| Status | Encoding | 복원 |
|---|---|---|
| `한글정상` | `인코딩일치` | — |
| `깨짐(Latin1)` | `Latin1(UTF8소스)` | 가능 |
| `깨짐(Latin1)` | `Latin1(949소스)` | 가능 |
| `깨짐(949이중)` | `MS949오컴파일` | 가능 |
| `손실(FFFD)` | `UTF-8오컴파일` | **불가 — 원본 소스 재컴파일** |
| `파싱실패` | `파싱실패` | 판정 보류 |

### 판정 방식

문자 범위로 추정하지 않고 **"역변환이 성립하는가"**로 판정한다.
깨진 문자열만 원래 바이트로 되돌렸을 때 유효한 시퀀스로 복원되며 **길이가 줄어든다.**
덕분에 `·` `é` `€` 같은 정상 특수문자를 깨짐으로 오판하지 않는다.

### 원리상 알 수 없는 것 (도구 한계)

1. **정상 컴파일된 class의 원본 소스 인코딩** — class는 항상 modified UTF-8로 저장되므로
   정보 자체가 남지 않는다. `-SourceRoot`로 `.java`를 직접 봐야 한다 (`SrcEnc` 컬럼).
2. **리터럴의 소스 라인번호** — `LineNumberTable`은 바이트코드 오프셋 매핑이라 상수 풀과
   연결되지 않는다. `Line` 컬럼도 `.java`에서 문자열을 직접 찾아 채운다.
3. **`?` 치환(Case A 소스 오염)** — 정상 물음표와 구분 불가. Phase 4에서 육안 확인한다.

## 2-2. javap 대조 (참고용)

```powershell
javap -verbose -J-Dfile.encoding=UTF-8 -cp .\build\classes com.xxx.Constants > .\javap-dump.dat
```

`major version` 확인만이면 인코딩 설정이 필요 없다(전부 ASCII).
상수 풀의 한글까지 보려면 Phase 0을 먼저 실행하고 `-J-Dfile.encoding=UTF-8`을 붙인다.

## 2-3 / 2-4. 배포 동일성 · 중복 로딩

```powershell
.\scripts\Phase2-Compare-Deployment.ps1 `
    -LocalClasses "D:\workspace\myapp\build\classes" `
    -DeployRoot   "D:\lena\AppServer\servers\WDMDB11\webapps\myapp" `
    -TargetClass  "smart/common/Constants.class"
```

해시 불일치 = 배포 자체가 안 된 것. **이 경우 Phase 4·5의 소스 작업은 무의미하다.**
jar 버전 중복, 대상 클래스의 jar 내 중복, WAS work 캐시 잔존까지 함께 본다.

---

# Phase 3 — 분기 판정

```powershell
.\scripts\Phase3-Invoke-Diagnosis.ps1 `
    -ConstantsDat  ".\Scan-ClassFiles\constants_20260812_090000.dat" `
    -ControllerDat ".\Scan-ClassFiles\controller_20260812_090100.dat"

# 전체를 한 번에 스캔한 경우
.\scripts\Phase3-Invoke-Diagnosis.ps1 -AllDat ".\Scan-ClassFiles\app_20260812.dat" `
    -ConstantsPattern "Constant" -ControllerPattern "Controller|View"
```

## 판정 매트릭스

| Constants | Controller | 가설 | 다음 Phase |
|---|---|---|---|
| `한글정상` | `한글정상` | **3** 배포/로딩 | 2-3·2-4 → 5의 C-6, C-7만 |
| `한글정상` | 깨짐 / 구값 | **1** 인라이닝 | 4 생략 → 5의 C-4부터 |
| `손실(FFFD)` | (무관) | **2** 소스 MS949 | 4부터 전부 |
| `깨짐(Latin1)` | (무관) | **2 변형** | 4 + build.xml encoding |
| `파싱실패` | (무관) | 판정 보류 | 해당 class 먼저 확인 |

> **가설 3인데 FNFE가 계속되면 → 원인은 컴파일이 아니라 런타임(Case A).** Phase 5의 D-1로 직행한다.
> **← 2026-08-12 현재 이 경로에 해당한다.**

---

# Phase 4 — 소스 정리 *(가설 2일 때만)*

> Phase 3에서 가설 2가 아니면 이 Phase 전체를 건너뛴다.

```powershell
# 1) 분류만 (드라이런) — 기본 동작
.\scripts\Phase4-Convert-SourceEncoding.ps1 -SrcPath "D:\workspace\myapp\src"

# 2) 결과 검토 후 변환 (백업 자동 + 변환 후 검증)
.\scripts\Phase4-Convert-SourceEncoding.ps1 -SrcPath "D:\workspace\myapp\src" -Convert -StripBom
```

`Action` 컬럼이 조치를 지정한다.

| Action | 의미 |
|---|---|
| `UTF-8 변환 대상` | MS949 + 한글 보유 |
| `BOM 제거 권장` | javac 8은 UTF-8 BOM을 소스에서 인식하지 못한다 |
| `원본 손실 - 형상관리에서 복원 필요` | 소스에 이미 U+FFFD — **변환해도 복구 안 됨** |
| `UTF-16 - 수동 변환 필요` | 자동 변환 대상에서 제외 |

변환 후 `build.xml`의 `javac encoding`을 UTF-8로 맞춘 뒤 Phase 5로 진행한다.

---

# Phase 5 — 코드 수정 + 빌드 + 배포

## 5-1. 이클립스 프로젝트 인코딩

Properties → Resource → Text file encoding → UTF-8
Window → Preferences → General → Workspace → UTF-8

> 이클립스 설정은 **표시/편집용**이다. Ant 빌드 결과에는 영향을 주지 않는다.
> 실제 컴파일 인코딩은 `build.xml`의 `javac encoding` 속성이 결정한다.

## 5-2. build.xml

```xml
<property file="build.properties"/>
<property name="javac.source"   value="1.6"/>
<property name="javac.target"   value="1.6"/>
<property name="javac.encoding" value="UTF-8"/>
<property name="javac.bootcp"   value=""/>

<javac srcdir="${src.dir}" destdir="${classes.dir}"
       source="${javac.source}" target="${javac.target}"
       encoding="${javac.encoding}"
       bootclasspath="${javac.bootcp}"
       includeantruntime="false">
```

### AS-IS 컴파일 레벨을 맞출 때

AS-IS 소스가 1.6과 1.7이 섞여 있으므로 프로젝트별로 `build.properties`에 지정한다.

```properties
javac.source=1.7
javac.target=1.7
javac.bootcp=D:/AppDev/Bin/java_home/java-se-7u75-ri/jre/lib/rt.jar
```

`source`/`target`만 지정하면 **API 세트는 컴파일 JDK의 것**이 그대로 쓰인다.
`bootclasspath`를 지정해야 실제로 그 레벨의 API로 제한되고,
`warning: bootstrap class path not set` 경고도 사라진다.

> `javac.bootcp` 경로가 없는 PC에서 빌드하면 javac는 `bad path element` 경고만 내고
> **조용히 무시한다.** 에러가 아니므로 눈치채지 못한 채 상위 JDK API로 컴파일될 수 있다.
> 공용 빌드라면 `<available>` + `<fail>`로 존재를 검증할 것.

원본 class의 실제 레벨 확인:

```powershell
javap -verbose -cp .\build\classes com.xxx.Foo | Select-String "major"
# 50 = 1.6 / 51 = 1.7 / 52 = 1.8
```

## 5-3. 코드 수정 (빌드 전에 반영)

### D-1. `CommExcelView`의 `getBytes("8859_1")`

**Phase 1-3에서 결정된 방침**에 따라 분기한다.

```java
// ── 방침 A: 디스크 파일명이 정상 한글 → 변환 제거
String fileName = getFileName();   // 그대로 사용

// ── 방침 B: 레거시 파일이 깨진 채 저장돼 있음 → 양방향 fallback
File f = new File(baseDir, fileName);
if (!f.exists()) {
    String legacy = new String(fileName.getBytes("MS949"), "ISO-8859-1");
    File lf = new File(baseDir, legacy);
    if (lf.exists()) { f = lf; }
}

// ── 방침 C: 요청 파라미터가 Latin-1로 도착 → 커넥터 설정으로 해결
//    코드가 아니라 LENA 커넥터의 URIEncoding / useBodyEncodingForURI
```

> 커넥터가 UTF-8이면 파라미터는 이미 정상 String이므로 `getBytes("8859_1")`은 순수 파괴 행위다.

**POST 본문은 커넥터 `URIEncoding`이 아니라 `CharacterEncodingFilter`가 처리한다.**
web.xml에서 이 필터가 `LucyXSSFilter`보다 **앞에** 있어야 한다.
순서가 뒤바뀌면 `setCharacterEncoding` 호출 전에 파라미터가 파싱되어
기본 인코딩(ISO-8859-1)으로 굳는다.

### 진단용 — 문자열이 깨진 건지 로그만 깨진 건지 구분

```java
log.info("[REQ] hex = " + EncodingUtil.toUnicodeHex(path));
File f = new File(path);
log.info("[FILE] exists = " + f.exists());
log.info("[FILE] abs hex = " + EncodingUtil.toUnicodeHex(f.getAbsolutePath()));
```

- `U+B9E4 U+CD9C ...` → 문자열 정상. **로그 출력 인코딩** 또는 경로 자체 문제
- `U+00EB U+00A7 ...` → request 파라미터 유입 지점에서 이미 깨짐

hex는 ASCII라 어떤 콘솔에서도 안 깨진다. 인코딩 문제를 인코딩에 의존하지 않고 볼 수 있다.

> **`sun.jnu.encoding`에 대한 정정 (8/12)**
> 리눅스에서는 파일 경로 인코딩을 지배하지만, **윈도우에서는 영향이 제한적**이다.
> JDK의 윈도우 파일 I/O는 ANSI가 아니라 Unicode(WCHAR) Win32 API를 사용하므로
> Java String이 UTF-16 그대로 전달되고 `sun.jnu.encoding` 변환을 거치지 않는다.
> 따라서 FNFE의 원인을 이 속성으로 단정하지 말고, 위 hex 로그로 먼저 구분할 것.

### D-2. `Content-Disposition` 헤더

```java
String encoded = URLEncoder.encode(fileName, "UTF-8").replaceAll("\\+", "%20");
response.setHeader("Content-Disposition",
    "attachment; filename=\"" + encoded + "\"; filename*=UTF-8''" + encoded);
```

> **D-1과 D-2는 별개 문제다.** D-2는 브라우저 저장 파일명(표시)에 영향을 주고,
> **FNFE는 D-1(서버 디스크 파일 검색) 문제다.** D-2를 고쳐도 FNFE는 사라지지 않는다.

## 5-4. Clean → Full Build

```powershell
ant clean compile war
```

부분 빌드는 가설 1(인라이닝)을 재발시킨다. `static final String` 상수는
컴파일 타임에 참조 클래스로 복사되므로 **반드시 clean 후 전체 빌드**한다.

## 5-5. 로컬 검증 — 배포 전 필수 게이트

```powershell
.\scripts\Scan-ClassFiles.ps1 -Root ".\build\classes" -SourceRoot ".\src\main\java"
```

`Broken` 합계가 0이 아니면 **배포하지 않는다.**

## 5-6. 배포 + work/cache 삭제 + 재기동

1. WAS 정지
2. `webapps/<app>` 배포
3. `work/` 및 인스턴스 캐시 삭제 (Phase 2-4에서 확인한 경로)
4. WAS 기동

## 5-7. 서버 클래스 재스캔

```powershell
.\scripts\Scan-ClassFiles.ps1 -Root "D:\lena\AppServer\servers\WDMDB11\webapps\myapp\WEB-INF\classes"
.\scripts\Phase2-Compare-Deployment.ps1 -LocalClasses ".\build\classes" -DeployRoot "D:\...\myapp"
```

배포본과 로컬이 해시까지 일치하는지 확인한다.

---

# Phase 6 — 재현 검증 *(병렬 수행 가능)*

```powershell
.\scripts\Phase6-Invoke-ReproMatrix.ps1 -JavacHome "D:\AppDev\Bin\java_home\jdk-1.8.0"
```

소스 인코딩 × javac 인코딩 4가지 조합을 실제로 빌드해 판정 결과를 대조한다.

| 조합 | 기대 판정 |
|---|---|
| UTF-8 소스 + `-encoding UTF-8` | `한글정상` |
| UTF-8 소스 + `-encoding ISO-8859-1` | `깨짐(Latin1)` / `Latin1(UTF8소스)` |
| MS949 소스 + `-encoding ISO-8859-1` | `깨짐(Latin1)` / `Latin1(949소스)` |
| MS949 소스 + `-encoding UTF-8` | JDK 8 → `손실(FFFD)` / JDK 12+ → **컴파일 에러** |

**목적이 둘이다.**

1. 현장 증상과 같은 Status가 나온 조합 = 현장에서 벌어진 일 (원인 특정)
2. 검출기 자체의 신뢰성 확인 — 정상 조합에서 `한글정상`, 깨진 조합에서 `깨짐`이
   **모두** 나와야 한다. 정상 빌드만 스캔하면 "깨짐 0건"이 진짜인지
   검출기가 고장난 것인지 구분할 수 없다.

> MS949 소스를 `-encoding UTF-8`로 컴파일하는 조합은 JDK 12+에서
> `unmappable character (0xB8) for encoding UTF-8` 에러로 **컴파일 자체가 실패**한다.
> 즉 조용히 깨진 class가 만들어지는 경로는 사실상 ISO-8859-1 하나뿐이다
> (Latin-1은 모든 바이트가 매핑되므로 경고 없이 성공한다).

---

## 부록 — 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-08-04 | 최초 작성. HANDOFF.md A~E를 Phase 0~6으로 재배열 |
| 2026-08-12 | Phase 2-1 파서 결함 발견(`-shl` byte 잘림) → 전면 교체, 이전 측정치 무효화 |
| 2026-08-12 | 판정 로직을 문자 범위 추정 → 역변환 검증으로 교체 (오탐 제거) |
| 2026-08-12 | `Latin1` 복원 경로를 UTF-8 소스 / MS949 소스 2종으로 분리 |
| 2026-08-12 | `SrcEnc`(소스 실제 인코딩) · `Line`(소스 라인번호) 컬럼 추가 |
| 2026-08-12 | 스크립트를 Phase별 파일로 분리 |
| 2026-08-12 | 재측정 결과 **가설 3** 확정 — 런타임(Case A) 경로로 전환 |
| 2026-08-12 | `sun.jnu.encoding`의 윈도우 영향 범위 정정 |
