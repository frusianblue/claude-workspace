# 소스 인코딩 판별 및 UTF-8 변환 가이드

> MAR/EOS 이관 프로젝트 — 한글 파일명 인코딩 이슈 대응 (2부)
> 선행 문서: `eclipse-encoding-guide.md`

---

## 1. 대전제 — 인코딩은 우열이 아니라 약속이다

MS949도 UTF-8도 한글 11,172자를 모두 표현한다. 어느 쪽을 써도 한글은 깨지지 않는다.

```
"파일"
  → MS949 인코딩 → 바이트  C6 C4 C0 CF
  → UTF-8 인코딩  → 바이트  ED 8C 8C EC 9D BC
```

둘 다 완벽하다. **깨지는 원인은 인코딩 선택이 아니라 불일치다.**

```
정상 = (쓸 때 사용한 인코딩) == (읽을 때 가정한 인코딩)
```

### 이것이 AS-IS가 동작했던 이유

구 서버에서는 클래스 상수와 디스크 파일명이 **똑같이 깨져 있었다.**

```
클래스 상수 바이트   : X (깨짐)
디스크 파일명 바이트 : X (깨짐)
→ 바이트 일치 → 파일 검색 성공 → 정상 동작
```

인코딩이 올발라서가 아니라, 일관되게 틀려서 맞아떨어진 것이다.
신규 LENA 환경에서 한쪽만 "고쳐지자" 불일치가 드러나 `FileNotFoundException`이 발생했다.

> **따라서 목표는 "UTF-8로 바꾸기"가 아니라 "모든 계층의 가정을 하나로 맞추기"다.**
> 기준점은 디스크의 실제 파일명 바이트다.

---

## 2. 인코딩 판별

### 2-1. 완벽한 판별은 불가능하다

`ISO-8859-1`은 0x00~0xFF 모든 바이트에 글자가 배정되어 있다.
즉 **어떤 바이트 나열도 유효한 Latin-1 텍스트**이므로, "Latin-1이 아니다"를 증명할 수 없다.

실제 질문은 이렇게 바뀐다.

> "이 바이트를 각 인코딩으로 읽었을 때 **말이 되는 건 어느 쪽인가**"

### 2-2. 판별 순서

#### 1단계 — ASCII 전용이면 판별 불필요

전 바이트가 `0x00~0x7F`면 네 인코딩 모두 결과가 동일하다.
실제 소스 파일 대다수가 여기 해당하며, 변환 대상이 아니다.

#### 2단계 — BOM 확인 (있으면 확정)

| BOM 바이트 | 인코딩 |
|---|---|
| `EF BB BF` | UTF-8 |
| `FF FE` | UTF-16 LE |
| `FE FF` | UTF-16 BE |

BOM이 없다고 UTF-8이 아닌 것은 아니다. BOM 없는 UTF-8이 더 일반적이다.

#### 3단계 — UTF-8 유효성 검사 (가장 결정적)

UTF-8은 엄격한 비트 패턴 규칙을 가진다.

```
0xxxxxxx                             → 1바이트 (ASCII)
110xxxxx 10xxxxxx                    → 2바이트
1110xxxx 10xxxxxx 10xxxxxx           → 3바이트 (한글)
11110xxx 10xxxxxx 10xxxxxx 10xxxxxx  → 4바이트
```

후속 바이트는 반드시 `10xxxxxx` (`0x80~0xBF`) 형식이어야 한다.

**예시** — MS949 `파` = `C6 C4`

| 바이트 | 비트 | 판정 |
|---|---|---|
| `C6` | `11000110` | 2바이트 시퀀스 시작 |
| `C4` | `11000100` | `10`으로 시작하지 않음 → **규칙 위반** |

MS949/EUC-KR 한글이 이 패턴을 우연히 만족하기는 매우 어렵다.

> **UTF-8 디코딩이 에러 없이 통과 → UTF-8일 확률 99% 이상**
> **실패 → UTF-8 아님 (확정)**

#### 4단계 — MS949 vs EUC-KR

EUC-KR은 MS949의 부분집합이다.

