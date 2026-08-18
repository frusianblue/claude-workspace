# ===========================================================================
# [폐기] Check-ClassEncoding.ps1
#   사유 : Scan-ClassFiles.ps1 로 통합됨
#   비고 : 단 -IncludeArchives(jar/war 내부 스캔)는 이 파일에만 있었다.
#   그 용도는 Expand-ArchivesForScan.ps1 + Scan-ClassFiles 조합으로 대체됐다.
#   판정 로직은 Scan-ClassFiles 쪽이 최신이므로 이 파일의 결과는 근거로 쓰지 말 것.
#
#   이 폴더의 파일은 실행하지 말 것. 삭제하지 않고 남겨둔 이유는
#   '아직 이식되지 않은 기능이 있는지' 나중에 확인할 근거가 필요하기 때문이다.
# ===========================================================================
<#
.SYNOPSIS
    .class 파일의 상수풀 문자열을 직접 읽어 인코딩 깨짐(mojibake)을 판정한다.

.DESCRIPTION
    javap 를 쓰지 않고 class 파일 바이트를 직접 파싱한다.
    class 파일 내부 문자열은 항상 modified UTF-8 로 저장되므로
    JVM 출력 인코딩 / 콘솔 코드페이지의 영향을 전혀 받지 않는다.

    판정은 문자 범위가 아니라 "역변환 성립 여부"로 한다.
      문자열 -> Latin-1 바이트 -> 엄격 UTF-8 디코드
        성공 + 결과가 더 짧음 => 깨짐 확정 (원문까지 복원)
        예외                  => 정상 (· é € 같은 정상 특수문자)

.EXAMPLE
    .\Check-ClassEncoding.ps1 -Root "D:\...\workspace\lena-encoding-test\build\classes"

.EXAMPLE
    .\Check-ClassEncoding.ps1 -Root "D:\lena\AppServer\servers\WDMDB11\webapps" -IncludeArchives

.NOTES
    이 파일은 UTF-8 with BOM 으로 저장할 것.
    (Windows PowerShell 5.1 은 BOM 없는 파일을 MS949 로 읽는다)
#>
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Root,

    # 결과 저장 경로. DRM 자동암호화 회피를 위해 .dat 사용
    [string] $OutFile = ".\class-encoding-report.dat",

    # jar / war 안의 class 까지 검사
    [switch] $IncludeArchives,

    # 콘솔에 정상 문자열까지 출력 (리포트 파일에는 항상 전체가 기록됨)
    [switch] $ShowOk
)

$ErrorActionPreference = 'Stop'

# ── 엄격 인코더/디코더 (치환 대신 예외를 던지게 해야 판정이 성립) ──────────────
$EncFail = New-Object System.Text.EncoderExceptionFallback
$DecFail = New-Object System.Text.DecoderExceptionFallback

$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$Latin1     = [System.Text.Encoding]::GetEncoding(28591, $EncFail, $DecFail)
$Ms949      = [System.Text.Encoding]::GetEncoding(949,   $EncFail, $DecFail)

$RxHangul  = [regex] '[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]'
$RxHighLat = [regex] '[\u0080-\u00FF]'

# ── big-endian 2바이트 읽기 ───────────────────────────────────────────────────
# 주의: PowerShell 은 -shl 의 결과 타입을 왼쪽 피연산자 타입으로 유지한다.
#       [byte] 를 -shl 8 하면 byte 범위를 넘어 0 으로 잘린다. 반드시 [int] 캐스팅.
function Get-U2 {
    param([byte[]] $b, [int] $o)
    return (([int] $b[$o] -shl 8) -bor [int] $b[$o + 1])
}

# ── 상수풀 파서 ───────────────────────────────────────────────────────────────
# tag -> 고정 크기 (tag 1/5/6/8 은 별도 처리)
$CpSize = @{
    3 = 4; 4 = 4; 7 = 2; 9 = 4; 10 = 4; 11 = 4; 12 = 4
    15 = 3; 16 = 2; 17 = 4; 18 = 4; 19 = 2; 20 = 2
}

