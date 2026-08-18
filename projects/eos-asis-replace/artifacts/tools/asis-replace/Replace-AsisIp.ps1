# ===========================================================================
# [표준 헤더] Replace-AsisIp.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-4  IP 치환
#   역할 : 매핑표 기반 AS-IS IP -> TO-BE IP 치환. -UsePort로 IP:포트 규칙 우선
#   입력 : -Root + -Map (또는 -RootList roots.dat + 공통 -Map)
#   출력 : report\<소스명>_asis_ip_replace_report.dat + <소스명>_backup_ip_<시각>\
#   선행 : IP 매핑표 작성 완료. 경로 치환(A-3) 이후 권장
#   상태 : 현행 v5
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Replace-AsisIp.ps1 (v5)
# 매핑표 기반 AS-IS IP -> TO-BE IP 일괄 치환 (Replace-AsisPath v3와 구조·규칙 통일)
# - DryRun 기본, -Apply 시에만 실제 치환 + 자동 백업 (소스 옆 <이름>_backup_ip_시각)
# - 바이트 단위 인코딩 보존 (Latin-1 라운드트립 — EUC-KR/UTF-8 한글 훼손 없음, IP는 ASCII)
# - 매핑에 없는 IP는 UNMAPPED로 리포트 (매핑표 보강용, NewIP·IgnoreIps는 제외)
# - -UsePort: "IP:포트" 단위 치환 규칙을 IP 단독 규칙보다 우선 적용
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v4: 최초 커밋 후보 (규칙 순차 [regex]::Replace, csv 리포트)
# v5: Replace-AsisPath v2/v3에서 잡은 버그·규칙을 동일 적용
#     (1) 치환을 규칙별 순차 Replace -> 단일 결합 정규식 + 매치 오프셋 재조립으로
#         · v4는 A의 NewIP가 B의 OldIP와 겹치면 연쇄 치환되는 위험 (IP 맞교환 시 사고)
#         · 리포트와 실치환 100% 일치 보장 (PS 5.1 delegate 미사용 — 원래도 안전했음)
#     (2) Out 기본 report\ + 출력 폴더 자동 생성 (v4는 폴더 없으면 리포트 유실)
#     (3) 폴더 제외 정규식 [\\/] 중립화 + 백업 폴더(*_backup_path_*, *_backup_ip_*) 자동 제외
#         · 백업 폴더명을 <소스명>_backup_ip_<시각>으로 변경 (Find v8.2/Replace v3 자동제외와 통일.
#           v4의 _ip_backup_* 이름은 자동제외에 안 걸려 상위 재조사 시 이중 검출됐음)
#     (4) 기본 리포트명에 소스명 접두 (report\<소스명>_asis_ip_replace_report.dat) — 덮어쓰기 방지
#     (5) -RootList 일괄 모드 — IP 매핑은 전 소스 공통이므로 Find와 같은 roots.dat(한 줄 한 경로) + 공통 -Map
#     (6) UNMAPPED IP 탐지 / Apply 정합성 경고 / Copy-Item -LiteralPath / 리포트 .dat (DRM)
#
# 매핑표 컬럼(콤마, # 주석): 업무코드,업무명,서버명,호스트명,OldIP,NewIP,OldPort,NewPort
#   - OldPort/NewPort는 비워도 됨. -UsePort 지정 시에만 "IP:포트" 규칙 생성
#   - 파일 확장자는 .dat 권장 (회사 DRM csv 자동 암호화 회피). UTF-8 BOM 저장
#
# 예) 단일 DryRun:  .\Replace-AsisIp.ps1 -Root "D:\src\portal" -Map ip_mapping.dat
# 예) 단일 적용  :  .\Replace-AsisIp.ps1 -Root "D:\src\portal" -Map ip_mapping.dat -Apply
# 예) 일괄 DryRun:  .\Replace-AsisIp.ps1 -RootList roots.dat -Map ip_mapping.dat
# 예) 포트 포함  :  .\Replace-AsisIp.ps1 -Root ... -Map ip_mapping.dat -UsePort -Apply