| | 한글 음절 수 | 비고 |
|---|---|---|
| EUC-KR | 2,350자 | 완성형 |
| MS949 | 11,172자 | 확장 완성형 |

| 2바이트 범위 | 해석 |
|---|---|
| 리드 `A1~FE` + 트레일 `A1~FE` | EUC-KR 영역 (양쪽 다 가능) |
| 리드 `81~A0` 또는 트레일 `41~A0` | **MS949 확장 영역 → EUC-KR 아님** |

확장 영역 바이트가 하나라도 있으면 MS949 확정.
없어도 **MS949로 읽으면 된다** — MS949가 EUC-KR을 완전 포함하므로 손실이 없다.

> `똠`, `펲`, `햏` 같은 확장 영역 글자가 EUC-KR에서는 손실된다.
> 레거시 파일명 상수에 섞여 있으면 조용히 깨지므로 **MS949로 통일**한다.

#### 5단계 — ISO-8859-1은 "판별"이 아니라 "제외"

한글 소스를 Latin-1로 저장하는 것은 애초에 불가능하다(인코딩 단계에서 실패).
`8859_1`이 등장하는 곳은 파일 내용이 아니라 **코드 내부**다.

```java
new String(fileName.getBytes("8859_1"), "UTF-8")
```

이것은 소스 인코딩 문제가 아니라 **런타임 로직 문제**이므로 별도로 다룬다.

### 2-3. 실무 결론

`.java` 파일에 한정하면 경우의 수는 셋뿐이다.

| 판별 결과 | 실제 의미 | 조치 |
|---|---|---|
| ASCII | 한글 없음 | 변환 불필요 |
| UTF-8 검사 통과 | UTF-8 | 그대로 유지 |
| UTF-8 검사 실패 | MS949 (한글 Windows) | MS949 → UTF-8 변환 |

**UTF-8 유효성 검사 하나로 사실상 끝난다.**

---

## 3. 판별 스크립트

`Scan-JavaSources.ps1`에 통합할 함수.

```powershell
function Get-FileEncoding {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # 1. BOM
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return "UTF-8-BOM"
    }

    # 2. ASCII only
    if (-not ($bytes | Where-Object { $_ -gt 0x7F })) {
        return "ASCII"
    }

    # 3. UTF-8 strict validation
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [void]$utf8Strict.GetString($bytes)
        return "UTF-8"
    } catch {
        # not UTF-8, fall through
    }

    # 4. MS949 extended area check
    $i = 0
    $hasExtended = $false
    while ($i -lt $bytes.Length) {
        $b = $bytes[$i]
        if ($b -le 0x7F) { $i++; continue }

        if ($i + 1 -ge $bytes.Length) { return "UNKNOWN" }
        $t = $bytes[$i + 1]

        if ($b -ge 0x81 -and $b -le 0xA0)      { $hasExtended = $true }
        elseif ($t -lt 0xA1)                   { $hasExtended = $true }

        $i += 2
    }

    if ($hasExtended) { return "MS949" }
    return "EUC-KR-COMPATIBLE"   # MS949로 읽어도 안전
}
```

### 왕복(Round-trip) 검증

의심스러운 파일의 최종 확인 방법.

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$ms949 = [System.Text.Encoding]::GetEncoding(949)

$decoded   = $ms949.GetString($bytes)
$reencoded = $ms949.GetBytes($decoded)

