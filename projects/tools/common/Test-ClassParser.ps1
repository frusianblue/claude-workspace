# ===========================================================================
# Test-ClassParser.ps1  (v1, 2026-08-13 신규)
#   계열 : 공용
#   역할 : ClassParser.psm1 자체 검증 — 모듈을 스크립트에 도입하기 전 게이트
#   실행 : .\common\Test-ClassParser.ps1
#   통과 : 전 항목 PASS. 하나라도 FAIL이면 모듈을 도입하지 말 것
# ===========================================================================
#
# 왜 필요한가:
#   "깨짐 0건"이 진짜인지 검출기가 고장난 것인지 구분되지 않으면 측정 결과 전체가
#   근거로 못 쓰인다 (2026-08-12에 class 4,658개 재측정한 이유).
#   Phase6는 실제 javac 빌드로 검증하지만 JDK가 필요하고 느리다.
#   이 스크립트는 JDK 없이 판정 로직만 즉시 검증한다.
#
# 검사 항목:
#   1  정상 한글                        -> 한글정상
#   2  정상 한글 + '·'(U+00B7)          -> 한글정상   ★ 2026-08-13 오탐 사례
#   3  정상 특수문자만 (· é €)          -> ASCII      ★ 깨짐으로 잡히면 안 됨
#   4  UTF-8 소스를 Latin-1로 컴파일     -> 깨짐Latin1(UTF8소스) + 원문 복원
#   5  MS949 소스를 Latin-1로 컴파일     -> 깨짐Latin1(949소스)  + 원문 복원
#   6  MS949 이중해석                    -> 깨짐949이중          + 원문 복원
#      (UTF-8 바이트가 유효한 MS949 시퀀스인 문자열에서만 성립 — 자동 탐색)
#   7  RealFFFD                          -> 손실FFFD
#   8  -shl byte 잘림 (256 이상 값)      -> 정확한 값
# ===========================================================================

Import-Module (Join-Path $PSScriptRoot 'ClassParser.psm1') -Force

$pass = 0; $fail = 0
function Check([string]$name, $expected, $actual) {
    if ("$expected" -eq "$actual") {
        Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host ("  FAIL  {0}`n        기대: {1}`n        실제: {2}" -f $name, $expected, $actual) -ForegroundColor Red
        $script:fail++
    }
}

$utf8   = New-Object System.Text.UTF8Encoding($false)
$ms949  = [System.Text.Encoding]::GetEncoding(949)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

Write-Host "===== Test-ClassParser v1 ====="
Write-Host ""
Write-Host "[판정 로직]"

# 1. 정상 한글
$r = Test-Mojibake "매출현황.xls"
Check "정상 한글" "한글정상" $r.Type

# 2. ★ 2026-08-13 오탐 사례 — 정상 한글에 '·'(U+00B7)가 섞인 경우
#    lev1의 구 로직은 Latin-1 검사를 먼저 해서 이걸 깨짐으로 오판했다
$r = Test-Mojibake "static final String 상수 변경 시 참조 클래스 전부 재컴파일·재배포 필요"
Check "정상 한글 + 중점(U+00B7)" "한글정상" $r.Type

# 3. 정상 특수문자만 (한글 없음) — 깨짐으로 잡히면 안 됨
$r = Test-Mojibake "Copyright (c) 2026 · Version 1.0 · 100€ · café"
Check "정상 특수문자 (· € é)" "ASCII" $r.Type

# 4. UTF-8 소스를 -encoding ISO-8859-1 로 컴파일한 결과 재현
#    (UTF-8 바이트를 Latin-1로 한 글자씩 읽으면 이렇게 부풀어 오른다)
$orig    = "매출현황"
$mojibake = $latin1.GetString($utf8.GetBytes($orig))
$r = Test-Mojibake $mojibake
Check "Latin1 깨짐(UTF8소스) 판정" "깨짐Latin1" $r.Type
Check "Latin1 깨짐(UTF8소스) 출처" "UTF8소스"   $r.Origin
Check "Latin1 깨짐(UTF8소스) 복원" $orig        $r.Restored

