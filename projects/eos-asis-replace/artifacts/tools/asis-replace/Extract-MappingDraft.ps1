# ===========================================================================
# [표준 헤더] Extract-MappingDraft.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-2  매핑표 초안
#   역할 : Find 리포트에서 매핑표 골격 추출 (Folder-Check/Ip-Check 통합)
#   입력 : -Report Find 리포트 .dat, -Mode Path|Ip|Domain|Port
#   출력 : report\<소스명>_mapping_draft_<path|ip|domain|port>.dat
#   선행 : A-1 Find 실행 완료
#   상태 : 현행 v2
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Extract-MappingDraft.ps1  (v2)
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v1 (2026-08-13): Find 리포트 -> OldPath/OldIP 초안. Match(줄 전체)에서 정규식 재추출
# v2: (1) Find v9의 Kind/Value 컬럼을 직접 사용 — 줄 텍스트 재파싱보다 정확
#         (Kind 컬럼이 없는 v8.2 리포트면 자동으로 v1 방식(Match 재추출)으로 폴백)
#     (2) -Mode 확장: Path(드라이브+UNC/NAS) / Ip / Domain(도메인·서버명) / Port
#     (3) -Depth — 경로를 뿌리 아래 N세그먼트로 잘라서 중복 제거
#         (d:/eos/upload/img/2024 -> d:/eos/upload) 기본 2
#     (4) 비고 열에 검출 건수를 넣는다 (Replace 매핑표 형식은 그대로 유지)
#
# ── 사용법 ──────────────────────────────────────────────────────────
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Path
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Ip
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Domain
#   .\Extract-MappingDraft.ps1 -Report .\report\portal_asis_path_report.dat -Mode Port
#   .\Extract-MappingDraft.ps1 -Report ... -Mode Path -Depth 3 -ConsoleOnly
#
# ── 중요 ────────────────────────────────────────────────────────────
#   이건 '초안'이다. New 열은 비어 있으므로 사람이 채워야 한다.
#   - 경로: 긴 경로가 자동 우선 적용되므로 상위/하위 경로가 같이 나와도 둘 다 남겨도 된다
#   - IP  : 127.0.0.1 / 0.0.0.0 / 버전번호(1.2.3.4) 등은 자동 제외되지 않는다. 눈으로 걸러낼 것
#   - Domain/Port: 전용 치환 스크립트가 아직 없다 — 인벤토리(체크리스트) 용도다.
#                  포트는 Replace-AsisIp 의 OldPort/NewPort + -UsePort 로 처리하고,
#                  도메인은 hosts·WAS 설정·방화벽 확인(IP치환 가이드 6단계)으로 처리한다
# ===========================================================================

