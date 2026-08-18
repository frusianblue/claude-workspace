# HANDOFF — MAR/EOS 한글 인코딩 이슈

> 작성: 2026-08-12 · 다음 세션 인수인계용
> 상세 절차는 `RUNBOOK.md`, 실행 스크립트는 `scripts/` 참조

---

## 1. 한 줄 요약

**컴파일 단계는 무혐의로 확정됐다. 남은 원인은 런타임 경로다.**
다음 세션은 `RUNBOOK.md`의 **Phase 5 D-1**부터 시작한다.

---

## 2. 확정된 사실

| 항목 | 결과 | 근거 |
|---|---|---|
| 상수 풀 한글 깨짐 | **0건** | `Scan-ClassFiles.ps1`, 8개 클래스 / 리터럴 90개 |
| class major version | **50 (1.6)** | 의도한 타깃대로 산출됨 |
| 빌드 파이프라인 | 정상 | `ant clean compile war` → `dist/enctest.war` 생성 |
| 판정 | **가설 3** | Constants·참조 클래스 양쪽 `한글정상` |

### 검증된 빌드 설정 (`lena-encoding-test`)

```properties
javac.source=1.6
javac.target=1.6
javac.encoding=UTF-8
javac.bootcp=D:/AppDev/Bin/java_home/java-se-7u75-ri/jre/lib/rt.jar
```

`bootclasspath`를 잡은 뒤 `bootstrap class path not set` 경고가 사라졌다.
이게 설정이 실제로 먹었다는 증거다.

---

## 3. 배제된 가설

| 가설 | 배제 근거 |
|---|---|
| 1 — 인라이닝 | Constants·참조 클래스 모두 `한글정상`. 구값 잔존 없음 |
| 2 — 소스 MS949 오컴파일 | `손실(FFFD)` 0건. 소스 인코딩도 UTF-8 확인 |
| 2 변형 — ISO-8859-1 컴파일 | `깨짐(Latin1)` 0건 |

> 추가로, MS949 소스를 `-encoding UTF-8`로 컴파일하는 경로는 실측 결과
> **javac가 `unmappable character` 에러로 막는다**(JDK 12+). JDK 8은 경고 후 U+FFFD 치환.
> 즉 조용히 깨진 class가 생기는 경로는 **ISO-8859-1 하나뿐**이다
> (Latin-1은 모든 바이트가 매핑되므로 경고 없이 성공).

---

## 4. 다음 액션 (우선순위 순)

### A. 문자열이 깨진 건지 로그만 깨진 건지 구분 ← **최우선**

`FileNotFoundException` 로그의 `?`만 보고 인코딩 문제로 단정하면 안 된다.
두 경우가 증상이 같다.

```java
String path = (String) map.get("templatePath");
log.info("[REQ] hex = " + EncodingUtil.toUnicodeHex(path));

File f = new File(path);
log.info("[FILE] exists  = " + f.exists());
log.info("[FILE] abs hex = " + EncodingUtil.toUnicodeHex(f.getAbsolutePath()));
```

| hex 결과 | 판정 | 다음 |
|---|---|---|
| `U+B9E4 U+CD9C ...` | 문자열 **정상** | 로그 출력 인코딩 또는 경로 자체 문제 → C로 |
| `U+00EB U+00A7 ...` | request 유입 지점에서 **이미 깨짐** | B로 |

hex는 ASCII라 어떤 콘솔에서도 안 깨진다. **인코딩 문제를 인코딩에 의존하지 않고 보는 방법.**

### B. 파라미터 유입 경로 점검 (A에서 "이미 깨짐"일 때)

1. 커넥터 `URIEncoding` / `useBodyEncodingForURI` — GET 쿼리스트링 담당
2. `web.xml`의 `CharacterEncodingFilter` — **POST 본문 담당. 커넥터 설정과 별개다**
3. **필터 순서**: `CharacterEncodingFilter`가 `LucyXSSFilter`보다 **앞**에 있는가
   → 뒤에 있으면 `setCharacterEncoding` 호출 전에 파라미터가 파싱되어 ISO-8859-1로 굳는다

### C. 디스크 파일명 실측 (A와 병렬 가능)

```powershell
.\scripts\Phase1-Get-TargetFilenameBytes.ps1 -Path "D:\upload" -Recurse
```

**이게 D-1 방침을 결정한다.** 코드를 고치기 전에 반드시 먼저 한다.

| Verdict | D-1 방침 |
|---|---|
| `정상` | `getBytes("8859_1")` 제거 |
| `AS-IS깨짐저장` | 양방향 fallback 또는 rename 배치 |
| 혼재 | 양쪽 fallback 필수 |

### D. 배포/캐시 확인 (가설 3의 나머지 절반)

```powershell
.\scripts\Phase2-Compare-Deployment.ps1 `
    -LocalClasses "...\build\classes" -DeployRoot "...\webapps\myapp" `
    -TargetClass  "smart/common/Constants.class"
```