# 5. MS949 소스를 -encoding ISO-8859-1 로 컴파일한 결과 재현
$mojibake949 = $latin1.GetString($ms949.GetBytes($orig))
$r = Test-Mojibake $mojibake949
Check "Latin1 깨짐(949소스) 판정" "깨짐Latin1" $r.Type
Check "Latin1 깨짐(949소스) 출처" "949소스"    $r.Origin
Check "Latin1 깨짐(949소스) 복원" $orig        $r.Restored

# 6. MS949 이중해석 — UTF-8 바이트를 MS949로 읽은 경우
#    ★ 아무 한글로나 재현되지 않는다. UTF-8 바이트열이 '우연히 유효한 MS949 시퀀스'여야
#      성립하므로, 왕복이 되는 문자열을 찾아서 쓴다.
#      (예: "매출현황"의 UTF-8 바이트는 유효한 MS949가 아니라 이중해석이 아예 안 일어난다.
#       .NET 기본 디코더는 이때 조용히 치환해버려 역변환 불가 문자열이 되고,
#       모듈은 이를 '한글정상'으로 판정한다 — 그게 맞는 동작이다)
$ms949Strict = [System.Text.Encoding]::GetEncoding(949,
                  (New-Object System.Text.EncoderExceptionFallback),
                  (New-Object System.Text.DecoderExceptionFallback))

$double = $null; $doubleSrc = $null
foreach ($cand in @("매출", "목록", "조회", "코드", "금액")) {
    try {
        $d  = $ms949Strict.GetString($utf8.GetBytes($cand))    # UTF-8 바이트를 949로 읽기
        $rt = $ms949Strict.GetBytes($d)                        # 되돌렸을 때 원래 바이트인지
        $ref = $utf8.GetBytes($cand)
        if ((@(Compare-Object $rt $ref -SyncWindow 0).Count -eq 0)) {
            $double = $d; $doubleSrc = $cand; break
        }
    } catch { }
}

if ($double) {
    Write-Host ("        (재현 문자열: '{0}' -> '{1}')" -f $doubleSrc, $double) -ForegroundColor DarkGray
    $r = Test-Mojibake $double
    Check "949 이중해석 판정" "깨짐949이중" $r.Type
    Check "949 이중해석 복원" $doubleSrc     $r.Restored
} else {
    Write-Host "  SKIP  949 이중해석 (이 환경에서 왕복 가능한 케이스 없음)" -ForegroundColor DarkGray
}

# 7. RealFFFD
$r = Test-Mojibake "$([char]0xFFFD)$([char]0xFFFD) 현황" -RealFFFD
Check "손실 FFFD 판정" "손실FFFD" $r.Type

Write-Host ""
Write-Host "[바이트 읽기]"

# 8. -shl byte 잘림 — 256 이상 값이 정확히 나와야 한다
#    0x01 0x2C = 300. [int] 캐스팅이 없으면 44(0x2C)가 나온다
$b = [byte[]](0x01, 0x2C, 0x00, 0x00, 0x01, 0x00)
$p = 0
Check "Read-U2 (300)" 300 (Read-U2 $b ([ref]$p))
$p = 0
Check "Read-U4 (19660800)" 19660800 (Read-U4 $b ([ref]$p))

# 9. 상수풀 파싱 — 최소 class 헤더 (major 52 = JDK 8)
$hdr = [byte[]](0xCA,0xFE,0xBA,0xBE, 0x00,0x00, 0x00,0x34, 0x00,0x01)
$pool = Get-ConstantPool $hdr
Check "Get-ConstantPool major" 52 $pool.Major
Check "Get-JdkName(52)" "8" (Get-JdkName 52)
Check "파싱 에러 없음" "" "$($pool.ParseError)"

# 10. 매직 아님 -> ParseError 로 격리 (조용히 통과하면 안 됨)
$bad = [byte[]](0x50,0x4B,0x03,0x04, 0,0,0,0,0,0)
$pool = Get-ConstantPool $bad
if ($pool.ParseError) { Check "매직 아닌 파일 격리" "격리됨" "격리됨" }
else                  { Check "매직 아닌 파일 격리" "격리됨" "통과해버림" }

Write-Host ""
if ($fail -eq 0) {
    Write-Host "전부 통과 ($pass 건) — 모듈 도입 가능" -ForegroundColor Green
} else {
    Write-Host "실패 $fail 건 / 통과 $pass 건 — 모듈을 도입하지 말 것" -ForegroundColor Red
    exit 1
}