function Read-ClassConstants {
    param([byte[]] $Bytes, [string] $Label)

    if ($Bytes.Length -lt 10) { throw "파일이 너무 작음" }
    if (-not ($Bytes[0] -eq 0xCA -and $Bytes[1] -eq 0xFE -and
              $Bytes[2] -eq 0xBA -and $Bytes[3] -eq 0xBE)) {
        throw "class 파일이 아님 (magic 불일치)"
    }

    $major   = Get-U2 $Bytes 6
    $cpCount = Get-U2 $Bytes 8

    $utf8    = @{}
    $strRefs = New-Object System.Collections.Generic.List[int]

    $p = 10
    $i = 1
    while ($i -lt $cpCount) {
        $tag = $Bytes[$p]; $p++

        if ($tag -eq 1) {
            # CONSTANT_Utf8
            $len = Get-U2 $Bytes $p; $p += 2
            $raw = New-Object byte[] $len
            [Array]::Copy($Bytes, $p, $raw, 0, $len)
            $p += $len
            try   { $utf8[$i] = $Utf8Strict.GetString($raw) }
            catch { $utf8[$i] = $null }   # modified UTF-8 특수 케이스
        }
        elseif ($tag -eq 8) {
            # CONSTANT_String -> 실제 문자열 리터럴
            $strRefs.Add((Get-U2 $Bytes $p)); $p += 2
        }
        elseif ($tag -eq 5 -or $tag -eq 6) {
            # Long / Double 은 상수풀 슬롯 2개를 차지
            $p += 8; $i++
        }
        elseif ($CpSize.ContainsKey([int]$tag)) {
            $p += $CpSize[[int]$tag]
        }
        else {
            throw "알 수 없는 상수풀 tag $tag (offset $p)"
        }
        $i++
    }

    $lits = foreach ($r in $strRefs) {
        if ($utf8.ContainsKey($r)) {
            [pscustomobject]@{ Index = $r; Value = $utf8[$r] }
        }
    }

    [pscustomobject]@{
        Major    = $major
        Jdk      = Get-JdkLabel $major
        Literals = @($lits)
    }
}

function Get-JdkLabel([int] $major) {
    if ($major -ge 45 -and $major -le 48) { return "1.$($major - 44)" }
    if ($major -eq 49) { return '5' }
    if ($major -ge 50) { return "$($major - 44)" }
    return "?($major)"
}

# ── 역변환 검증 ───────────────────────────────────────────────────────────────
function Invoke-RoundTrip {
    param([string] $Text, [System.Text.Encoding] $Enc)

    try   { $raw = $Enc.GetBytes($Text) }      # 표현 불가 문자 -> 예외
    catch { return $null }

    try   { $back = $Utf8Strict.GetString($raw) }
    catch { return $null }                     # 유효한 UTF-8 아님 -> 정상 문자열

    # 깨진 문자열은 한글 1자가 3문자로 부풀어 있으므로 되돌리면 반드시 짧아진다
    if ($back.Length -ge $Text.Length) { return $null }
    return $back
}

function Get-Verdict {
    param([string] $Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return [pscustomobject]@{ Verdict = 'EMPTY'; Recovered = '' }
    }

    # U+FFFD = 컴파일 시점에 이미 원본이 파괴된 경우 (복원 불가)
    # MS949 소스를 -encoding UTF-8 로 컴파일하면 발생.
    # JDK 8 javac 는 경고만 내고 치환했으나 JDK 12+ 는 에러로 막는다.
    if ($Text.IndexOf([char]0xFFFD) -ge 0) {
        return [pscustomobject]@{ Verdict = 'LOST_FFFD'; Recovered = '(복원 불가 - 소스에서 재컴파일 필요)' }
    }

    $isAscii = $true
    foreach ($c in $Text.ToCharArray()) { if ([int]$c -ge 0x80) { $isAscii = $false; break } }
    if ($isAscii) {
        return [pscustomobject]@{ Verdict = 'ASCII'; Recovered = '' }
    }

    if ($RxHangul.IsMatch($Text)) {
        # 겉보기엔 한글이지만 UTF-8 을 MS949 로 읽은 결과일 수 있음 (주로 런타임 경로)
        $r = Invoke-RoundTrip $Text $Ms949
        if ($r -and $RxHangul.IsMatch($r)) {
            return [pscustomobject]@{ Verdict = 'BROKEN_MS949'; Recovered = $r }
        }
        return [pscustomobject]@{ Verdict = 'OK'; Recovered = '' }
    }

    if ($RxHighLat.IsMatch($Text)) {
        # UTF-8 소스를 ISO-8859-1 로 컴파일한 경우
        $r = Invoke-RoundTrip $Text $Latin1
        if ($r) {
            return [pscustomobject]@{ Verdict = 'BROKEN_LATIN1'; Recovered = $r }
        }
    }

    return [pscustomobject]@{ Verdict = 'OK'; Recovered = '' }
}