$identical = -not (Compare-Object $bytes $reencoded)
```

디코딩 후 재인코딩했을 때 원본 바이트가 복원되면, 그 인코딩으로 읽어도 **정보 손실이 없다**는 뜻이다.

### 눈으로 하는 빠른 확인

스크립트 없이 이클립스에서:

1. 프로젝트 인코딩을 **UTF-8**로 설정 → `F5` (Refresh)
2. 한글이 `�`로 보이면 → 그 파일은 MS949
3. 정상이면 → UTF-8

> ⚠️ **편집·저장만 하지 않으면 안전하다.** 저장하는 순간 `�`가 파일에 확정된다.

---

## 4. MS949 → UTF-8 변환

### 4-1. 이클립스에서 변환하는 방법

이클립스에는 "인코딩 변환" 메뉴가 없다. 대신 다음 성질을 이용한다.

> 이클립스는 **읽을 때의 인코딩으로 String을 만들고, 저장할 때의 인코딩으로 바이트를 쓴다.**

```
1. MS949로 읽는다          → 메모리에 정상 한글 String
2. 인코딩을 UTF-8로 바꾼다  → 화면이 깨져 보임 (파일은 아직 그대로)
3. 저장한다                → UTF-8 바이트로 기록
```

#### 절차

```
① 프로젝트 인코딩 = MS949 확인
   → 에디터에서 한글이 정상 표시되어야 함     ★ 전제조건

② 변환할 파일을 에디터로 연다

③ 파일 우클릭 → Properties → Resource
   → Text file encoding → Other → UTF-8 → Apply and Close

④ 에디터로 돌아오면 한글이 깨져 보인다        ← 정상

⑤ ASCII 영역에서 아무 글자나 입력했다 지운다   ★ Dirty 상태 생성

⑥ Ctrl + S 저장

⑦ 한글이 다시 정상 표시되면 성공
```

#### ⑤번이 핵심이다

`Ctrl+S`는 변경사항이 없으면 아무 동작도 하지 않는다.
인코딩만 바꾸고 저장하면 **파일이 그대로 남는다.**

③번 이후 화면이 깨져 보이는 것은 단지 **다르게 읽고 있을 뿐**이며, 파일은 여전히 MS949다.

#### ⚠️ 절대 금지

**깨져 보이는 상태(④)에서 한글 부분을 편집하지 말 것.**

깨진 표시가 `U+FFFD`(`�`)라면 원본 바이트는 이미 메모리에서 소실된 상태다.
저장 시 `�`가 파일에 확정 기록되며 **복구 불가**하다.

⑤번은 반드시 ASCII 영역에서 — 주석 끝 공백 하나를 넣었다 빼는 식으로 수행한다.

### 4-2. 이클립스 방식의 한계

| 항목 | 이클립스 | PowerShell |
|---|:---:|:---:|
| 일괄 처리 | ❌ 파일마다 수동 | ✅ 재귀 일괄 |
| 드라이런 | ❌ 없음 | ✅ `-WhatIf` |
| 변환 로그 | ❌ 없음 | ✅ `.dat` 출력 |
| 실수 위험 | 높음 (⑤ 누락, 오편집) | 낮음 |
| BOM 제어 | 불명확 | 명시적 |
| 대상 수백 개 | 비현실적 | 문제없음 |

> 본 프로젝트는 `Constants.java` 단독이 아니라 **참조 클래스 전체**를 다뤄야 하므로
> 스크립트 방식이 적합하다. 이클립스 방식은 1~2개 파일 확인용으로만 사용한다.

### 4-3. PowerShell 변환 (권장)

```powershell
function Convert-Ms949ToUtf8 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$WhatIf,
        [string]$BackupDir
    )

    $ms949 = [System.Text.Encoding]::GetEncoding(949)
    $utf8  = New-Object System.Text.UTF8Encoding($false)   # BOM 없음

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # --- 안전장치 1: 이미 UTF-8이면 건너뛴다 (이중 변환 방지) ---
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [void]$strict.GetString($bytes)
        Write-Host "SKIP (already UTF-8): $Path" -ForegroundColor DarkGray
        return
    } catch { }

    # --- 안전장치 2: MS949 왕복 검증 ---
    $text = $ms949.GetString($bytes)
    $roundtrip = $ms949.GetBytes($text)
    if (Compare-Object $bytes $roundtrip) {
        Write-Host "WARN (roundtrip failed, skipped): $Path" -ForegroundColor Yellow
        return
    }

    if ($WhatIf) {
        Write-Host "WOULD CONVERT: $Path" -ForegroundColor Cyan
        return
    }

    if ($BackupDir) {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
        Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force
    }

    [System.IO.File]::WriteAllBytes($Path, $utf8.GetBytes($text))
    Write-Host "CONVERTED: $Path" -ForegroundColor Green
}
```

#### 실행

```powershell
# 1단계 — 반드시 드라이런 먼저
Get-ChildItem -Path .\src -Filter *.java -Recurse |
    ForEach-Object { Convert-Ms949ToUtf8 -Path $_.FullName -WhatIf }

