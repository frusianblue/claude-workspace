# ===========================================================================
# [표준 헤더] Replace-AsisPath.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-3  경로 치환
#   역할 : 매핑표 기반 경로 접두사 치환. DryRun 기본, -Apply 시 자동 백업
#   입력 : -Root + -Map (또는 -RootList: 소스경로,매핑파일)
#   출력 : report\<소스명>_asis_path_replace_report.dat + <소스명>_backup_path_<시각>\
#   선행 : A-2 매핑표 작성 완료. ★ 인코딩 통일(B-6)을 먼저 끝낼 것
#   상태 : 현행 v3
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Replace-AsisPath.ps1 (v3)
# AS-IS 하드코딩 경로 접두사 치환 (매핑표 기반, 소스별 매핑 파일 운용)
# - DryRun 기본, -Apply 시에만 실제 치환 + 자동 백업 (소스 옆 <이름>_backup_path_시각)
# - 구분자 스타일 보존: d:/a, d:\a, d:\\a (java 리터럴) 각각 원본 스타일 유지
# - 드라이브 문자 대소문자 보존 / 바이트 단위 인코딩 보존 (EUC-KR/UTF-8 원본 그대로, BOM 유지)
# - 매핑에 없는 d:/ 경로는 UNMAPPED로 리포트 (매핑표 보강용)
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v1: 최초 (매핑표, DryRun/Apply, 스타일·인코딩 보존, UNMAPPED)
# v2: (1) Apply 치환을 delegate 대신 매치 오프셋 재조립으로 — PS 5.1에서 delegate가
#         조용히 실패해 "치환 대상 N건인데 변경 0개·백업 없음"이 되던 문제 해결
#     (2) Out 기본값 report\ + 출력 폴더 자동 생성 (v1은 폴더 없으면 리포트 유실)
#     (3) 백업 폴더 자동제외 정규식 수정 (<이름>_backup_path_* 형태 인식)
#     (4) Apply 정합성 경고 / Copy-Item -LiteralPath / 드라이브 루트 통짜 매핑 가드
# v3: (1) -RootList 일괄 모드 — 목록 파일 형식: 소스경로,매핑파일[,비고]
#         (소스마다 매핑이 다르므로 매핑파일 명시 필수. 시작 전 전체 사전 검증 후 처리)
#     (2) 리포트명 규칙 Find v8.2와 통일 — 기본 report\<소스명>_asis_path_replace_report.dat
#         (단일 모드에서 -Out 지정 시엔 그 이름 그대로, 일괄 모드는 항상 소스명 접두)
#
# 예) 단일 DryRun:  .\Replace-AsisPath.ps1 -Root "D:\src\portal" -Map path_mapping_portal.dat
# 예) 단일 적용  :  .\Replace-AsisPath.ps1 -Root "D:\src\portal" -Map path_mapping_portal.dat -Apply
# 예) 일괄 DryRun:  .\Replace-AsisPath.ps1 -RootList replace_targets.dat
# 예) 일괄 적용  :  .\Replace-AsisPath.ps1 -RootList replace_targets.dat -Apply
#
# replace_targets.dat 형식 (한 줄에 하나, # 주석):
#   D:\AppDev\workspace-egov\portal,D:\작업\path_mapping_portal.dat
#   D:\AppDev\workspace-egov\admin,D:\작업\path_mapping_admin.dat,비고 가능

param(
    [string]$Root = "C:\pgms",
    [string]$Map  = "path_mapping.dat",
    [string]$RootList = "",              # 일괄 목록 파일 (소스경로,매핑파일). 지정 시 -Root/-Map 무시
    [string]$Out  = "report\asis_path_replace_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","target","bin","build","classes","dist"),
    [string[]]$ExcludeFiles = @(),          # 예: @("*.min.js","legacy_backup.xml")
    [string]$ExcludeList = "",              # 제외할 파일 경로 목록 파일 (한 줄에 하나)
    [string]$DetectPattern = "(?<![a-zA-Z0-9])[dD]:[/\\]",  # UNMAPPED 탐지용 (Find와 동일)
    [switch]$Apply
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml")

# ---------- 공통 준비 ----------
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
    if ($path -match '[\\/][^\\/]*_backup_(path|ip)_') { return $true }   # <이름>_backup_path_* 자동 제외
    $rel = Get-RelPath $path
    if ($excludeSet.Contains($path) -or $excludeSet.Contains($rel)) { return $true }
    foreach ($pat in $ExcludeFiles) {
        if ((Split-Path $path -Leaf) -like $pat) { return $true }
    }
    return $false
}

