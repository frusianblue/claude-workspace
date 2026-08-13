# ===========================================================================
# ClassParser.psm1  (v1, 2026-08-13 신규)
#   계열 : 공용
#   역할 : .class 상수풀 파싱 + 한글 깨짐 판정의 단일 원본(single source of truth)
#   사용 : Import-Module (Join-Path $PSScriptRoot '..\common\ClassParser.psm1') -Force
# ===========================================================================
#
# ── 왜 만들었는가 ────────────────────────────────────────────────────
#   같은 파싱·판정 로직이 4벌로 복제돼 있었고, 수정이 한 벌씩만 반영되는 사고가
#   두 번 연속 났다.
#
#     2026-08-12  -shl byte 잘림      → 3곳 수정, Compare-SourceToClass-lev2 누락
#     2026-08-13  깨짐 판정 순서       → Scan-ClassFiles만 수정, lev1 누락
#                 (정상 한글에 '·'(U+00B7)가 섞이면 Latin-1 깨짐으로 오판.
#                  "재컴파일·재배포"가 실제로 오탐됐다 — Scan-ClassFiles 주석에
#                  예시로 적어둔 바로 그 문자열이다)
#
#   이 모듈이 유일한 구현이 되면 수정이 한 곳에서 끝난다.
#
# ── 판정 원칙 (문자 범위 추정이 아니라 역변환 검증) ──────────────────
#   깨진 문자열은 원래 1글자가 2~3문자로 부풀어 있다.
#   따라서 원래 바이트로 되돌렸을 때
#     (1) 유효한 시퀀스로 디코드되고
#     (2) 길이가 반드시 줄어든다
#   두 조건을 함께 만족해야 깨짐으로 본다.
#   정상 특수문자(· é €)는 되돌려도 유효 시퀀스가 안 나오거나 길이가 안 줄어 걸러진다.
#
# ── 판정 순서 (★ 뒤집으면 오탐이 난다) ──────────────────────────────
#   1) FFFD 검사      — 원본 손실. 복원 불가
#   2) 한글 검사      — 949 이중해석 여부만 추가 확인, 아니면 정상
#   3) 상위 Latin 검사 — 여기 와야 '·' 같은 정상 특수문자가 2)에서 이미 걸러진 뒤다
#
#   한글 검사를 Latin-1 검사보다 반드시 먼저 둘 것.
# ===========================================================================

Set-StrictMode -Off

# ── 엄격 인코더/디코더 (치환 대신 예외 — 역변환 판정의 전제 조건) ────
$script:EncFail    = New-Object System.Text.EncoderExceptionFallback
$script:DecFail    = New-Object System.Text.DecoderExceptionFallback
$script:Ms949      = [System.Text.Encoding]::GetEncoding(949,   $script:EncFail, $script:DecFail)
$script:Latin1Enc  = [System.Text.Encoding]::GetEncoding(28591, $script:EncFail, $script:DecFail)
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:RxHangul   = [regex] "[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]"
$script:RxHighLat  = [regex] "[\u0080-\u00FF]"

$script:JdkMap = @{ 45="1.1"; 46="1.2"; 47="1.3"; 48="1.4"; 49="5"; 50="6"; 51="7"; 52="8";
                    53="9"; 54="10"; 55="11"; 56="12"; 57="13"; 58="14"; 59="15"; 60="16";
                    61="17"; 62="18"; 63="19"; 64="20"; 65="21"; 66="22"; 67="23"; 68="24" }

# ---------------------------------------------------------------------------
# 바이트 읽기
#   ★ PowerShell은 -shl 의 결과 타입을 왼쪽 피연산자 타입으로 유지한다.
#     [byte]를 8비트 밀면 byte 범위를 넘어 0으로 잘리므로 반드시 [int] 캐스팅.
#     이 캐스팅이 없으면 상수풀 256개 이상 / 256바이트 이상 문자열에서 desync가
#     발생해 파일이 결과에서 통째로 누락된다. major는 256 미만이라 우연히 맞는다.
# ---------------------------------------------------------------------------
function Read-U2 {
    param([byte[]]$Bytes, [ref]$Pos)
    $v = ((([int]$Bytes[$Pos.Value]) -shl 8) -bor ([int]$Bytes[$Pos.Value + 1]))
    $Pos.Value += 2
    return $v
}

function Read-U4 {
    param([byte[]]$Bytes, [ref]$Pos)
    $v = ((([long]$Bytes[$Pos.Value])     -shl 24) -bor
          (([long]$Bytes[$Pos.Value + 1]) -shl 16) -bor
          (([long]$Bytes[$Pos.Value + 2]) -shl  8) -bor
           ([long]$Bytes[$Pos.Value + 3]))
    $Pos.Value += 4
    return $v
}

