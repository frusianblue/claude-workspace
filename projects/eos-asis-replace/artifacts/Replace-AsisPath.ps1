# Replace-AsisPath.ps1 (v1)
# AS-IS 하드코딩 경로 접두사 치환 (매핑표 기반, 소스별 매핑 파일 운용)
# - DryRun 기본, -Apply 시에만 실제 치환 + 자동 백업
# - 구분자 스타일 보존: d:/a, d:\a, d:\\a (java 리터럴) 각각 원본 스타일 유지
# - 드라이브 문자 대소문자 보존 (D:/ -> D:/, d:/ -> d:/)
# - 바이트 단위 인코딩 보존 (Latin-1 라운드트립 — EUC-KR/UTF-8 원본 그대로, BOM 유지)
# - 매핑에 없는 d:/ 경로는 UNMAPPED로 리포트 (매핑표 보강용)
# 예) DryRun:  .\Replace-AsisPath.ps1 -Root "D:\src\portal" -Map path_mapping_portal.dat -Out portal_path_dryrun.dat
# 예) 적용  :  .\Replace-AsisPath.ps1 -Root "D:\src\portal" -Map path_mapping_portal.dat -Apply

param(
    [string]$Root = "C:\pgms",
    [string]$Map  = "path_mapping.dat",
    [string]$Out  = "asis_path_replace_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","target","bin","build","classes","dist"),
    [string[]]$ExcludeFiles = @(),          # 예: @("*.min.js","legacy_backup.xml")
    [string]$ExcludeList = "",              # 제외할 파일 경로 목록 파일 (한 줄에 하나, 엑셀 검토 후 사용)
    [string]$DetectPattern = "(?<![a-zA-Z0-9])[dD]:[/\\]",  # UNMAPPED 탐지용 (Find v7과 동일)
    [switch]$Apply
)

$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml")

# ---------- 사전 검증 ----------
if (-not (Test-Path $Root)) { Write-Error "Root 없음: $Root"; exit 1 }
if (-not (Test-Path $Map))  { Write-Error "매핑 파일 없음: $Map"; exit 1 }
$RootFull = (Resolve-Path $Root).Path.TrimEnd('\')

# 제외 목록 파일 로드
$excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if ($ExcludeList -and (Test-Path $ExcludeList)) {
    Get-Content $ExcludeList | ForEach-Object {
        $l = $_.Trim(); if ($l -and -not $l.StartsWith("#")) { [void]$excludeSet.Add($l) }
    }
}

$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/]_backup_(path|ip)_') { return $true }   # 자기 백업 재검색 방지
    $rel = Get-RelPath $path
    if ($excludeSet.Contains($path) -or $excludeSet.Contains($rel)) { return $true }
    foreach ($pat in $ExcludeFiles) {
        if ((Split-Path $path -Leaf) -like $pat) { return $true }
    }
    return $false
}