# 2단계 — 결과 확인 후 실제 실행
Get-ChildItem -Path .\src -Filter *.java -Recurse |
    ForEach-Object { Convert-Ms949ToUtf8 -Path $_.FullName -BackupDir "D:\backup\src" }
```

#### 두 가지 안전장치의 의미

**이중 변환 방지** — 이미 UTF-8인 파일을 다시 MS949로 읽으면 완전히 손상된다.
스크립트를 두 번 실행하는 실수는 흔하므로 이 체크가 필수다.

**왕복 검증** — MS949로 디코딩 후 재인코딩했을 때 원본이 복원되지 않으면
그 파일은 MS949가 아니다. 손대지 않고 넘어가야 한다.

---

## 5. BOM 주의

Java 8 `javac`는 UTF-8 BOM을 처리하지 못한다.

```
error: illegal character: '\ufeff'
```

위 스크립트의 `UTF8Encoding($false)`가 BOM을 제외하는 부분이므로 변경하지 말 것.

### BOM 검사

```powershell
Get-ChildItem .\src -Filter *.java -Recurse | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Host "BOM found: $($_.FullName)" -ForegroundColor Red
    }
}
```

---

## 6. 변환 후 전체 순서

```
1. Convert-Ms949ToUtf8 실행 완료
2. BOM 검사 통과 확인
3. 이클립스 프로젝트 인코딩 → UTF-8
4. F5 (Refresh) → 한글 정상 표시 확인
5. build.xml  <javac encoding="UTF-8">
6. Clean → Build
7. javap -v Constants.class      검증
8. javap -v LogController.class  검증   ★ 인라이닝 때문에 필수
9. 배포 (참조 클래스 전체 함께)
10. WAS work/cache 삭제 → 재기동
```

### 7~8단계를 모두 해야 하는 이유

`static final String`은 컴파일 시점에 **참조하는 클래스의 상수 풀로 값이 복사**된다.
`Constants.class`만 새로 배포하면 `LogController`는 여전히 예전 깨진 값을 보유한다.

```
Constants.class      → 정상 한글  ✅
LogController.class  → 깨진 값    ❌  ← 런타임에 실제로 사용되는 쪽
```

---

## 7. 인코딩 이름 표기 주의

이클립스 드롭다운에 MS949는 없다. 콤보박스에 **직접 입력**한다.

| 입력값 | JDK 인식 | 비고 |
|---|:---:|---|
| `MS949` | ✅ | **권장** |
| `x-windows-949` | ✅ | JDK canonical name |
| `windows-949` | ✅ | 별칭 |
| `CP949` | ❌ | `UnsupportedCharsetException` |

> `CP949`는 Python·PowerShell에서는 통하지만 **Java에서는 인식하지 못한다.**
> 습관적으로 입력하기 쉬우니 주의.

잘못된 이름을 입력하면 이클립스가 하단에 에러를 표시하므로, 조용히 무시되지는 않는다.

---

## 8. 요약 체크리스트

- [ ] `Get-FileEncoding`으로 전체 소스 분류 → `.dat` 출력
- [ ] `Convert-Ms949ToUtf8 -WhatIf` 드라이런
- [ ] 백업 디렉터리 지정 후 실제 변환
- [ ] BOM 검사 통과
- [ ] 이클립스 프로젝트 인코딩 UTF-8 전환 + 육안 확인
- [ ] `build.xml` javac encoding UTF-8
- [ ] Clean Build
- [ ] `javap -v` — `Constants` **및 모든 참조 클래스**
- [ ] `CommExcelView`의 `getBytes("8859_1")` 제거 여부 확인
- [ ] 디스크 실제 파일명 바이트와 대조
