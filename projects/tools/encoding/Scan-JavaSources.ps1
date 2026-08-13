# ===========================================================================
# [표준 헤더] Scan-JavaSources.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-4  현황 조사 (소스측)
#   역할 : .java 인코딩 판별 + 한글/FFFD 라인 상세
#   입력 : -Root 소스 루트
#   출력 : Scan-JavaSources\<프로젝트>_<일시>.dat (+ -lines)
#   선행 : 읽기 전용
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Scan-JavaSources.ps1 — .java 소스 인코딩 판별 + 한글/깨짐(FFFD) 라인 상세 (라인 번호 포함)

.USAGE
  # 기본 실행: 현재 위치에 .\Scan-JavaSources\ 폴더 자동 생성 후
  #            <프로젝트명>_<yyyyMMdd_HHmmss>.dat / -lines.dat 자동 저장
  #            (프로젝트명은 Root 경로에서 자동 추출: src/main/java 등 범용 폴더명은 건너뜀)
  .\Scan-JavaSources.ps1 -Root "D:\src\MAR"

  .\Scan-JavaSources.ps1 -Root ... -ProjectName MAR             # 프로젝트명 직접 지정
  .\Scan-JavaSources.ps1 -Root ... -OutFile D:\src-scan.dat     # 출력 경로 직접 지정 (자동 규칙 무시)
  .\Scan-JavaSources.ps1 -Root ... -Delimiter "`t"              # 탭 구분 (엑셀 더블클릭용)

  # 콘솔에서 필터링 (파일 저장 안 함)
  .\Scan-JavaSources.ps1 -Root "D:\src\MAR" -ConsoleOnly | Where-Object 판정 -eq "MS949(추정)"

.판정 기준
  MS949(추정)  : strict UTF-8 디코드 실패 + MS949로 읽으면 한글 → Convert-ToUtf8 변환 대상
  UTF-8        : 정상 (BOM 없음)
  UTF-8(BOM)   : javac -encoding UTF-8에서 illegal character 에러 가능 → BOM 제거 필요
  손상(FFFD)   : 소스 안에 U+FFFD(�) 문자가 이미 존재 → 과거에 잘못 변환된 파일, 원본 재확보 필요
  ASCII        : 한글 리터럴 없음 → 인코딩 무관
  판별불가     : UTF-8도 아니고 MS949 한글도 안 나옴 → 수동 확인

  ※ 리포트 dat는 엑셀용으로 UTF-8 BOM 포함 저장.
    (소스 변환 저장은 Convert-ToUtf8.ps1이 BOM 없이 저장 — 용도별 BOM 유무 반대인 점 주의)
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Root,
    [string]$ProjectName,          # 미지정 시 Root 경로에서 자동 추출
    [string]$OutFile,              # 미지정 시 .\Scan-JavaSources\<프로젝트명>_<일시>.dat 자동 생성
    [string]$Delimiter = "|",
    [int]$MaxContentLen = 160,
    [switch]$ConsoleOnly           # 파일 저장 없이 콘솔 객체 출력만 (파이프 필터링용)
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