function Test-ClassMagic {
    param([byte[]]$Bytes)
    return ($Bytes.Length -ge 10 -and $Bytes[0] -eq 0xCA -and $Bytes[1] -eq 0xFE)
}

function Get-ClassMajor {
    param([Parameter(Mandatory)][string]$Path)
    $b = New-Object byte[] 8
    $fs = [System.IO.File]::OpenRead($Path)
    try { $null = $fs.Read($b, 0, 8) } finally { $fs.Close() }
    if ($b[0] -ne 0xCA) { return 0 }
    return ((([int]$b[6]) -shl 8) -bor ([int]$b[7]))
}

function Get-JdkName {
    param([int]$Major)
    if ($script:JdkMap.ContainsKey($Major)) { return $script:JdkMap[$Major] }
    return "?($Major)"
}

# ---------------------------------------------------------------------------
# 상수풀 순회
#   반환: @{ Major; Utf8 = @( @{Text; RealFFFD; Index} ); StringRefs = @(인덱스);
#            ParseError }
#   ParseError 가 채워지면 그 파일은 '파싱실패'로 격리한다 (조용히 빠지지 않게).
# ---------------------------------------------------------------------------
function Get-ConstantPool {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $r = [PSCustomObject]@{
        Major = 0; Minor = 0
        Utf8 = New-Object System.Collections.Generic.List[object]
        StringRefs = New-Object System.Collections.Generic.List[int]
        ParseError = $null
    }
    if (-not (Test-ClassMagic $Bytes)) { $r.ParseError = "class 매직(CAFEBABE) 아님"; return $r }

    $pos = 4
    $r.Minor = Read-U2 $Bytes ([ref]$pos)
    $r.Major = Read-U2 $Bytes ([ref]$pos)
    $cpCount = Read-U2 $Bytes ([ref]$pos)

    $i = 1
    while ($i -lt $cpCount) {
        if ($pos -ge $Bytes.Length) { $r.ParseError = "상수풀 도중 파일 끝 (index $i/$cpCount)"; break }
        $tag = $Bytes[$pos]; $pos++
        switch ($tag) {
            1 {
                $len = Read-U2 $Bytes ([ref]$pos)
                if ($pos + $len -gt $Bytes.Length) { $r.ParseError = "Utf8 길이 초과 (index $i)"; break }
                $s = [System.Text.Encoding]::UTF8.GetString($Bytes, $pos, $len)
                # 컴파일러가 실제로 심은 U+FFFD 인지, 우리 디코더가 만든 것인지 구분한다.
                # (class는 modified UTF-8 이라 C0 80 등에서 디코더가 FFFD를 낼 수 있다)
                $realFFFD = $false
                for ($q = $pos; $q -le $pos + $len - 3; $q++) {
                    if ($Bytes[$q] -eq 0xEF -and $Bytes[$q+1] -eq 0xBF -and $Bytes[$q+2] -eq 0xBD) { $realFFFD = $true; break }
                }
                $r.Utf8.Add([PSCustomObject]@{ Index = $i; Text = $s; RealFFFD = $realFFFD })
                $pos += $len
            }
            8 { $r.StringRefs.Add((Read-U2 $Bytes ([ref]$pos))) }   # CONSTANT_String -> Utf8 인덱스
            { $_ -in 3,4 }              { $pos += 4 }
            { $_ -in 5,6 }              { $pos += 8; $i++ }         # long/double 은 슬롯 2개
            { $_ -in 7,16,19,20 }       { $pos += 2 }
            { $_ -in 9,10,11,12,17,18 } { $pos += 4 }
            15                          { $pos += 3 }
            default { $r.ParseError = "알 수 없는 상수풀 태그 $tag (offset $pos, index $i)" }
        }
        if ($r.ParseError) { break }
        $i++
    }
    return $r
}

# 진짜 String 리터럴만 — CONSTANT_String이 참조하는 Utf8만 추출
# (클래스명·메서드명·디스크립터가 섞이지 않게)
function Get-StringLiterals {
    param([Parameter(Mandatory)]$Pool)
    $byIdx = @{}
    foreach ($u in $Pool.Utf8) { $byIdx[$u.Index] = $u }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($ix in $Pool.StringRefs) {
        if ($byIdx.ContainsKey($ix)) { $out.Add($byIdx[$ix]) }
    }
    return $out
}

# ---------------------------------------------------------------------------
# 복원 (역변환)
# ---------------------------------------------------------------------------
function Restore-Latin1 {
    param([string]$Text)
    if (-not $Text) { return $null }
    try { $raw = $script:Latin1Enc.GetBytes($Text) } catch { return $null }

    # (a) UTF-8 소스를 Latin-1로 컴파일한 경우
    #     엄격 디코더 통과 자체가 강한 증거라 한글 조건을 걸지 않는다
    #     (한글이 아닌 é ü 가 깨진 경우도 정확히 복원됨)
    try {
        $u = $script:Utf8Strict.GetString($raw)
        if ($u.Length -lt $Text.Length) {
            return [PSCustomObject]@{ Restored = $u; Origin = "UTF8소스" }
        }
    } catch { }

    # (b) MS949 소스를 Latin-1로 컴파일한 경우
    try {
        $k = $script:Ms949.GetString($raw)
        if ($k.Length -lt $Text.Length -and $script:RxHangul.IsMatch($k)) {
            return [PSCustomObject]@{ Restored = $k; Origin = "949소스" }
        }
    } catch { }

    return $null
}

