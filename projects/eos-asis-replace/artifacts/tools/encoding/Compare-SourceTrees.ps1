# ===========================================================================
# [표준 헤더] Compare-SourceTrees.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-3  세대 대조
#   역할 : 두 소스 트리 전수 비교 (해시 -> 인코딩 감지 -> 텍스트 비교)
#   입력 : -LeftRoot 형상 소스, -RightRoot WAS 소스
#   출력 : Compare-SourceTrees\<프로젝트>_<일시>.dat
#   선행 : 양쪽 트리 확보. 읽기 전용 — 원본 수정 안 함
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
    두 소스 트리(예: ChangeFlow 소스 vs WAS 다운로드 소스)를 전수 비교한다.

.DESCRIPTION
    [1단계 전수조사] 비교 로직:
      1) 상대경로 기준으로 양쪽 트리의 파일 매칭
      2) SHA256 해시 비교 → 동일하면 SAME_HASH
      3) 해시가 다르면 인코딩을 각각 감지(UTF-8 BOM / UTF-8 / ASCII / MS949)해서
         텍스트 레벨로 2차 비교 (줄바꿈 CRLF/LF 정규화 후)
         - 텍스트 동일 + 인코딩 다름  → SAME_TEXT_DIFF_ENCODING  (인코딩만 변환된 파일)
         - 텍스트 동일 + 인코딩 같음  → SAME_TEXT_DIFF_EOL_OR_BOM (줄바꿈/BOM 차이)
         - 텍스트 다름               → DIFF_CONTENT (실제 내용 차이, 최초 차이 라인 기록)
      4) 한쪽에만 존재 → ONLY_LEFT / ONLY_RIGHT (형상관리 누락 또는 서버 직수정 의심)

    출력: 파이프(|) 구분자, UTF-8 BOM 포함 .dat (엑셀 바로 열기 가능)
    읽기 전용 조사이므로 -WhatIf 불필요. 원본 파일은 절대 수정하지 않는다.

.PARAMETER LeftRoot
    왼쪽 트리 루트 (예: C:\audit\changeflow-src)

.PARAMETER RightRoot
    오른쪽 트리 루트 (예: C:\audit\was-src)

.PARAMETER LeftLabel / RightLabel
    리포트에 표시할 라벨 (기본: ChangeFlow / WAS)

.PARAMETER Include
    비교 대상 확장자 패턴 (기본: *.java, *.jsp, *.properties, *.xml)

.PARAMETER ProjectName
    결과 파일명에 쓸 프로젝트명 (미지정 시 양쪽 Root 경로에서 자동 추출해 "왼쪽_vs_오른쪽")

.PARAMETER OutFile
    출력 경로 직접 지정 (미지정 시 .\Compare-SourceTrees\<프로젝트명>_<일시>.dat 자동 생성)

.EXAMPLE
    .\Compare-SourceTrees.ps1 -LeftRoot C:\audit\changeflow-src -RightRoot C:\audit\was-src