param(
    [Parameter(Mandatory=$true)][string]$Report,
    [ValidateSet("Path","Ip","Domain","Port")]
    [string]$Mode = "Path",
    [int]$Depth = 2,                     # 경로를 뿌리(d: / \\nas) 아래 N세그먼트로 절단. 0 = 자르지 않음
    [string]$Out,                        # 미지정 시 리포트 옆 report\<소스명>_mapping_draft_<mode>.dat
    [string]$Delimiter = ",",            # Find 리포트는 Export-Csv 기본(쉼표)
    [switch]$ConsoleOnly
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

if (-not (Test-Path $Report)) { Write-Error "리포트 파일 없음: $Report"; exit 1 }

# FoundIn=FILE 만 대상 — CLASS/JAR/WAR는 재빌드·재패키징으로 해소되므로 매핑표 재료가 아니다
$all  = @(Import-Csv -Path $Report -Delimiter $Delimiter)
if ($all.Count -eq 0) { Write-Error "리포트가 비어 있음: $Report"; exit 1 }
$rows = @($all | Where-Object { $_.FoundIn -eq 'FILE' })
if ($rows.Count -eq 0) {
    Write-Warning "FoundIn=FILE 행이 없음. 리포트가 Find-AsisPath 산출물이 맞는지, 구분자가 '$Delimiter'인지 확인할 것"
    exit 1
}
$cols = $all[0].PSObject.Properties.Name
$hasKind = ($cols -contains 'Kind') -and ($cols -contains 'Value')

# Mode -> (Find v9 Kind 목록, 헤더, 파일접미사)
switch ($Mode) {
    "Path"   { $kinds = @("path","unc");    $header = "OldPath,NewPath,비고"; $suffix = "path" }
    "Ip"     { $kinds = @("ip");            $header = "업무코드,업무명,서버명,호스트명,OldIP,NewIP,OldPort,NewPort"; $suffix = "ip" }
    "Domain" { $kinds = @("domain","host"); $header = "OldDomain,NewDomain,비고"; $suffix = "domain" }
    "Port"   { $kinds = @("port");          $header = "Port,용도,비고"; $suffix = "port" }
}

# v8.2 리포트(Kind 없음) 폴백용 — Match(줄 전체)에서 재추출
$SEGF = '[^\s"''<>|*?:,;=(){}\[\]\\/]'
$fallbackRx = @{
    "Path"   = '(?<![A-Za-z0-9])[A-Za-z]:(?:(?:\\{1,2}|/)' + $SEGF + '*)+' +
               '|(?<![\w:])\\{2,4}[A-Za-z0-9][\w.\-]*(?:(?:\\{1,2}|/)' + $SEGF + '*)*' +
               '|(?<![\w:/])//[A-Za-z0-9][\w.\-]*(?:/' + $SEGF + '*)+'
    "Ip"     = '(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'
    "Domain" = '(?<![\w.\-])(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+(?:co\.kr|go\.kr|or\.kr|kr|com|net|org|local)(?!\.?[A-Za-z0-9])'
    "Port"   = '[A-Za-z0-9_.\-]{0,20}port\s*[=:]\s*\d{1,5}(?!\d)'
}

# ---------- 값 정규화 ----------
# 경로: 구분자 / 통일 + 소문자 (UNC는 선두 // 보존), -Depth 로 절단
# 매핑표는 / 표기로 적어도 된다 — Replace 가 / \ \\ 전부 매칭한다
function Get-NormalizedPath([string]$v, [int]$depth) {
    if (-not $v) { return $null }
    $isUnc = $v -match '^[\\/]{2,}'
    $c = (($v -replace '[\\/]+','/').TrimEnd('/')).ToLower()
    $segs = @($c.TrimStart('/').Split('/') | Where-Object { $_ })
    if ($segs.Count -eq 0) { return $null }
    if ($isUnc) {
        if ($depth -gt 0 -and $segs.Count -gt ($depth + 1)) { $segs = $segs[0..$depth] }
        return '//' + ($segs -join '/')
    }
    if ($depth -gt 0 -and $segs.Count -gt ($depth + 1)) { $segs = $segs[0..$depth] }
    if ($segs.Count -lt 2) { return $null }   # 드라이브 루트만 남은 건 매핑 재료가 아니다
    return ($segs -join '/')
}

function Get-NormalizedPort([string]$v) {
    $m = [regex]::Match($v, '(\d{1,5})\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# ---------- 값 수집 ----------
$counts = @{}
function Add-Value([string]$v) {
    if (-not $v) { return }
    if ($counts.ContainsKey($v)) { $counts[$v] = $counts[$v] + 1 } else { $counts[$v] = 1 }
}

if ($hasKind) {
    foreach ($r in $rows) {
        if ($kinds -notcontains $r.Kind) { continue }
        switch ($Mode) {
            "Path"   { Add-Value (Get-NormalizedPath $r.Value $Depth) }
            "Ip"     { Add-Value $r.Value }
            "Domain" { Add-Value $r.Value.ToLower() }
            "Port"   { Add-Value (Get-NormalizedPort $r.Value) }
        }
    }
} else {
    Write-Warning "리포트에 Kind/Value 컬럼이 없다 (v8.2 이하 리포트) — Match 열 재추출 방식으로 폴백"
    $rx = $fallbackRx[$Mode]
    foreach ($r in $rows) {
        foreach ($m in [regex]::Matches($r.Match, $rx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            switch ($Mode) {
                "Path"   { Add-Value (Get-NormalizedPath $m.Value $Depth) }
                "Ip"     { Add-Value $m.Value }
                "Domain" { Add-Value $m.Value.ToLower() }
                "Port"   { Add-Value (Get-NormalizedPort $m.Value) }
            }
        }
    }
}

$values = @($counts.Keys | Sort-Object)
if ($values.Count -eq 0) {
    Write-Warning "추출된 값이 없음 (Mode=$Mode). Find 실행 시 -Kind 에 $($kinds -join ',') 가 포함됐는지 확인할 것"
    exit 1
}

Write-Host "===== Extract-MappingDraft v2 (Mode=$Mode) ====="
Write-Host "리포트   : $Report (FILE $($rows.Count)행, Kind컬럼=$hasKind)"
$depthNote = ''
if ($Mode -eq 'Path' -and $Depth -gt 0) { $depthNote = ', Depth=' + $Depth }
Write-Host "추출 결과: $($values.Count)건 (중복 제거 후)$depthNote"
Write-Host ""
$values | Sort-Object { -($counts[$_]) } | ForEach-Object { Write-Host ("  {0,5}건  {1}" -f $counts[$_], $_) }

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
switch ($Mode) {
    "Path"   { $lines.Add("# 드라이브 경로와 UNC(\\서버\공유)를 한 파일에 섞어도 된다 (Replace-AsisPath v4 이상)")
               $lines.Add("# 드라이브 <-> UNC 교차 매핑 가능. 예) w:/data,\\nas01\data") }
    "Ip"     { $lines.Add("# 127.0.0.1 / 0.0.0.0 / 버전번호 등 치환 대상이 아닌 값이 섞여 있다 — 반드시 선별할 것") }
    "Domain" { $lines.Add("# 전용 치환 스크립트는 아직 없다 — 인벤토리/체크리스트 용도 (hosts·WAS 설정·방화벽 확인)") }
    "Port"   { $lines.Add("# 포트 치환은 Replace-AsisIp 의 OldPort/NewPort + -UsePort 로 처리한다") }
}
# Path 초안은 Replace 매핑표(헤더 없는 형식)로 바로 들어가므로 헤더를 주석으로 낸다
if ($Mode -eq "Path") { $lines.Add("# " + $header) } else { $lines.Add($header) }
foreach ($v in $values) {
    $c = $counts[$v]
    switch ($Mode) {
        "Path"   { $lines.Add("$v,,검출 ${c}건") }
        "Ip"     { $lines.Add(",,,,$v,,,") }
        "Domain" { $lines.Add("$v,,검출 ${c}건") }
        "Port"   { $lines.Add("$v,,검출 ${c}건") }
    }
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($Out, $lines, $utf8Bom)

Write-Host ""
Write-Host "-> $Out"
switch ($Mode) {
    "Path"   { Write-Host "다음 단계 : NewPath 열을 채운 뒤 Replace-AsisPath.ps1 -Map 으로 DryRun" }
    "Ip"     { Write-Host "다음 단계 : NewIP 열을 채운 뒤 Replace-AsisIp.ps1 -Map 으로 DryRun" }
    default  { Write-Host "다음 단계 : 인벤토리 검토 (치환 대상/비대상 판정)" }
}