param(
    [string]$Root = "C:\pgms",
    [string]$Map  = "ip_mapping.dat",
    [string]$RootList = "",              # 일괄 목록 파일 (한 줄에 소스 경로 하나, # 주석). 지정 시 -Root 무시
    [switch]$Apply,
    [switch]$UsePort,
    [string]$Out  = "report\asis_ip_replace_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","target","bin","build","classes","dist"),
    [string[]]$ExcludeFiles = @(),          # 예: @("*Test.java","sample*.xml")
    [string]$ExcludeList = "",              # 제외할 파일 경로/패턴 목록 파일 (한 줄에 하나)
    [string[]]$IgnoreIps = @("127.0.0.1","0.0.0.0","255.255.255.255")  # UNMAPPED에서 제외할 상용구 IP
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml")

# ---------- 내장 매핑표 (DRM 등으로 파일 반입이 어려울 때 -Map "" 로 실행하고 여기를 직접 편집) ----------
$InlineMap = @"
업무코드,업무명,서버명,호스트명,OldIP,NewIP,OldPort,NewPort
EOS01,포털,WDAAD11,asis-web01,192.168.1.10,10.20.1.10,8080,9090
EOS02,리포팅,WDDIM11,asis-was01,192.168.1.11,10.20.1.11,,
"@

# ---------- 공통 준비 ----------
$excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if ($ExcludeList) {
    if (-not (Test-Path $ExcludeList)) { Write-Error "제외 목록 파일 없음: $ExcludeList"; exit 1 }
    Get-Content $ExcludeList | ForEach-Object {
        $l = $_.Trim(); if ($l -and -not $l.StartsWith("#")) { $ExcludeFiles += $l }
    }
}