function Get-RelPath([string]$path) {
    if ($path.StartsWith($script:RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($script:RootFull.Length).TrimStart('\')
    }
    return $path
}

function Get-Canon([string]$p) { return (($p -replace '[\\/]+','/').TrimEnd('/')).ToLower() }

# ---------- 매핑 로드 (검증 실패 시 $false 반환 — 일괄 모드 사전 검증용) ----------
# 형식(콤마 구분, # 주석): OldPath,NewPath[,비고]
function Import-PathMapping([string]$mapPath) {
    $script:MapTable = @{}
    $mapOrder = New-Object System.Collections.Generic.List[string]
    $lineNo = 0
    foreach ($raw in (Get-Content $mapPath)) {
        $lineNo++
        $l = $raw.Trim()
        if (-not $l -or $l.StartsWith("#")) { continue }
        $cols = $l.Split(",")
        if ($cols.Count -lt 2) { Write-Error "[$mapPath] ${lineNo}행: 컬럼 부족 -> $l"; return $false }
        $old = $cols[0].Trim(); $new = $cols[1].Trim()
        if ($old -notmatch '^[a-zA-Z]:[/\\]') { Write-Error "[$mapPath] ${lineNo}행: OldPath는 드라이브 경로여야 함 -> $old"; return $false }
        if ($new -notmatch '^[a-zA-Z]:[/\\]') { Write-Error "[$mapPath] ${lineNo}행: NewPath는 드라이브 경로여야 함 -> $new"; return $false }
        $oldC = Get-Canon $old
        $newC = ($new -replace '[\\/]+','/').TrimEnd('/')
        if ($script:MapTable.ContainsKey($oldC)) { Write-Error "[$mapPath] ${lineNo}행: OldPath 중복 -> $old"; return $false }
        if ($oldC -eq (Get-Canon $newC)) { Write-Warning "[$mapPath] ${lineNo}행: Old=New 동일, 건너뜀 -> $old"; continue }
        if (($oldC.Split('/')).Count -lt 2 -or ($newC.Split('/')).Count -lt 2) {
            Write-Error "[$mapPath] ${lineNo}행: 드라이브 루트 통짜 매핑 불가 (드라이브 아래 최소 1세그먼트 필요) -> $l"; return $false }
        if ($oldC[0] -ne $newC.ToLower()[0]) { Write-Warning "[$mapPath] ${lineNo}행: 드라이브 문자가 다름 (의도 확인) -> $old -> $new" }
        $script:MapTable[$oldC] = $newC
        $mapOrder.Add($oldC)
    }
    if ($script:MapTable.Count -eq 0) { Write-Error "유효한 매핑이 없음: $mapPath"; return $false }

    # 긴 경로 우선 (d:/eos/upload가 d:/eos보다 먼저 매칭되도록)
    $sorted = $mapOrder | Sort-Object { $_.Length } -Descending

    # 구분자: / 또는 \ 또는 \\ (java 문자열 리터럴) 어느 것이든 매칭
    $sep = '(?:\\\\|\\|/)'
    $alts = foreach ($oldC in $sorted) {
        $segs = $oldC.Split('/')
        $dl = $segs[0][0]
        $body = ($segs[1..($segs.Count-1)] | ForEach-Object { [regex]::Escape($_) }) -join $sep
        "[" + [char]::ToLower($dl) + [char]::ToUpper($dl) + "]:" + $sep + $body
    }
    # 앞: 영숫자 아님(forward:/ 오탐 방지) / 뒤: 단어문자·점·하이픈 아님(d:/eos가 d:/eosdata 매칭 방지)
    $pattern = "(?<![a-zA-Z0-9])(?:" + ($alts -join "|") + ")(?![\w.\-])"
    $script:rx = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # TO-BE(NewPath) 인식 — 치환 완료 경로가 UNMAPPED로 오보되지 않게
    $newAlts = foreach ($newC in ($script:MapTable.Values | Select-Object -Unique | Sort-Object Length -Descending)) {
        $segs = $newC.Split('/')
        $dl = $segs[0][0]
        $body = ($segs[1..($segs.Count-1)] | ForEach-Object { [regex]::Escape($_) }) -join $sep
        "[" + [char]::ToLower($dl) + [char]::ToUpper($dl) + "]:" + $sep + $body
    }
    $script:rxNew = New-Object System.Text.RegularExpressions.Regex(
        ("(?<![a-zA-Z0-9])(?:" + ($newAlts -join "|") + ")"),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $true
}

# ---------- 치환값 생성 (구분자 스타일·드라이브 대소문자 보존) ----------
function Get-Replacement([string]$orig) {
    $canon = Get-Canon $orig
    $new = $script:MapTable[$canon]
    if (-not $new) { return $null }
    if     ($orig -match '\\\\') { $style = '\\' }
    elseif ($orig -match '\\')   { $style = '\'  }
    else                         { $style = '/'  }
    $styled = $new.Replace('/', $style)
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

# ---------- 소스 1건 처리 ----------
# Latin-1(28591)은 바이트<->문자 1:1 라운드트립 — 경로는 ASCII이므로
# EUC-KR/UTF-8 한글 바이트를 건드리지 않고 원본 인코딩 그대로 보존됨
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Invoke-Replace([string]$scanRoot, [string]$mapLabel, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $results = New-Object System.Collections.Generic.List[object]
    $changedFiles = 0; $replacedCount = 0; $unmappedCount = 0

    $backupRoot = $null
    if ($Apply) {
        $rootName = Split-Path $script:RootFull -Leaf
        $parent = Split-Path $script:RootFull -Parent
        $backupRoot = Join-Path $parent ($rootName + "_backup_path_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    }

    Get-ChildItem -Path $scanRoot -Recurse -File -Include $textExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      ForEach-Object {
        $file = $_.FullName
        $bytes = [System.IO.File]::ReadAllBytes($file)
        if ($bytes.Length -eq 0) { return }
        $content = $latin1.GetString($bytes)

        $matches_ = $script:rx.Matches($content)

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
                foreach ($mn in $script:rxNew.Matches($content)) {
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

        # 실제 치환 — 매치 오프셋으로 직접 재조립 (PS 5.1 안전, 리포트와 100% 일치)
        if ($Apply -and $matches_.Count -gt 0) {
            $sb = New-Object System.Text.StringBuilder
            $pos = 0
            foreach ($m in $matches_) {
                [void]$sb.Append($content.Substring($pos, $m.Index - $pos))
                $r = Get-Replacement $m.Value
                if ($r) { [void]$sb.Append($r) } else { [void]$sb.Append($m.Value) }
                $pos = $m.Index + $m.Length
            }
            [void]$sb.Append($content.Substring($pos))
            $newContent = $sb.ToString()
            if ($newContent -ne $content) {
                $rel = Get-RelPath $file
                $bakPath = Join-Path $backupRoot $rel
                $bakDir = Split-Path $bakPath -Parent
                if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
                Copy-Item -LiteralPath $file -Destination $bakPath -Force
                [System.IO.File]::WriteAllBytes($file, $latin1.GetBytes($newContent))
                $changedFiles++
            }
        }
      }

    # 리포트 (출력 폴더 자동 생성)
    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $results | Sort-Object Status, File, Line |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot]"
    Write-Host "  매핑      : $mapLabel ($($script:MapTable.Count)건)"
    Write-Host "  치환 대상 : ${replacedCount}건 / UNMAPPED: ${unmappedCount}건 -> $outFile"
    if ($Apply) {
        Write-Host "  변경 파일 : ${changedFiles}개, 백업 -> $backupRoot"
        if ($replacedCount -gt 0 -and $changedFiles -eq 0) {
            Write-Warning "치환 대상이 있는데 변경 파일이 0개 — 비정상. 실행 환경 확인 필요"
        }
        if ($changedFiles -gt 0 -and -not (Test-Path $backupRoot)) {
            Write-Warning "백업 폴더가 확인되지 않음: $backupRoot"
        }
    }
    if ($replacedCount -gt 0) {
        Write-Host "  == 매핑별 치환 건수 =="
        $results | Where-Object { $_.Status -eq "REPLACE" } | Group-Object MapKey | Sort-Object Count -Descending |
          ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    }

    return [pscustomobject]@{
        Replaced = $replacedCount; Unmapped = $unmappedCount
        Changed = $changedFiles; Backup = $backupRoot; Report = $outFile
    }
}

# ---------- 실행 ----------
$mode = if ($Apply) { "APPLY(치환 실행)" } else { "DryRun(검토 전용)" }
Write-Host "===== Replace-AsisPath v3 ====="
Write-Host "모드: $mode"

if ($RootList) {
    # ── 일괄 모드: 소스경로,매핑파일 ──
    if (-not (Test-Path $RootList)) { Write-Error "목록 파일 없음: $RootList"; exit 1 }
    $entries = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    foreach ($raw in (Get-Content $RootList)) {
        $lineNo++
        $l = $raw.Trim()
        if (-not $l -or $l.StartsWith("#")) { continue }
        $cols = $l.Split(",")
        if ($cols.Count -lt 2) {
            Write-Error "목록 ${lineNo}행: '소스경로,매핑파일' 형식이어야 함 -> $l"
            Write-Host "  (Replace는 소스마다 매핑이 다르므로 매핑파일 명시 필수)"
            exit 1
        }
        $entries.Add([pscustomobject]@{ Root = $cols[0].Trim(); Map = $cols[1].Trim(); Line = $lineNo })
    }
    if ($entries.Count -eq 0) { Write-Error "목록이 비어 있음: $RootList"; exit 1 }

    # 사전 전체 검증 — Apply 도중 중단으로 일부만 치환되는 사고 방지
    $valid = $true
    foreach ($e in $entries) {
        if (-not (Test-Path $e.Root)) { Write-Error "목록 $($e.Line)행: 소스 없음 -> $($e.Root)"; $valid = $false; continue }
        if (-not (Test-Path $e.Map))  { Write-Error "목록 $($e.Line)행: 매핑 파일 없음 -> $($e.Map)"; $valid = $false; continue }
        if (-not (Import-PathMapping $e.Map)) { $valid = $false }
    }
    if (-not $valid) { Write-Error "사전 검증 실패 — 아무 소스도 처리하지 않음. 목록/매핑 수정 후 재실행"; exit 1 }

    $outDir  = Split-Path $Out -Parent
    $outName = Split-Path $Out -Leaf
    $summary = New-Object System.Collections.Generic.List[object]
    $usedNames = @{}

    foreach ($e in $entries) {
        $leaf = Split-Path ((Resolve-Path $e.Root).Path.TrimEnd('\')) -Leaf
        if ($usedNames.ContainsKey($leaf)) {
            $usedNames[$leaf]++
            $tag = "$leaf`_$($usedNames[$leaf])"
            Write-Warning "소스 폴더명 중복: '$leaf' -> 리포트는 '$tag'로 저장 ($($e.Root))"
            $leaf = $tag
        } else { $usedNames[$leaf] = 1 }
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
        [void](Import-PathMapping $e.Map)   # 소스별 매핑 재로드
        $r = Invoke-Replace $e.Root $e.Map $outFile
        $summary.Add([pscustomobject]@{ Source = $leaf; Replaced = $r.Replaced; Unmapped = $r.Unmapped; Changed = $r.Changed; Report = $r.Report })
    }

    Write-Host "`n===== 일괄 요약 ($($summary.Count)개 소스, $mode) ====="
    $summary | ForEach-Object {
        Write-Host ("  {0,-25} 치환 {1,5}건 / UNMAPPED {2,4}건 / 변경파일 {3,3}개  -> {4}" -f `
            $_.Source, $_.Replaced, $_.Unmapped, $_.Changed, $_.Report)
    }
    if (-not $Apply) { Write-Host "`n다음 단계 : 리포트 검토 -> -Apply -> 재DryRun으로 전 소스 치환 0건 확인" }
}
else {
    # ── 단일 모드 ──
    if (-not (Test-Path $Root)) { Write-Error "Root 없음: $Root"; exit 1 }
    if (-not (Test-Path $Map))  { Write-Error "매핑 파일 없음: $Map"; exit 1 }
    if (-not (Import-PathMapping $Map)) { exit 1 }

    # 기본 파일명엔 소스명 접두 (Find v8.2와 규칙 통일). -Out 지정 시엔 그 이름 그대로
    $outFile = $Out
    if (-not $PSBoundParameters.ContainsKey('Out')) {
        $leaf = Split-Path ((Resolve-Path $Root).Path.TrimEnd('\')) -Leaf
        $outDir  = Split-Path $Out -Parent
        $outName = Split-Path $Out -Leaf
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
    }
    $r = Invoke-Replace $Root $Map $outFile
    if (-not $Apply) {
        Write-Host "`n다음 단계 : $($r.Report) 엑셀(텍스트 나누기) 검토 -> 제외 반영 -> -Apply"
    } else {
        Write-Host "`n다음 단계 : 같은 매핑으로 DryRun 재실행 -> REPLACE 0건 확인"
    }
    if ($r.Unmapped -gt 0) {
        Write-Host "[주의] UNMAPPED $($r.Unmapped)건 — 매핑표에 없는 경로. 리포트 확인 후 매핑 추가 여부 판단."
    }
}