# MS949 이중해석: 겉보기엔 한글이지만 실제로는 UTF-8 바이트를 MS949로 읽은 결과
#   [주의] 이 현상은 아무 한글에서나 생기지 않는다. 원문의 UTF-8 바이트열이
#   '우연히 유효한 MS949 시퀀스'일 때만 성립한다. 예를 들어 '매출'(-> 留ㅼ텧)은
#   재현되지만 '매출현황'은 UTF-8 바이트가 유효한 949가 아니라 재현되지 않는다.
#   후자의 경우 .NET 기본(비엄격) 디코더는 조용히 치환해 역변환 불가 문자열을 만들고,
#   이 함수는 null을 반환한다 = 정상 판정. 이게 맞는 동작이다.
function Restore-949Double {
    param([string]$Text)
    if (-not $Text) { return $null }
    try { $raw = $script:Ms949.GetBytes($Text) } catch { return $null }
    try {
        $u = $script:Utf8Strict.GetString($raw)
        if ($u.Length -lt $Text.Length -and $script:RxHangul.IsMatch($u)) { return $u }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
# 리터럴 1개 판정  ★ 이 순서를 바꾸지 말 것
#   반환: @{ Type; Restored; Origin }
#   Type: 손실FFFD / 한글정상 / 깨짐949이중 / 깨짐Latin1 / ASCII
# ---------------------------------------------------------------------------
function Test-Mojibake {
    param(
        [string]$Text,
        [switch]$RealFFFD          # Get-ConstantPool 이 판정한 '진짜 FFFD' 플래그
    )

    if (-not $Text) { return [PSCustomObject]@{ Type="ASCII"; Restored=""; Origin="" } }

    # 1) 원본 손실 — 복원 불가
    if ($RealFFFD) {
        return [PSCustomObject]@{ Type="손실FFFD"; Restored=""; Origin="UTF-8오컴파일" }
    }

    # 2) 한글 — ★ Latin-1 검사보다 먼저.
    #    여기서 걸러야 "재컴파일·재배포"처럼 정상 한글에 '·'(U+00B7)가 섞인 문자열이
    #    3)의 Latin-1 검사로 넘어가 깨짐으로 오판되지 않는다.
    if ($script:RxHangul.IsMatch($Text)) {
        $d = Restore-949Double $Text
        if ($d) { return [PSCustomObject]@{ Type="깨짐949이중"; Restored=$d; Origin="MS949오컴파일" } }
        return   [PSCustomObject]@{ Type="한글정상"; Restored=""; Origin="인코딩일치" }
    }

    # 3) 상위 Latin 영역 — 역변환이 성립할 때만 깨짐
    if ($script:RxHighLat.IsMatch($Text)) {
        $r = Restore-Latin1 $Text
        if ($r) { return [PSCustomObject]@{ Type="깨짐Latin1"; Restored=$r.Restored; Origin=$r.Origin } }
        # 역변환 불성립 = 정상 특수문자 (· é €)
    }

    return [PSCustomObject]@{ Type="ASCII"; Restored=""; Origin="" }
}

# 파일 단위 상태 (우선순위: FFFD > Latin1 > 949이중 > 정상)
function Get-FileStatus {
    param([int]$Fffd, [int]$Latin1, [int]$Double949, [int]$Ok, [string]$Latin1Origin)
    if     ($Fffd       -gt 0) { return [PSCustomObject]@{ Status="손실(FFFD)";   Encoding="UTF-8오컴파일" } }
    elseif ($Latin1     -gt 0) { return [PSCustomObject]@{ Status="깨짐(Latin1)"; Encoding="Latin1($Latin1Origin)" } }
    elseif ($Double949  -gt 0) { return [PSCustomObject]@{ Status="깨짐(949이중)"; Encoding="MS949오컴파일" } }
    elseif ($Ok         -gt 0) { return [PSCustomObject]@{ Status="한글정상";     Encoding="인코딩일치" } }
    else                       { return [PSCustomObject]@{ Status="ASCII만";      Encoding="-" } }
}

Export-ModuleMember -Function Read-U2, Read-U4, Test-ClassMagic, Get-ClassMajor, Get-JdkName,
                              Get-ConstantPool, Get-StringLiterals,
                              Restore-Latin1, Restore-949Double, Test-Mojibake, Get-FileStatus