# ── 스캔 ──────────────────────────────────────────────────────────────────────
function Escape-Field([string] $s) {
    if ($null -eq $s) { return '' }
    $s -replace "`t", '\t' -replace "`r", '' -replace "`n", '\n'
}

$rows    = New-Object System.Collections.Generic.List[object]
$errors  = New-Object System.Collections.Generic.List[object]

function Scan-One {
    param([byte[]] $Bytes, [string] $Source, [string] $Entry)

    try   { $info = Read-ClassConstants -Bytes $Bytes -Label $Entry }
    catch {
        $errors.Add([pscustomobject]@{ Source = $Source; Entry = $Entry; Message = $_.Exception.Message })
        return
    }

    foreach ($lit in $info.Literals) {
        $v = Get-Verdict $lit.Value
        $rows.Add([pscustomobject]@{
            Source = $Source; Entry = $Entry; Major = $info.Major; Jdk = $info.Jdk
            Index = $lit.Index; Verdict = $v.Verdict
            Value = $lit.Value; Recovered = $v.Recovered
        })
    }
}

if (-not (Test-Path -LiteralPath $Root)) { throw "경로 없음: $Root" }

Write-Host "스캔 시작: $Root" -ForegroundColor Cyan

Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.class | ForEach-Object {
    Scan-One -Bytes ([System.IO.File]::ReadAllBytes($_.FullName)) `
             -Source $_.FullName -Entry ''
}

if ($IncludeArchives) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $_.Extension -in '.jar', '.war', '.ear' } | ForEach-Object {
            $archivePath = $_.FullName
            $zip = $null
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
                foreach ($e in $zip.Entries) {
                    if ($e.FullName -notlike '*.class') { continue }
                    $ms = New-Object System.IO.MemoryStream
                    $st = $e.Open()
                    $st.CopyTo($ms); $st.Close()
                    Scan-One -Bytes $ms.ToArray() -Source $archivePath -Entry $e.FullName
                    $ms.Dispose()
                }
            }
            catch {
                $errors.Add([pscustomobject]@{ Source = $archivePath; Entry = ''; Message = $_.Exception.Message })
            }
            finally { if ($zip) { $zip.Dispose() } }
        }
}

# ── 출력 ──────────────────────────────────────────────────────────────────────
$reported = $rows

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("Source`tEntry`tMajor`tJdk`tIndex`tVerdict`tValue`tRecovered"))
foreach ($r in $reported) {
    $lines.Add((
        "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f `
            $r.Source, $r.Entry, $r.Major, $r.Jdk, $r.Index, $r.Verdict,
            (Escape-Field $r.Value), (Escape-Field $r.Recovered)
    ))
}
$outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile }
           else { Join-Path (Get-Location).Path $OutFile }
[System.IO.File]::WriteAllLines(
    $outPath,
    $lines,
    (New-Object System.Text.UTF8Encoding($true))   # BOM 포함 -> 엑셀에서 바로 열림
)

$broken = @($reported | Where-Object { $_.Verdict -like 'BROKEN*' -or $_.Verdict -eq 'LOST_FFFD' })
$total  = ($rows | Measure-Object).Count
$files  = ($rows | Select-Object -ExpandProperty Source -Unique | Measure-Object).Count

Write-Host ""
Write-Host ("검사 파일 수 : {0}" -f $files)
Write-Host ("문자열 리터럴: {0}" -f $total)
Write-Host ("major version: {0}" -f (($rows | Select-Object -ExpandProperty Major -Unique | Sort-Object) -join ', '))

if ($broken.Count -eq 0) {
    Write-Host "깨짐 없음 (정상)" -ForegroundColor Green
} else {
    Write-Host ("깨짐 {0}건" -f $broken.Count) -ForegroundColor Red
    $broken | Select-Object -First 20 | ForEach-Object {
        Write-Host ("  [{0}] {1}" -f $_.Verdict, (Split-Path $_.Source -Leaf))
        Write-Host ("      현재: {0}" -f $_.Value)
        Write-Host ("      원문: {0}" -f $_.Recovered) -ForegroundColor Yellow
    }
    if ($broken.Count -gt 20) { Write-Host ("  ... 외 {0}건" -f ($broken.Count - 20)) }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host ("파싱 실패 {0}건:" -f $errors.Count) -ForegroundColor DarkYellow
    $errors | Select-Object -First 10 | ForEach-Object {
        Write-Host ("  {0} {1} : {2}" -f $_.Source, $_.Entry, $_.Message)
    }
}

Write-Host ""
Write-Host ("리포트: {0}" -f $outPath) -ForegroundColor Cyan