$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Get-RelPath([string]$path) {
    if ($path.StartsWith($script:RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($script:RootFull.Length).TrimStart('\')
    }
    return $path
}

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/][^\\/]*_backup_(path|ip)_') { return $true }   # 치환 백업 폴더 자동 제외
    $leaf = Split-Path $path -Leaf
    $rel  = Get-RelPath $path
    foreach ($pat in $ExcludeFiles) {
        $pp = $pat -replace '/','\'
        if ($leaf -like $pp) { return $true }             # 파일명: *Test.java
        if ($rel -like $pp) { return $true }              # 상대경로 정확
        if ($rel -like ("*\" + $pp)) { return $true }     # 하위경로
    }
    return $false
}

function Test-ValidIp([string]$ip) {
    if ($ip -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { return $false }
    foreach ($o in $ip.Split('.')) { if ([int]$o -gt 255) { return $false } }
    return $true
}

# ---------- 매핑 로드 + 치환 규칙(단일 결합 정규식) 구성 ----------
function Import-IpMapping([string]$mapPath) {
    $mapping = $null
    if ($mapPath) {
        if (-not (Test-Path $mapPath)) { Write-Error "매핑표 파일 없음: $mapPath (현재 폴더: $PWD)"; return $false }
        foreach ($enc in @("Default","UTF8")) {
            try {
                $m = Import-Csv -Path $mapPath -Encoding $enc
                if ($m -and ($m[0].PSObject.Properties.Name -contains "OldIP")) { $mapping = $m; break }
            } catch {}
        }
        if (-not $mapping) { Write-Error "매핑표를 읽을 수 없거나 OldIP 컬럼이 없음: $mapPath"; return $false }
    } else {
        Write-Host "(-Map 미지정: 스크립트 내장 매핑표 사용)"
        $mapping = ($InlineMap -split "`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") }) | ConvertFrom-Csv
    }

    # 유효성: OldIP/NewIP 필수·형식, OldIP 중복 금지, Old=New 경고
    foreach ($row in $mapping) {
        if (-not $row.OldIP -or -not $row.NewIP) { Write-Error "OldIP/NewIP가 비어있는 행이 있음 ($mapPath)"; return $false }
        if (-not (Test-ValidIp $row.OldIP.Trim())) { Write-Error "OldIP 형식 오류: '$($row.OldIP)' ($mapPath)"; return $false }
        if (-not (Test-ValidIp $row.NewIP.Trim())) { Write-Error "NewIP 형식 오류: '$($row.NewIP)' ($mapPath)"; return $false }
    }
    $dup = $mapping | Group-Object { $_.OldIP.Trim() } | Where-Object Count -gt 1
    if ($dup) { Write-Error ("OldIP 중복: " + (($dup | ForEach-Object Name) -join ", ")); return $false }
    $same = $mapping | Where-Object { $_.OldIP.Trim() -eq $_.NewIP.Trim() }
    if ($same) { Write-Warning ("Old=New 동일 행 {0}건은 건너뜀" -f @($same).Count)
                 $mapping = $mapping | Where-Object { $_.OldIP.Trim() -ne $_.NewIP.Trim() } }
    if (-not $mapping -or @($mapping).Count -eq 0) { Write-Error "유효한 매핑이 없음: $mapPath"; return $false }
    if ($UsePort) {
        $noPort = $mapping | Where-Object { -not $_.OldPort -or -not $_.NewPort }
        if ($noPort) { Write-Warning ("-UsePort 지정됐지만 포트가 비어있는 행 {0}건은 IP만 치환" -f @($noPort).Count) }
    }
    # 스왑/체인 매핑 감지: 어떤 행의 NewIP가 다른 행의 OldIP와 같으면
    # 치환 자체는 단일 패스라 안전하지만, 재DryRun이 그 값을 다시 REPLACE로 잡아 0건 검증이 불가
    $oldSetChk = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($row in $mapping) { [void]$oldSetChk.Add($row.OldIP.Trim()) }
    foreach ($row in $mapping) {
        if ($oldSetChk.Contains($row.NewIP.Trim())) {
            Write-Warning "NewIP '$($row.NewIP.Trim())'가 다른 행의 OldIP와 동일 (스왑/체인 매핑) — 치환은 1패스로 안전하나 재DryRun 0건 검증 불가, 리포트로 판정할 것"
        }
    }
    $script:Mapping = $mapping

    # 규칙: key = 매치 문자열 정규화("ip" 또는 "ip:port") -> New/Row
    # 결합 정규식은 포트 규칙(긴 매치)을 IP 단독 규칙보다 앞에 배치 — 대안 순서가 우선순위
    $script:RuleTable = @{}
    $alts = New-Object System.Collections.Generic.List[string]
    foreach ($row in $mapping) {
        $oldIp = $row.OldIP.Trim()
        $oldEsc = [regex]::Escape($oldIp)
        if ($UsePort -and $row.OldPort -and $row.NewPort) {
            $key = $oldIp + ":" + $row.OldPort.Trim()
            $script:RuleTable[$key] = @{ New = ($row.NewIP.Trim() + ":" + $row.NewPort.Trim()); Row = $row }
            $alts.Add($oldEsc + "\s*:\s*" + [regex]::Escape($row.OldPort.Trim()) + "(?!\d)")
        }
    }
    foreach ($row in $mapping) {
        $oldIp = $row.OldIP.Trim()
        $script:RuleTable[$oldIp] = @{ New = $row.NewIP.Trim(); Row = $row }
        $alts.Add([regex]::Escape($oldIp) + "(?![\d.])")
    }
    # 앞 경계: 숫자/점 아님 (192.168.1.1이 192.168.1.10 내부에 매칭되는 것 방지)
    $pattern = "(?<![\d.])(?:" + ($alts -join "|") + ")"
    $script:rx = New-Object System.Text.RegularExpressions.Regex($pattern)

    # TO-BE(NewIP) 인식 — 치환 완료 IP가 UNMAPPED로 오보되지 않게
    $newSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($row in $mapping) { [void]$newSet.Add($row.NewIP.Trim()) }
    foreach ($ig in $IgnoreIps) { [void]$newSet.Add($ig.Trim()) }
    $script:NewIpSet = $newSet
    return $true
}

function Get-MatchKey([string]$val) {   # "ip : port" 표기 흔들림 정규화
    return ($val -replace '\s*:\s*', ':')
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
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$ipDetect = '(?<![\d.])\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![\d.])'

function Invoke-ReplaceIp([string]$scanRoot, [string]$mapLabel, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $results = New-Object System.Collections.Generic.List[object]
    $changedFiles = 0; $replacedCount = 0; $unmappedCount = 0

    $backupRoot = $null
    if ($Apply) {
        $rootName = Split-Path $script:RootFull -Leaf
        $parent = Split-Path $script:RootFull -Parent
        $backupRoot = Join-Path $parent ($rootName + "_backup_ip_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
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
            $key = Get-MatchKey $m.Value
            $rule = $script:RuleTable[$key]
            $newVal = if ($rule) { $rule.New } else { $null }
            $row = if ($rule) { $rule.Row } else { $null }
            $results.Add([pscustomobject]@{
                Status   = "REPLACE"
                File     = $file
                RelPath  = (Split-Path (Get-RelPath $file) -Parent)
                Ext      = ([System.IO.Path]::GetExtension($file)).TrimStart('.').ToLower()
                Line     = Get-LineNumber $content $m.Index
                Old      = $m.Value
                New      = $newVal
                업무코드 = if ($row) { $row.업무코드 } else { "" }
                업무명   = if ($row) { $row.업무명 } else { "" }
                서버명   = if ($row) { $row.서버명 } else { "" }
                호스트명 = if ($row) { $row.호스트명 } else { "" }
                Context  = Get-Context $content $m.Index
            })
            $replacedCount++
        }

        # 매핑에 안 걸린 IP -> UNMAPPED (매핑표 보강 신호. NewIP·IgnoreIps·비유효 IP는 제외)
        foreach ($g in [regex]::Matches($content, $ipDetect)) {
            if (-not (Test-ValidIp $g.Value)) { continue }
            if ($script:NewIpSet.Contains($g.Value)) { continue }
            $covered = $false
            foreach ($mm in $matches_) {
                if ($g.Index -ge $mm.Index -and $g.Index -lt ($mm.Index + $mm.Length)) { $covered = $true; break }
            }
            if (-not $covered) {
                $results.Add([pscustomobject]@{
                    Status   = "UNMAPPED"
                    File     = $file
                    RelPath  = (Split-Path (Get-RelPath $file) -Parent)
                    Ext      = ([System.IO.Path]::GetExtension($file)).TrimStart('.').ToLower()
                    Line     = Get-LineNumber $content $g.Index
                    Old      = $g.Value
                    New      = ""
                    업무코드 = ""
                    업무명   = ""
                    서버명   = ""
                    호스트명 = ""
                    Context  = Get-Context $content $g.Index
                })
                $unmappedCount++
            }
        }

        # 실제 치환 — 매치 오프셋으로 직접 재조립 (연쇄 치환 방지, 리포트와 100% 일치)
        if ($Apply -and $matches_.Count -gt 0) {
            $sb = New-Object System.Text.StringBuilder
            $pos = 0
            foreach ($m in $matches_) {
                [void]$sb.Append($content.Substring($pos, $m.Index - $pos))
                $rule = $script:RuleTable[(Get-MatchKey $m.Value)]
                if ($rule) { [void]$sb.Append($rule.New) } else { [void]$sb.Append($m.Value) }
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

    # 리포트 (출력 폴더 자동 생성, .dat — 회사 DRM csv 자동 암호화 회피)
    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $results | Sort-Object Status, File, Line |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot]"
    Write-Host "  매핑      : $mapLabel ($(@($script:Mapping).Count)행)"
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
        Write-Host "  == IP별 치환 건수 =="
        $results | Where-Object { $_.Status -eq "REPLACE" } | Group-Object Old | Sort-Object Count -Descending |
          ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
        Write-Host "  == 업무별 건수 =="
        $results | Where-Object { $_.Status -eq "REPLACE" -and $_.업무명 } | Group-Object 업무명 | Sort-Object Count -Descending |
          ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    }

    return [pscustomobject]@{
        Replaced = $replacedCount; Unmapped = $unmappedCount
        Changed = $changedFiles; Backup = $backupRoot; Report = $outFile
    }
}

# ---------- 실행 ----------
$mode = if ($Apply) { "APPLY(치환 실행)" } else { "DryRun(검토 전용)" }
Write-Host "===== Replace-AsisIp v5 ====="
Write-Host "모드: $mode / UsePort: $(if ($UsePort) {'ON (IP:포트 규칙 우선)'} else {'OFF (IP 단독만)'})"

if (-not (Import-IpMapping $Map)) { exit 1 }

if ($RootList) {
    # ── 일괄 모드: IP 매핑은 전 소스 공통 -> roots.dat(한 줄 한 경로) + 공통 -Map ──
    if (-not (Test-Path $RootList)) { Write-Error "목록 파일 없음: $RootList"; exit 1 }
    $roots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -and -not $_.StartsWith("#") }
    if (-not $roots) { Write-Error "목록이 비어 있음: $RootList"; exit 1 }

    # 사전 전체 검증 — Apply 도중 중단으로 일부만 치환되는 사고 방지
    $valid = $true
    $lineNo = 0
    foreach ($r in $roots) {
        $lineNo++
        if (-not (Test-Path $r)) { Write-Error "목록 ${lineNo}행: 소스 없음 -> $r"; $valid = $false }
    }
    if (-not $valid) { Write-Error "사전 검증 실패 — 아무 소스도 처리하지 않음. 목록 수정 후 재실행"; exit 1 }

    $outDir  = Split-Path $Out -Parent
    $outName = Split-Path $Out -Leaf
    $summary = New-Object System.Collections.Generic.List[object]
    $usedNames = @{}

    foreach ($r in $roots) {
        $leaf = Split-Path ((Resolve-Path $r).Path.TrimEnd('\')) -Leaf
        if ($usedNames.ContainsKey($leaf)) {
            $usedNames[$leaf]++
            $tag = "$leaf`_$($usedNames[$leaf])"
            Write-Warning "소스 폴더명 중복: '$leaf' -> 리포트는 '$tag'로 저장 ($r)"
            $leaf = $tag
        } else { $usedNames[$leaf] = 1 }
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
        $res = Invoke-ReplaceIp $r $Map $outFile
        $summary.Add([pscustomobject]@{ Source = $leaf; Replaced = $res.Replaced; Unmapped = $res.Unmapped; Changed = $res.Changed; Report = $res.Report })
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

    # 기본 파일명엔 소스명 접두 (Find v8.2/Replace v3와 규칙 통일). -Out 지정 시엔 그 이름 그대로
    $outFile = $Out
    if (-not $PSBoundParameters.ContainsKey('Out')) {
        $leaf = Split-Path ((Resolve-Path $Root).Path.TrimEnd('\')) -Leaf
        $outDir  = Split-Path $Out -Parent
        $outName = Split-Path $Out -Leaf
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
    }
    $res = Invoke-ReplaceIp $Root $Map $outFile
    if (-not $Apply) {
        Write-Host "`n다음 단계 : $($res.Report) 엑셀(텍스트 나누기) 검토 -> 제외 반영 -> -Apply"
    } else {
        Write-Host "`n다음 단계 : 같은 매핑으로 DryRun 재실행 -> REPLACE 0건 확인"
    }
    if ($res.Unmapped -gt 0) {
        Write-Host "[주의] UNMAPPED $($res.Unmapped)건 — 매핑표에 없는 IP. 리포트 확인 후 매핑 추가 여부 판단."
    }
}