.EXAMPLE
    # java만 빠르게
    .\Compare-SourceTrees.ps1 -LeftRoot C:\a -RightRoot C:\b -Include *.java
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LeftRoot,

    [Parameter(Mandatory = $true)]
    [string]$RightRoot,

    [string]$LeftLabel  = "ChangeFlow",
    [string]$RightLabel = "WAS",

    [string[]]$Include = @("*.java", "*.jsp", "*.properties", "*.xml"),

    [string]$ProjectName,          # 미지정 시 양쪽 Root 경로에서 자동 추출
    [string]$OutFile               # 미지정 시 .\Compare-SourceTrees\<프로젝트명>_<일시>.dat
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 준비
# ---------------------------------------------------------------------------
$LeftRoot  = (Resolve-Path $LeftRoot).Path.TrimEnd('\')
$RightRoot = (Resolve-Path $RightRoot).Path.TrimEnd('\')

# 출력 경로 자동 결정: .\Compare-SourceTrees\<왼쪽프로젝트>_vs_<오른쪽프로젝트>_<일시>.dat
$scanName = "Compare-SourceTrees"
function Get-AutoProjectName {
    param([string]$Path)
    $generic = @('classes','class','web-inf','lib','target','build','bin','out','dist',
                 'src','main','java','resources','webapp','webcontent','deploy','app','work')
    $parts = $Path -split '\\'
    for ($k = $parts.Count - 1; $k -ge 0; $k--) {
        $p = $parts[$k]
        if ($p -and ($generic -notcontains $p.ToLower())) { return $p }
    }
    return "tree"
}
if (-not $ProjectName) {
    $ProjectName = "{0}_vs_{1}" -f (Get-AutoProjectName $LeftRoot), (Get-AutoProjectName $RightRoot)
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')   # 파일명 금지 문자 제거

if (-not $OutFile) {
    $outDirAuto = Join-Path (Get-Location).Path $scanName
    if (-not (Test-Path $outDirAuto)) { New-Item -ItemType Directory -Path $outDirAuto | Out-Null }
    $OutFile = Join-Path $outDirAuto ("{0}_{1}.dat" -f $ProjectName, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$outFile = $OutFile

# 인코더 (엄격 모드: 잘못된 바이트 시 예외 발생 → 인코딩 판별용)
$utf8Strict  = New-Object System.Text.UTF8Encoding($false, $true)
$ms949Strict = [System.Text.Encoding]::GetEncoding(949,
                    [System.Text.EncoderFallback]::ExceptionFallback,
                    [System.Text.DecoderFallback]::ExceptionFallback)
$ms949Loose  = [System.Text.Encoding]::GetEncoding(949)

# ---------------------------------------------------------------------------
# 함수: 파일 수집 (상대경로 소문자 키 → 원본 상대경로 + FullName)
# ---------------------------------------------------------------------------
function Get-TreeFiles {
    param([string]$Root, [string[]]$Patterns)
    $map = @{}
    foreach ($pat in $Patterns) {
        Get-ChildItem -Path $Root -Recurse -File -Filter $pat -ErrorAction SilentlyContinue |
        ForEach-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
            $map[$rel.ToLower()] = [PSCustomObject]@{
                RelPath  = $rel
                FullName = $_.FullName
                Size     = $_.Length
            }
        }
    }
    return $map
}

# ---------------------------------------------------------------------------
# 함수: 인코딩 감지 + 텍스트 디코딩
#   반환: Encoding 이름, 디코딩된 텍스트, U+FFFD 포함 여부
# ---------------------------------------------------------------------------
function Get-DecodedText {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # UTF-8 BOM
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $text = $utf8Strict.GetString($bytes, 3, $bytes.Length - 3)
        $enc  = "UTF-8-BOM"
    }
    else {
        # UTF-8 엄격 디코딩 시도
        $decodedUtf8 = $null
        try { $decodedUtf8 = $utf8Strict.GetString($bytes) } catch { }

        if ($null -ne $decodedUtf8) {
            $isAscii = $true
            foreach ($b in $bytes) { if ($b -ge 0x80) { $isAscii = $false; break } }
            $text = $decodedUtf8
            $enc  = if ($isAscii) { "ASCII" } else { "UTF-8" }
        }
        else {
            # UTF-8 실패 → MS949 시도
            try {
                $text = $ms949Strict.GetString($bytes)
                $enc  = "MS949"
            }
            catch {
                $text = $ms949Loose.GetString($bytes)
                $enc  = "UNKNOWN/BINARY"
            }
        }
    }

    $hasFFFD = $text.IndexOf([char]0xFFFD) -ge 0
    if ($hasFFFD) { $enc = "$enc(FFFD)" }   # 파일 자체에 U+FFFD 오염 존재

    return [PSCustomObject]@{
        Encoding = $enc
        Text     = $text
        HasFFFD  = $hasFFFD
    }
}

# ---------------------------------------------------------------------------
# 함수: 정규화(줄바꿈 통일) 후 라인 배열
# ---------------------------------------------------------------------------
function Get-NormalizedLines {
    param([string]$Text)
    $norm = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    return , ($norm -split "`n")
}

# ---------------------------------------------------------------------------
# 수집
# ---------------------------------------------------------------------------
Write-Host "[수집] $LeftLabel : $LeftRoot" -ForegroundColor Cyan
$leftMap  = Get-TreeFiles -Root $LeftRoot  -Patterns $Include
Write-Host "        -> $($leftMap.Count) 개 파일"
Write-Host "[수집] $RightLabel : $RightRoot" -ForegroundColor Cyan
$rightMap = Get-TreeFiles -Root $RightRoot -Patterns $Include
Write-Host "        -> $($rightMap.Count) 개 파일"

$allKeys = [System.Collections.Generic.HashSet[string]]::new()
$leftMap.Keys  | ForEach-Object { [void]$allKeys.Add($_) }
$rightMap.Keys | ForEach-Object { [void]$allKeys.Add($_) }
$sortedKeys = $allKeys | Sort-Object

# ---------------------------------------------------------------------------
# 비교
# ---------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$total   = $sortedKeys.Count
$idx     = 0

foreach ($key in $sortedKeys) {
    $idx++
    if ($idx % 200 -eq 0) {
        Write-Host ("[진행] {0} / {1}" -f $idx, $total)
    }

    $L = $leftMap[$key]
    $R = $rightMap[$key]

    # --- 한쪽에만 존재 ---
    if ($null -eq $R) {
        $results.Add([PSCustomObject]@{
            Status = "ONLY_LEFT"; RelPath = $L.RelPath
            LeftEnc = ""; RightEnc = ""
            LeftSize = $L.Size; RightSize = ""
            LeftHash8 = ""; RightHash8 = ""
            FirstDiffLine = ""; DiffLineCount = ""
            Note = "$LeftLabel 에만 존재 (서버 미배포 or WAS 회수 누락 의심)"
        })
        continue
    }
    if ($null -eq $L) {
        $results.Add([PSCustomObject]@{
            Status = "ONLY_RIGHT"; RelPath = $R.RelPath
            LeftEnc = ""; RightEnc = ""
            LeftSize = ""; RightSize = $R.Size
            LeftHash8 = ""; RightHash8 = ""
            FirstDiffLine = ""; DiffLineCount = ""
            Note = "$RightLabel 에만 존재 (형상관리 누락 or 서버 직수정 의심)"
        })
        continue
    }

    # --- 해시 비교 ---
    $lHash = (Get-FileHash -Path $L.FullName -Algorithm SHA256).Hash
    $rHash = (Get-FileHash -Path $R.FullName -Algorithm SHA256).Hash
    $lHash8 = $lHash.Substring(0, 8)
    $rHash8 = $rHash.Substring(0, 8)

    if ($lHash -eq $rHash) {
        $results.Add([PSCustomObject]@{
            Status = "SAME_HASH"; RelPath = $L.RelPath
            LeftEnc = ""; RightEnc = ""
            LeftSize = $L.Size; RightSize = $R.Size
            LeftHash8 = $lHash8; RightHash8 = $rHash8
            FirstDiffLine = ""; DiffLineCount = ""
            Note = ""
        })
        continue
    }

    # --- 해시 다름 → 인코딩 감지 후 텍스트 2차 비교 ---
    $lDec = Get-DecodedText -Path $L.FullName
    $rDec = Get-DecodedText -Path $R.FullName

    $lLines = Get-NormalizedLines -Text $lDec.Text
    $rLines = Get-NormalizedLines -Text $rDec.Text

    $textEqual = $false
    if ($lLines.Count -eq $rLines.Count) {
        $textEqual = $true
        for ($i = 0; $i -lt $lLines.Count; $i++) {
            if ($lLines[$i] -cne $rLines[$i]) { $textEqual = $false; break }
        }
    }

    if ($textEqual) {
        if ($lDec.Encoding -ne $rDec.Encoding) {
            $status = "SAME_TEXT_DIFF_ENCODING"
            $note   = "내용 동일, 인코딩만 다름 ($($lDec.Encoding) vs $($rDec.Encoding))"
        }
        else {
            $status = "SAME_TEXT_DIFF_EOL_OR_BOM"
            $note   = "내용 동일, 줄바꿈(CRLF/LF) 또는 BOM/공백 차이"
        }
        $results.Add([PSCustomObject]@{
            Status = $status; RelPath = $L.RelPath
            LeftEnc = $lDec.Encoding; RightEnc = $rDec.Encoding
            LeftSize = $L.Size; RightSize = $R.Size
            LeftHash8 = $lHash8; RightHash8 = $rHash8
            FirstDiffLine = ""; DiffLineCount = 0
            Note = $note
        })
        continue
    }

    # --- 실제 내용 차이 ---
    $minCount   = [Math]::Min($lLines.Count, $rLines.Count)
    $firstDiff  = 0
    $diffCount  = [Math]::Abs($lLines.Count - $rLines.Count)
    for ($i = 0; $i -lt $minCount; $i++) {
        if ($lLines[$i] -cne $rLines[$i]) {
            if ($firstDiff -eq 0) { $firstDiff = $i + 1 }
            $diffCount++
        }
    }
    if ($firstDiff -eq 0 -and $lLines.Count -ne $rLines.Count) {
        $firstDiff = $minCount + 1   # 앞부분 동일, 뒤에 라인 추가/삭제
    }

    $noteParts = @("실제 내용 차이")
    if ($lDec.HasFFFD -or $rDec.HasFFFD) { $noteParts += "주의: U+FFFD 오염 파일 포함" }
    if ($lDec.Encoding -ne $rDec.Encoding) { $noteParts += "인코딩도 다름" }

    $results.Add([PSCustomObject]@{
        Status = "DIFF_CONTENT"; RelPath = $L.RelPath
        LeftEnc = $lDec.Encoding; RightEnc = $rDec.Encoding
        LeftSize = $L.Size; RightSize = $R.Size
        LeftHash8 = $lHash8; RightHash8 = $rHash8
        FirstDiffLine = $firstDiff; DiffLineCount = $diffCount
        Note = ($noteParts -join " / ")
    })
}

# ---------------------------------------------------------------------------
# 출력 (.dat : 파이프 구분자, UTF-8 BOM)
# ---------------------------------------------------------------------------
$statusOrder = @{
    "DIFF_CONTENT"              = 1
    "ONLY_RIGHT"                = 2
    "ONLY_LEFT"                 = 3
    "SAME_TEXT_DIFF_ENCODING"   = 4
    "SAME_TEXT_DIFF_EOL_OR_BOM" = 5
    "SAME_HASH"                 = 6
}
$sorted = $results | Sort-Object @{Expression = { $statusOrder[$_.Status] }}, RelPath

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Status|RelPath|${LeftLabel}Enc|${RightLabel}Enc|${LeftLabel}Size|${RightLabel}Size|${LeftLabel}Hash8|${RightLabel}Hash8|FirstDiffLine|DiffLineCount|Note")
foreach ($r in $sorted) {
    $lines.Add(($r.Status, $r.RelPath, $r.LeftEnc, $r.RightEnc,
                $r.LeftSize, $r.RightSize, $r.LeftHash8, $r.RightHash8,
                $r.FirstDiffLine, $r.DiffLineCount, $r.Note) -join "|")
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($outFile, $lines, $utf8Bom)

# ---------------------------------------------------------------------------
# 콘솔 요약
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============== 비교 요약 ===============" -ForegroundColor Yellow
$summary = $results | Group-Object Status | Sort-Object @{Expression = { $statusOrder[$_.Name] }}
foreach ($g in $summary) {
    $color = switch ($g.Name) {
        "DIFF_CONTENT" { "Red" }
        "ONLY_RIGHT"   { "Red" }
        "ONLY_LEFT"    { "Magenta" }
        "SAME_TEXT_DIFF_ENCODING" { "Yellow" }
        default        { "Green" }
    }
    Write-Host ("  {0,-28} : {1,6} 개" -f $g.Name, $g.Count) -ForegroundColor $color
}
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "  프로젝트: $ProjectName"
Write-Host "  전체: $($results.Count) 개"
Write-Host "  결과 파일: $outFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "  * DIFF_CONTENT / ONLY_* 부터 확인할 것" -ForegroundColor Gray
Write-Host "  * SAME_TEXT_DIFF_ENCODING 은 내용 동일 → 인코딩 통일 대상 목록으로 활용 가능" -ForegroundColor Gray