function Get-RelPath([string]$path) {
    if ($path.StartsWith($RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($RootFull.Length).TrimStart('\')
    }
    return $path
}

# ---------- 매핑 로드 ----------
# 형식(콤마 구분, # 주석): OldPath,NewPath[,비고]
#   예: d:/eos/upload,d:/app/eos/upload,업로드 루트 이동
# OldPath/NewPath는 슬래시(/)든 역슬래시(\)든 무방 — 내부에서 정규화
function Get-Canon([string]$p) { return (($p -replace '[\\/]+','/').TrimEnd('/')).ToLower() }

$MapTable = @{}          # canon(old) -> new(canonical, / 구분)
$MapOrder = New-Object System.Collections.Generic.List[string]
$lineNo = 0
foreach ($raw in (Get-Content $Map)) {
    $lineNo++
    $l = $raw.Trim()
    if (-not $l -or $l.StartsWith("#")) { continue }
    $cols = $l.Split(",")
    if ($cols.Count -lt 2) { Write-Error "매핑 ${lineNo}행: 컬럼 부족 -> $l"; exit 1 }
    $old = $cols[0].Trim(); $new = $cols[1].Trim()
    if ($old -notmatch '^[a-zA-Z]:[/\\]') { Write-Error "매핑 ${lineNo}행: OldPath는 드라이브 경로여야 함 -> $old"; exit 1 }
    if ($new -notmatch '^[a-zA-Z]:[/\\]') { Write-Error "매핑 ${lineNo}행: NewPath는 드라이브 경로여야 함 -> $new"; exit 1 }
    $oldC = Get-Canon $old
    $newC = ($new -replace '[\\/]+','/').TrimEnd('/')
    if ($MapTable.ContainsKey($oldC)) { Write-Error "매핑 ${lineNo}행: OldPath 중복 -> $old"; exit 1 }
    if ($oldC -eq (Get-Canon $newC)) { Write-Warning "매핑 ${lineNo}행: Old=New 동일, 건너뜀 -> $old"; continue }
    if ($oldC[0] -ne $newC.ToLower()[0]) { Write-Warning "매핑 ${lineNo}행: 드라이브 문자가 다름 (의도 확인) -> $old -> $new" }
    $MapTable[$oldC] = $newC
    $MapOrder.Add($oldC)
}
if ($MapTable.Count -eq 0) { Write-Error "유효한 매핑이 없음: $Map"; exit 1 }

# 긴 경로 우선 (d:/eos/upload가 d:/eos보다 먼저 매칭되도록)
$sorted = $MapOrder | Sort-Object { $_.Length } -Descending

# ---------- 매칭 정규식 조립 ----------
# 구분자: / 또는 \ 또는 \\ (java 문자열 리터럴) 어느 것이든 매칭
$sep = '(?:\\\\|\\|/)'
$alts = foreach ($oldC in $sorted) {
    $segs = $oldC.Split('/')                    # [0]="d:", 이후 세그먼트
    $dl = $segs[0][0]
    $body = ($segs[1..($segs.Count-1)] | ForEach-Object { [regex]::Escape($_) }) -join $sep
    "[" + [char]::ToLower($dl) + [char]::ToUpper($dl) + "]:" + $sep + $body
}
# 앞: 영숫자 아님(forward:/ 오탐 방지, Find v7과 동일) / 뒤: 단어문자·점·하이픈 아님(d:/eos가 d:/eosdata·d:/eos.bak 매칭 방지)
$pattern = "(?<![a-zA-Z0-9])(?:" + ($alts -join "|") + ")(?![\w.\-])"
$rx = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# TO-BE(NewPath) 인식 정규식 — 치환 완료된 경로가 UNMAPPED로 오보되지 않게 (같은 드라이브 유지 시 필수)
$newAlts = foreach ($newC in ($MapTable.Values | Select-Object -Unique | Sort-Object Length -Descending)) {
    $segs = $newC.Split('/')
    $dl = $segs[0][0]
    $body = ($segs[1..($segs.Count-1)] | ForEach-Object { [regex]::Escape($_) }) -join $sep
    "[" + [char]::ToLower($dl) + [char]::ToUpper($dl) + "]:" + $sep + $body
}
$rxNew = New-Object System.Text.RegularExpressions.Regex(
    ("(?<![a-zA-Z0-9])(?:" + ($newAlts -join "|") + ")"),
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# ---------- 치환값 생성 (구분자 스타일·드라이브 대소문자 보존) ----------
function Get-Replacement([string]$orig) {
    $canon = Get-Canon $orig
    $new = $MapTable[$canon]
    if (-not $new) { return $null }
    if     ($orig -match '\\\\') { $style = '\\' }
    elseif ($orig -match '\\')   { $style = '\'  }
    else                         { $style = '/'  }
    $styled = $new.Replace('/', $style)
    # 드라이브 문자 대소문자 보존 (같은 문자일 때만)
    if ([char]::ToLower($styled[0]) -eq [char]::ToLower($orig[0])) {
        $styled = $orig[0] + $styled.Substring(1)
    }
    return $styled
}

function Get-LineNumber([string]$text, [int]$idx) {
    $n = 1
    for ($i = 0; $i -lt $idx; $i++) { if ($text[$i] -eq "`n") { $n++ } }
    return $n
}

function Get-Context([string]$text, [int]$idx) {
    $s = [Math]::Max(0, $idx - 40)
    $len = [Math]::Min(160, $text.Length - $s)
    return ($text.Substring($s, $len) -replace '[^\x20-\x7E]', '.')
}

# ---------- 본 처리 ----------
# Latin-1(28591)은 바이트<->문자 1:1 라운드트립 — 경로는 ASCII이므로
# EUC-KR/UTF-8 한글 바이트를 건드리지 않고 원본 인코딩 그대로 보존됨
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$results = New-Object System.Collections.Generic.List[object]
$changedFiles = 0; $replacedCount = 0; $unmappedCount = 0

$backupRoot = $null
if ($Apply) {
    $rootName = Split-Path $RootFull -Leaf
    $parent = Split-Path $RootFull -Parent
    $backupRoot = Join-Path $parent ($rootName + "_backup_path_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}

Get-ChildItem -Path $Root -Recurse -File -Include $textExt -ErrorAction SilentlyContinue |
  Where-Object { -not (Test-Excluded $_.FullName) } |
  ForEach-Object {
    $file = $_.FullName
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return }
    $content = $latin1.GetString($bytes)

    $matches_ = $rx.Matches($content)

    foreach ($m in $matches_) {
        $newVal = Get-Replacement $m.Value
        $results.Add([pscustomobject]@{
            Status  = "REPLACE"
            File    = $file
            RelPath = (Split-Path (Get-RelPath $file) -Parent)
            Ext     = ([System.IO.Path]::GetExtension($file)).TrimStart('.').ToLower()
            Line    = Get-LineNumber $content $m.Index
            Old     = $m.Value
            New     = $newVal
            MapKey  = (Get-Canon $m.Value)
            Context = Get-Context $content $m.Index
        })
        $replacedCount++
    }

    # 매핑에 안 걸린 d:/ 경로 -> UNMAPPED (매핑표 보강 신호)
    foreach ($g in [regex]::Matches($content, $DetectPattern)) {
        $covered = $false
        foreach ($mm in $matches_) {
            if ($g.Index -ge $mm.Index -and $g.Index -lt ($mm.Index + $mm.Length)) { $covered = $true; break }
        }
        if (-not $covered) {
            foreach ($mn in $rxNew.Matches($content)) {
                if ($g.Index -ge $mn.Index -and $g.Index -lt ($mn.Index + $mn.Length)) { $covered = $true; break }
            }
        }
        if (-not $covered) {
            $results.Add([pscustomobject]@{
                Status  = "UNMAPPED"
                File    = $file
                RelPath = (Split-Path (Get-RelPath $file) -Parent)
                Ext     = ([System.IO.Path]::GetExtension($file)).TrimStart('.').ToLower()
                Line    = Get-LineNumber $content $g.Index
                Old     = ""
                New     = ""
                MapKey  = ""
                Context = Get-Context $content $g.Index
            })
            $unmappedCount++
        }
    }

    # 실제 치환
    if ($Apply -and $matches_.Count -gt 0) {
        $newContent = $rx.Replace($content, {
            param($m)
            $r = Get-Replacement $m.Value
            if ($r) { $r } else { $m.Value }
        })
        if ($newContent -ne $content) {
            $rel = Get-RelPath $file
            $bakPath = Join-Path $backupRoot $rel
            $bakDir = Split-Path $bakPath -Parent
            if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
            Copy-Item -Path $file -Destination $bakPath -Force
            [System.IO.File]::WriteAllBytes($file, $latin1.GetBytes($newContent))
            $changedFiles++
        }
    }
  }

# ---------- 리포트 / 요약 ----------
$results | Sort-Object Status, File, Line |
  Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8

$mode = if ($Apply) { "APPLY(치환 실행)" } else { "DryRun(검토 전용)" }
Write-Host "`n===== Replace-AsisPath v1 ====="
Write-Host "모드      : $mode"
Write-Host "Root      : $RootFull"
Write-Host "매핑      : $Map ($($MapTable.Count)건)"
Write-Host "치환 대상 : ${replacedCount}건 / UNMAPPED: ${unmappedCount}건 -> $Out"
if ($Apply) {
    Write-Host "변경 파일 : ${changedFiles}개, 백업 -> $backupRoot"
    Write-Host "다음 단계 : 같은 매핑으로 DryRun 재실행 -> REPLACE 0건 확인"
} else {
    Write-Host "다음 단계 : $Out 엑셀(텍스트 나누기) 검토 -> 제외 반영 -> -Apply"
}
if ($unmappedCount -gt 0) {
    Write-Host "`n[주의] UNMAPPED ${unmappedCount}건 — 매핑표에 없는 경로. 리포트 확인 후 매핑 추가 여부 판단."
}
Write-Host "`n== 매핑별 치환 건수 =="
$results | Where-Object { $_.Status -eq "REPLACE" } | Group-Object MapKey | Sort-Object Count -Descending |
  ForEach-Object { Write-Host ("  {0,6}건  {1}" -f $_.Count, $_.Name) }
Write-Host "== 파일 확장자별 =="
$results | Where-Object { $_.Status -eq "REPLACE" } | Group-Object Ext | Sort-Object Count -Descending |
  ForEach-Object { Write-Host ("  {0,6}건  {1}" -f $_.Count, $_.Name) }