if (-not (Test-Path $Root)) { Write-Error "경로 없음: $Root"; exit 1 }
$Root = (Resolve-Path $Root).Path.TrimEnd('\')

# ---------------------------------------------------------------------------
# 출력 경로 자동 결정: .\Scan-JavaSources\<프로젝트명>_<일시>.dat
# ---------------------------------------------------------------------------
$scanName = "Scan-JavaSources"
if (-not $ProjectName) {
    $generic = @('classes','class','web-inf','lib','target','build','bin','out','dist',
                 'src','main','java','resources','webapp','webcontent','deploy','app','work')
    $parts = $Root -split '\\'
    for ($k = $parts.Count - 1; $k -ge 0; $k--) {
        $p = $parts[$k]
        if ($p -and ($generic -notcontains $p.ToLower())) { $ProjectName = $p; break }
    }
    if (-not $ProjectName) { $ProjectName = "scan" }
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')   # 파일명 금지 문자 제거

if ($ConsoleOnly) {
    $OutFile = $null
}
elseif (-not $OutFile) {
    $outDir = Join-Path (Get-Location).Path $scanName
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $OutFile = Join-Path $outDir ("{0}_{1}.dat" -f $ProjectName, (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)   # 디코드 실패 시 예외
$ms949      = [System.Text.Encoding]::GetEncoding(949)

$summary = New-Object System.Collections.Generic.List[object]
$detail  = New-Object System.Collections.Generic.List[object]

$reKorean = '[\uAC00-\uD7A3\u3130-\u318F\u1100-\u11FF]'
$chFFFD   = [char]0xFFFD

$files = Get-ChildItem -Path $Root -Recurse -Filter *.java -File
$total = $files.Count
$i = 0

foreach ($file in $files) {
    $i++
    Write-Progress -Activity "소스 스캔" -Status "$i / $total  $($file.Name)" -PercentComplete (100 * $i / $total)

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $rel   = $file.FullName.Substring($Root.Length).TrimStart('\')

    $enc = $null; $text = $null
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    if ($hasBom) {
        $enc  = "UTF-8(BOM)"
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    else {
        try {
            $text = $utf8Strict.GetString($bytes)
            $nonAscii = $false
            foreach ($b in $bytes) { if ($b -gt 0x7F) { $nonAscii = $true; break } }
            $enc = if ($nonAscii) { "UTF-8" } else { "ASCII" }
        }
        catch {
            $text = $ms949.GetString($bytes)
            $enc  = if ($text -match $reKorean) { "MS949(추정)" } else { "판별불가" }
        }
    }

    # 라인별 상세: 한글 포함 라인 + FFFD 포함 라인
    $srcLines = $text -split "`n"
    $koreanCnt = 0; $fffdCnt = 0
    for ($ln = 0; $ln -lt $srcLines.Count; $ln++) {
        $line = $srcLines[$ln].TrimEnd("`r")
        $hasKor  = $line -match $reKorean
        $hasFFFD = $line.Contains($chFFFD)
        if (-not ($hasKor -or $hasFFFD)) { continue }

        if ($hasKor)  { $koreanCnt++ }
        if ($hasFFFD) { $fffdCnt++ }

        $type = if ($hasFFFD -and $hasKor) { "한글+FFFD" } elseif ($hasFFFD) { "FFFD" } else { "한글" }
        $content = $line.Trim()
        if ($content.Length -gt $MaxContentLen) { $content = $content.Substring(0, $MaxContentLen) + "..." }

        $detail.Add([PSCustomObject]@{
            File   = $rel
            판정   = $enc
            Line   = $ln + 1
            유형   = $type
            내용   = $content
        })
    }

    # 최종 판정 및 권장 조치
    $status = $enc
    if (($enc -eq "UTF-8" -or $enc -eq "UTF-8(BOM)") -and $fffdCnt -gt 0) { $status = "손상(FFFD)" }

    $action = switch ($status) {
        "MS949(추정)" { "Convert-ToUtf8 변환" }
        "UTF-8(BOM)"  { "BOM 제거 (Convert-ToUtf8 재저장)" }
        "손상(FFFD)"  { "원본 재확보 (변환으로 복구 불가)" }
        "판별불가"    { "수동 확인" }
        default       { "-" }
    }

    $summary.Add([PSCustomObject]@{
        File     = $rel
        판정     = $status
        한글라인 = $koreanCnt
        FFFD라인 = $fffdCnt
        총라인   = $srcLines.Count
        조치     = $action
    })
}
Write-Progress -Activity "소스 스캔" -Completed

if ($OutFile) {
    $encOut = New-Object System.Text.UTF8Encoding($true)   # 리포트는 BOM 포함 (엑셀용)

    $hdr = @("File","판정","한글라인","FFFD라인","총라인","조치") -join $Delimiter
    $rows = $summary | ForEach-Object { @($_.File,$_.판정,$_.한글라인,$_.FFFD라인,$_.총라인,$_.조치) -join $Delimiter }
    [System.IO.File]::WriteAllLines($OutFile, (@($hdr) + $rows), $encOut)

    $detailFile = [System.IO.Path]::ChangeExtension($OutFile, $null).TrimEnd('.') + "-lines" + [System.IO.Path]::GetExtension($OutFile)
    $hdr2 = @("File","판정","Line","유형","내용") -join $Delimiter
    $rows2 = $detail | ForEach-Object { @($_.File,$_.판정,$_.Line,$_.유형,$_.내용) -join $Delimiter }
    [System.IO.File]::WriteAllLines($detailFile, (@($hdr2) + $rows2), $encOut)

    $ms949Cnt = ($summary | Where-Object 판정 -eq "MS949(추정)").Count
    $bomCnt   = ($summary | Where-Object 판정 -eq "UTF-8(BOM)").Count
    $brokenCnt= ($summary | Where-Object 판정 -eq "손상(FFFD)").Count
    Write-Host ""
    Write-Host "프로젝트: $ProjectName  (Root: $Root)"
    Write-Host "완료: $total 파일 스캔"
    Write-Host "  요약  → $OutFile"
    Write-Host "  상세  → $detailFile  (라인번호 포함, $($detail.Count)건)"
    Write-Host "  변환 대상 MS949: $ms949Cnt / BOM 제거: $bomCnt / 손상 FFFD: $brokenCnt"
}
else {
    $summary
}
