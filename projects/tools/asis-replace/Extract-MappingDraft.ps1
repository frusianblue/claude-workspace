# ===========================================================================
# [표준 헤더] Extract-MappingDraft.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-2  매핑표 초안
#   역할 : Find 리포트에서 매핑표 골격 추출 (Folder-Check/Ip-Check 통합)
#   입력 : -Report Find 리포트 .dat, -Mode Path|Ip
#   출력 : report\<소스명>_mapping_draft_<path|ip>.dat
#   선행 : A-1 Find 실행 완료
#   상태 : 현행 v1 (2026-08-13 신규)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# ===========================================================================
# Extract-MappingDraft.ps1  (v1, 2026-08-13 신규)
#   계열 : A (경로/IP 치환)
#   단계 : A-2 — Find 리포트에서 매핑표 '초안'을 뽑는다
#   입력 : Find-AsisPath 리포트 (.dat, 쉼표 구분 CSV)
#   출력 : report\<소스명>_mapping_draft_<path|ip>.dat  (매핑표 골격)
#   선행 : Find-AsisPath.ps1 실행 완료
# ===========================================================================
#
# ── 이 스크립트가 대체하는 것 ────────────────────────────────────────
#   Folder-Check.ps1 / Ip-Check.ps1 / "folder-find 실행.txt" 본문 스니펫
#   → 같은 파이프라인이 3벌로 흩어져 있었고, 하드코딩된 입력 파일명
#     (portal_asis.dat / portal_ip_all.dat)이 실제 리포트명
#     (report\portal_asis_path_report.dat)과 달라 그대로 실행하면 실패했다.
#
# ── 사용법 ──────────────────────────────────────────────────────────
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Path
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_ip_all.dat          -Mode Ip
#   .\Extract-MappingDraft.ps1 -Report ... -Mode Path -ConsoleOnly         # 파일 저장 없이 목록만
#
# ── 중요 ────────────────────────────────────────────────────────────
#   이건 '초안'이다. NewPath/NewIP 열은 비어 있으므로 사람이 채워야 한다.
#   - 경로: 긴 경로가 자동 우선 적용되므로 상위/하위 경로가 같이 나와도 둘 다 남겨도 된다
#   - IP  : 127.0.0.1 / 0.0.0.0 / 버전번호(1.2.3.4) 등은 자동 제외되지 않는다.
#           매핑표에 넣기 전에 반드시 눈으로 걸러낼 것 (IP치환 가이드 1단계 표 참조)
#
#   출력은 UTF-8 BOM (.dat) — 회사 DRM csv 자동 암호화 회피 + PS 5.1 한글 비고 보존
# ===========================================================================

param(
    [Parameter(Mandatory=$true)][string]$Report,
    [ValidateSet("Path","Ip")]
    [string]$Mode = "Path",
    [string]$Out,                        # 미지정 시 리포트 옆 report\<소스명>_mapping_draft_<mode>.dat
    [string]$Delimiter = ",",            # Find 리포트는 Export-Csv 기본(쉼표)
    [switch]$ConsoleOnly
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

if (-not (Test-Path $Report)) { Write-Error "리포트 파일 없음: $Report"; exit 1 }

# FoundIn=FILE 만 대상 — CLASS/JAR/WAR는 재빌드·재패키징으로 해소되므로 매핑표 재료가 아니다
$rows = @(Import-Csv -Path $Report -Delimiter $Delimiter | Where-Object { $_.FoundIn -eq 'FILE' })
if ($rows.Count -eq 0) {
    Write-Warning "FoundIn=FILE 행이 없음. 리포트가 Find-AsisPath 산출물이 맞는지, 구분자가 '$Delimiter'인지 확인할 것"
    exit 1
}

switch ($Mode) {
    "Path" {
        # d:/... 또는 d:\... 형태를 2세그먼트까지 잡는다 (따옴표·괄호·공백에서 끊김)
        $rx     = '[dD]:[/\\]+[^/\\";''<>\s,)]*[/\\]?[^/\\";''<>\s,)]*'
        $header = "OldPath,NewPath,비고"
        $suffix = "path"
    }
    "Ip" {
        $rx     = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'
        $header = "업무코드,업무명,서버명,호스트명,OldIP,NewIP,OldPort,NewPort"
        $suffix = "ip"
    }
}

$values = $rows |
    ForEach-Object { [regex]::Matches($_.Match, $rx) } |
    ForEach-Object {
        if ($Mode -eq "Path") { ($_.Value -replace '[\\/]+','/').ToLower() }
        else                  { $_.Value }
    } |
    Sort-Object -Unique

if ($values.Count -eq 0) { Write-Warning "추출된 값이 없음"; exit 1 }

Write-Host "===== Extract-MappingDraft v1 (Mode=$Mode) ====="
Write-Host "리포트   : $Report ($($rows.Count) FILE 행)"
Write-Host "추출 결과: $($values.Count)건 (중복 제거 후)"
Write-Host ""
$values | ForEach-Object { Write-Host "  $_" }

if ($ConsoleOnly) { return }

# 출력 경로 결정
if (-not $Out) {
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Report)
    $leaf = ($leaf -split '_')[0]                       # portal_asis_path_report -> portal
    $dir  = Split-Path $Report -Parent
    if (-not $dir) { $dir = "report" }
    $Out  = Join-Path $dir ("{0}_mapping_draft_{1}.dat" -f $leaf, $suffix)
}
$outParent = Split-Path $Out -Parent
if ($outParent -and -not (Test-Path $outParent)) {
    New-Item -ItemType Directory -Path $outParent -Force | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# $Mode 매핑표 초안 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("# 출처: $Report")
$lines.Add("# New 열이 비어 있다. 채운 뒤 Replace 스크립트의 -Map 으로 넘길 것.")
if ($Mode -eq "Ip") {
    $lines.Add("# 127.0.0.1 / 0.0.0.0 / 버전번호 등 치환 대상이 아닌 값이 섞여 있다 — 반드시 선별할 것")
}
$lines.Add($header)
foreach ($v in $values) {
    if ($Mode -eq "Path") { $lines.Add("$v,,") }
    else                  { $lines.Add(",,,,$v,,,") }
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($Out, $lines, $utf8Bom)

Write-Host ""
Write-Host "-> $Out"
Write-Host "다음 단계 : New 열을 채운 뒤 Replace-Asis$Mode.ps1 -Map 으로 DryRun"