해시 불일치 / jar 내 중복 / work 캐시 잔존을 본다. **아직 미실행.**

---

## 5. 도구 현황

| 파일 | 상태 |
|---|---|
| `scripts/Scan-ClassFiles.ps1` | **현행** — 상수풀 스캔 핵심 도구 |
| `scripts/Phase0~4,6-*.ps1` | **현행** — Phase별 분리 |
| `Check-ClassEncoding.ps1` | 폐기 (Scan-ClassFiles로 통합) |
| RUNBOOK 8/4판 Phase 2-1 인라인 파서 | **폐기 — 결함 있음** |

### 8/4 이전 측정치는 전부 무효

구 파서는 2바이트 값을 `($b[$p] -shl 8) -bor $b[$p+1]`로 읽었다.
PowerShell은 `-shl` 결과 타입을 왼쪽 피연산자로 유지해서 **`[byte]`를 8비트 밀면 0으로 잘린다.**

- `major`는 256 미만이라 우연히 맞았다 → 발견이 늦은 이유
- 상수 풀 256개 이상 / 256바이트 이상 문자열에서 desync → **파일이 결과에서 통째로 누락**
- 실측: class 4,658개 대상 파싱 실패 39건 → `[int]` 캐스팅 후 **0건**

**"깨짐 0건"이 진짜인지 못 읽은 것인지 구분되지 않으므로 재측정 전 결과는 근거로 쓰지 않는다.**

---

## 6. 알려진 함정

| 함정 | 대응 |
|---|---|
| PowerShell `-shl`이 byte 타입 유지 | 바이트 조립 시 무조건 `[int]` 캐스팅 |
| PS 5.1은 BOM 없는 .ps1을 MS949로 읽음 | 스크립트는 **UTF-8 BOM** 저장. 안 그러면 엉뚱한 구문 오류 |
| 실행 정책 | `powershell -ExecutionPolicy Bypass -File ...` |
| DRM이 csv/txt 자동 암호화 | 출력은 `.dat` |
| 엑셀 Power Query가 `.dat`을 오파싱 | 파일→열기→모든 파일→텍스트 마법사→구분자 `|` |
| `bootclasspath` 경로 없으면 javac가 **조용히 무시** | 공용 빌드는 `<available>`+`<fail>` 검증 |
| 부분 빌드는 가설 1 재발 | `static final String`은 컴파일 타임 인라이닝 → 반드시 clean 후 전체 빌드 |
| 정상 빌드만 스캔하면 검출기 고장을 못 봄 | `Phase6-Invoke-ReproMatrix.ps1`로 대조군 검증 |

---

## 7. 정정 이력 (이전 판단이 틀렸던 것)

| 항목 | 이전 | 정정 |
|---|---|---|
| `sun.jnu.encoding` | 윈도우 FNFE의 유력 원인 | **영향 제한적.** JDK 윈도우 파일 I/O는 Unicode(WCHAR) Win32 API를 써서 Java String이 UTF-16 그대로 전달됨. 리눅스와 다름 |
| 깨짐 판정 | 문자 범위(`[\u00A1-\u00FF]`) 추정 | **역변환 검증.** `·`(U+00B7) `é` `€` 오탐 제거 |
| Latin1 복원 | MS949 경로만 | UTF-8 / MS949 **2경로 분리** → 원본 소스 계열 역추적 가능 |

---

## 8. 열린 질문

1. **`Phase2-Compare-Deployment.ps1` 미실행** — 가설 3의 배포/로딩 쪽 절반이 아직 검증 안 됨
2. **디스크 파일명 실측 미실행** — D-1 방침이 아직 미정
3. **AS-IS 전수 점검 미실행** — 운영 jar/war 대상 `-IncludeArchives` 스캔.
   `손실FFFD`가 나오면 복원 불가이므로 **원본 소스 확보가 선행 과제**가 된다
4. **프로젝트별 컴파일 레벨 미확정** — AS-IS가 1.6/1.7 혼재.
   `javap -verbose | Select-String major`로 모듈별 확인 후 `build.properties`에 고정 필요
5. **`?` 치환(Case A) 판별 불가** — 정상 물음표와 구분 불가능. 의심 시 소스 육안 확인

---

## 9. 다음 세션 시작 방법

```powershell
# 1) 콘솔 고정
. .\scripts\Phase0-Init-EncodingConsole.ps1

# 2) 디스크 파일명 실측 (D-1 방침 결정)
.\scripts\Phase1-Get-TargetFilenameBytes.ps1 -Path "D:\upload" -Recurse

# 3) 배포/캐시 확인
.\scripts\Phase2-Compare-Deployment.ps1 -LocalClasses ... -DeployRoot ...
```

그 다음 **4-A의 hex 로그**를 심어 재현하면 런타임 원인이 특정된다.
