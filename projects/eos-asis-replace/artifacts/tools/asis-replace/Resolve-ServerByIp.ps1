# ===========================================================================
# [표준 헤더] Resolve-ServerByIp.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1.5  검출 IP -> 서버/시스템/업무 역조회   (Find 이후, 매핑표 작성 이전)
#   역할 : Find-AsisPath 가 뽑은 IP가 '어느 서버의 무엇인지'를 서버이관 인덱스에서 찾는다
#          정확매칭이 없으면 같은 /24 이웃을 보여준다 (시트에 없는 IP의 소속 추정)
#   입력 : -Index mapping\server_ip_index.dat
#          + (-Ip 직접입력 | -Report Find리포트.dat | -Grep 서버명/업무명 역검색)
#   출력 : report\resolve_server_by_ip.dat
#          -EmitIpMapping 지정 시 mapping\ip_mapping_draft_resolved.dat (A-4 투입용)
#   선행 : A-1 Find 실행 완료 / 인덱스 파일 존재
#   상태 : 현행 v1
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Resolve-ServerByIp.ps1 (v1)
#
# 왜 필요한가
#   Find 리포트는 "10.10.88.164 가 3건 나왔다"까지만 말해준다.
#   그게 개발 총무지원 WEB(d1gptwb1)이고 TO-BE가 10.10.91.102 라는 건 사람이 엑셀을 열어야 안다.
#   그 엑셀이 사무실에서 DRM에 걸리므로, 엑셀을 .dat 인덱스로 한 번 떠서 이 스크립트로 조회한다.
#
# 사용법
#   # 1) IP 몇 개 직접 조회
#   .\Resolve-ServerByIp.ps1 -Ip 10.10.88.164,10.10.88.135
#
#   # 2) Find 리포트 통째로 (Kind=ip 행을 자동 추출)
#   .\Resolve-ServerByIp.ps1 -Report .\report\portal_asis_path_report.dat
#
#   # 3) 조회 결과로 A-4 매핑표 초안까지 (AS-IS -> TO-BE 자동 채움)
#   .\Resolve-ServerByIp.ps1 -Report .\report\portal_asis_path_report.dat -EmitIpMapping
#
#   # 4) 역검색 — 서버명/시스템/업무명으로 IP 찾기
#   .\Resolve-ServerByIp.ps1 -Grep 모바일디빈스
#   .\Resolve-ServerByIp.ps1 -Grep DZ-MIDMWAS -Env 개발
#
# 상태(Status) 값
#   EXACT : 인덱스에 그 IP가 그대로 있다
#   NEAR  : 없지만 같은 /24에 아는 서버가 있다 -> 인접 IP일 가능성 (2호기/보조NIC/미기재)
#   NONE  : /24 대역조차 모른다 -> 시트 밖. 별도 확인 대상
# ===========================================================================

param(
    [string[]]$Ip = @(),
    [string]$Report = "",
    [string]$Grep = "",
    [string]$Index = "mapping\server_ip_index.dat",
    [ValidateSet("all","운영","개발")]
    [string]$Env = "all",
    [ValidateSet("all","ASIS","TOBE")]
    [string]$Stage = "all",
    [switch]$NoNear,                     # /24 이웃 추정 끄기
    [int]$NearMax = 3,                   # NEAR 로 보여줄 이웃 개수 (4옥텟 거리 가까운 순)
    [string[]]$IgnoreIps = @("127.0.0.1","0.0.0.0","255.255.255.255"),   # 조회에서 제외할 상용구 IP
    [switch]$EmitIpMapping,              # 조회 결과로 A-4 매핑표 초안 생성
    [string]$Out = "report\resolve_server_by_ip.dat",
    [string]$MapOut = "mapping\ip_mapping_draft_resolved.dat",
    [switch]$ConsoleOnly
)
# [PATCH] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "===== Resolve-ServerByIp v1 ====="

# ---------- 공통 ----------
function Test-ValidIp([string]$s) {
    if ($s -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($o in $s.Split('.')) { if ([int]$o -gt 255) { return $false } }
    return $true
}
function Get-Slash24([string]$s) { return ($s.Split('.')[0..2] -join '.') }

# [v9 동일 처리] powershell -File 로 실행하면 배열 파라미터가 문자열 하나로 뭉개진다
if ($Ip.Count -eq 1 -and ($Ip[0] -match '[,;]')) {
    $Ip = $Ip[0] -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# ---------- 인덱스 로드 ----------
if (-not (Test-Path $Index)) {
    Write-Error "인덱스 파일 없음: $Index (현재 폴더: $PWD)"
    Write-Host  "  -> 서버이관_통합정보.xlsx 에서 Build-ServerIpIndex.ps1 로 먼저 생성할 것"
    exit 1
}
$rawLines = Get-Content -LiteralPath $Index -Encoding UTF8 |
            Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith("#") }
if (-not $rawLines) { Write-Error "인덱스가 비어 있음: $Index"; exit 1 }

$idxRows = $rawLines | ConvertFrom-Csv -Delimiter '|'
if (-not ($idxRows[0].PSObject.Properties.Name -contains "IP")) {
    Write-Error "인덱스에 IP 컬럼이 없음: $Index (구분자 | 확인)"; exit 1
}
if ($Env   -ne "all") { $idxRows = $idxRows | Where-Object { $_.환경 -eq $Env } }
if ($Stage -ne "all") { $idxRows = $idxRows | Where-Object { $_.단계 -eq $Stage } }
$idxRows = @($idxRows)
Write-Host ("인덱스 : {0} ({1}행 / 환경={2} 단계={3})" -f $Index, $idxRows.Count, $Env, $Stage)

# IP -> 행들 / /24 -> 행들
$byIp    = @{}
$bySlash = @{}
foreach ($row in $idxRows) {
    $k = $row.IP.Trim()
    if (-not (Test-ValidIp $k)) { continue }
    if (-not $byIp.ContainsKey($k)) { $byIp[$k] = New-Object System.Collections.ArrayList }
    [void]$byIp[$k].Add($row)
    $s = Get-Slash24 $k
    if (-not $bySlash.ContainsKey($s)) { $bySlash[$s] = New-Object System.Collections.ArrayList }
    [void]$bySlash[$s].Add($row)
}

# ---------- 역검색 (-Grep) ----------
if ($Grep) {
    Write-Host ("역검색 : '{0}'" -f $Grep)
    $hit = @($idxRows | Where-Object {
        $_.시스템 -like "*$Grep*" -or $_.서버명 -like "*$Grep*" -or
        $_.업무명 -like "*$Grep*" -or $_.업무코드 -like "*$Grep*" -or
        $_.Instance -like "*$Grep*" -or $_.URL -like "*$Grep*"
    })
    if (-not $hit) { Write-Host "  일치 없음"; exit 0 }
    ($hit | Sort-Object 환경,단계,@{ Expression = { [version]$_.IP } } |
        Format-Table IP,환경,단계,시스템,구분,서버명,업무코드,대응IP -AutoSize |
        Out-String -Width 300).TrimEnd() | Write-Host
    Write-Host ("  {0}건" -f $hit.Count)
    exit 0
}

# ---------- 조회 대상 IP 수집 ----------
$targets = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($v in $Ip) {
    $t = $v.Trim()
    if (Test-ValidIp $t) { if (-not $targets.Contains($t)) { $targets.Add($t, 0) } }
    elseif ($t) { Write-Warning "IP 형식 아님 — 건너뜀: $t" }
}

if ($Report) {
    if (-not (Test-Path $Report)) { Write-Error "리포트 없음: $Report"; exit 1 }
    $got = 0
    $rep = $null
    try { $rep = Import-Csv -LiteralPath $Report } catch {}
    if ($rep -and ($rep[0].PSObject.Properties.Name -contains "Value")) {
        # Find v9 리포트: Kind/Value 컬럼을 그대로 쓴다
        foreach ($r in $rep) {
            if ($r.PSObject.Properties.Name -contains "Kind" -and $r.Kind -and $r.Kind -ne "ip") { continue }
            $val = ("" + $r.Value).Trim()
            # "10.1.2.3:8080" 형태면 IP만 떼어낸다
            if ($val -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') { $val = $Matches[1] }
            if (Test-ValidIp $val) {
                if (-not $targets.Contains($val)) { $targets.Add($val, 0) }
                $targets[$val] = [int]$targets[$val] + 1
                $got++
            }
        }
        Write-Host ("리포트 : {0} (Kind/Value 컬럼 사용, IP {1}건)" -f $Report, $got)
    } else {
        # v8.2 이하 또는 컬럼 구조가 다르면 본문에서 IPv4를 긁는다
        $txt = Get-Content -LiteralPath $Report -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($txt, '(?<![\d.])\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![\d.])')) {
            $val = $m.Value
            if (Test-ValidIp $val) {
                if (-not $targets.Contains($val)) { $targets.Add($val, 0) }
                $targets[$val] = [int]$targets[$val] + 1
                $got++
            }
        }
        Write-Host ("리포트 : {0} (컬럼 폴백 — 본문 IPv4 추출, {1}건)" -f $Report, $got)
    }
}

foreach ($ig in $IgnoreIps) {
    $t = ("" + $ig).Trim()
    if ($t -and $targets.Contains($t)) { $targets.Remove($t); Write-Host ("  (제외) $t") }
}

if ($targets.Count -eq 0) {
    Write-Error "조회할 IP가 없음. -Ip 또는 -Report 를 지정할 것"
    exit 1
}
Write-Host ("조회 대상 : {0}개 IP" -f $targets.Count)
Write-Host ""

# ---------- 조회 ----------
$results = New-Object System.Collections.Generic.List[object]
$cntExact = 0; $cntNear = 0; $cntNone = 0

function New-Row([string]$q, [int]$hits, [string]$status, $row, [string]$note) {
    $o = [ordered]@{ 조회IP = $q; 검출건수 = $hits; 상태 = $status }
    foreach ($c in @("환경","단계","종류","시스템","구분","서버명","업무코드","업무명","대응IP","PORT","URL","Instance")) {
        if ($row) { $o[$c] = ("" + $row.$c) } else { $o[$c] = "" }
    }
    if ($row) { $o["인덱스IP"] = ("" + $row.IP) } else { $o["인덱스IP"] = "" }
    $o["비고"] = $note
    return [pscustomobject]$o
}

foreach ($q in @($targets.Keys)) {
    $hits = [int]$targets[$q]
    if ($byIp.ContainsKey($q)) {
        $cntExact++
        foreach ($row in $byIp[$q]) { $results.Add((New-Row $q $hits "EXACT" $row $row.비고)) }
    }
    elseif (-not $NoNear -and $bySlash.ContainsKey((Get-Slash24 $q))) {
        $cntNear++
        $last = [int]($q.Split('.')[3])
        $nb = @($bySlash[(Get-Slash24 $q)] |
                Sort-Object @{ Expression = { [Math]::Abs([int]($_.IP.Split('.')[3]) - $last) } },
                            @{ Expression = { [int]($_.IP.Split('.')[3]) } })
        $take = $nb
        if ($NearMax -gt 0 -and $nb.Count -gt $NearMax) { $take = $nb[0..($NearMax - 1)] }
        foreach ($row in $take) {
            $d = [Math]::Abs([int]($row.IP.Split('.')[3]) - $last)
            $results.Add((New-Row $q $hits "NEAR" $row ("같은 /24 이웃 (4옥텟 차 {0}) — 인덱스에 없는 IP. 소속 추정용" -f $d)))
        }
    }
    else {
        $cntNone++
        $results.Add((New-Row $q $hits "NONE" $null "인덱스에 없음 — 시트 밖 IP(외부연계/미기재/오탐) 확인 필요"))
    }
}

# ---------- 콘솔 ----------
$ex0 = @($results | Where-Object { $_.상태 -eq "EXACT" })
if ($ex0.Count -gt 0) {
    Write-Host "-- EXACT --"
    ($ex0 | Format-Table 조회IP,검출건수,환경,단계,시스템,구분,서버명,업무코드,대응IP -AutoSize |
        Out-String -Width 300).TrimEnd() | Write-Host
    Write-Host ""
}

$nearQ = @($results | Where-Object { $_.상태 -eq "NEAR" } | Select-Object -ExpandProperty 조회IP -Unique)
if ($nearQ.Count -gt 0) {
    Write-Host "-- NEAR (인덱스에 없지만 같은 대역에 아는 서버가 있음) --"
    foreach ($q in $nearQ) {
        $nb = @($results | Where-Object { $_.조회IP -eq $q -and $_.상태 -eq "NEAR" })
        $desc = ($nb | ForEach-Object { "{0}={1}/{2}" -f $_.인덱스IP, $_.시스템, $_.서버명 } |
                 Select-Object -Unique) -join " , "
        Write-Host ("  {0}  ->  {1}" -f $q, $desc)
    }
    Write-Host ""
}
$noneQ = @($results | Where-Object { $_.상태 -eq "NONE" } | Select-Object -ExpandProperty 조회IP -Unique)
if ($noneQ.Count -gt 0) {
    Write-Host "-- NONE (대역조차 모름 — 별도 확인) --"
    Write-Host ("  " + ($noneQ -join ", "))
    Write-Host ""
}
Write-Host ("요약 : EXACT {0} / NEAR {1} / NONE {2}  (조회 {3}개)" -f $cntExact, $cntNear, $cntNone, $targets.Count)

# ---------- 파일 출력 ----------
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
if (-not $ConsoleOnly) {
    $dir = Split-Path $Out -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cols = @("조회IP","검출건수","상태","환경","단계","종류","시스템","구분","서버명",
              "업무코드","업무명","대응IP","PORT","URL","Instance","인덱스IP","비고")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Resolve-ServerByIp v1 결과 (구분자 |) — " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
    $lines.Add("# EXACT=인덱스 일치 / NEAR=같은 /24 이웃 추정 / NONE=대역 미확인")
    $lines.Add($cols -join "|")
    foreach ($r in $results) {
        $vals = foreach ($c in $cols) { ("" + $r.$c) -replace '\|','/' }
        $lines.Add($vals -join "|")
    }
    [System.IO.File]::WriteAllText($Out, ($lines -join "`r`n") + "`r`n", $utf8Bom)
    Write-Host ""
    Write-Host "-> $Out"
}

# ---------- A-4 매핑표 초안 ----------
if ($EmitIpMapping) {
    $ex = @($results | Where-Object { $_.상태 -eq "EXACT" -and $_.단계 -eq "ASIS" -and $_.대응IP })
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $ml = New-Object System.Collections.Generic.List[string]
    $ml.Add("# ip_mapping 초안 — Resolve-ServerByIp -EmitIpMapping 생성 (" + (Get-Date -Format "yyyy-MM-dd") + ")")
    $ml.Add("# 실제로 소스에서 검출된 AS-IS IP만 담았다. NewIP는 시트의 TO-BE 값 — 반드시 눈으로 검증할 것")
    $ml.Add("# 포트는 업무별로 달라 비워 뒀다 (-UsePort 를 쓸 거면 직접 채울 것)")
    $ml.Add("업무코드,업무명,서버명,호스트명,OldIP,NewIP,OldPort,NewPort")
    $n = 0
    foreach ($r in ($ex | Sort-Object { [version]$_.조회IP })) {
        if ($r.조회IP -eq $r.대응IP) { continue }        # Old=New 금지
        if (-not $seen.Add($r.조회IP)) { continue }       # OldIP 중복 금지
        $f = { param($s) ("" + $s) -replace ',','/' }
        $ml.Add(("{0},{1},{2},{3},{4},{5},," -f (& $f $r.업무코드), (& $f $r.업무명),
                 (& $f $r.서버명), (& $f ($r.환경 + "-" + $r.구분)), $r.조회IP, $r.대응IP))
        $n++
    }
    $dir2 = Split-Path $MapOut -Parent
    if ($dir2 -and -not (Test-Path $dir2)) { New-Item -ItemType Directory -Path $dir2 -Force | Out-Null }
    [System.IO.File]::WriteAllText($MapOut, ($ml -join "`r`n") + "`r`n", $utf8Bom)
    Write-Host "-> $MapOut  (매핑 $n 행)"
    if ($cntNear -gt 0 -or $cntNone -gt 0) {
        Write-Warning ("NEAR {0} / NONE {1} 은 매핑표에 안 들어갔다 — 수동 판정 후 추가할 것" -f $cntNear, $cntNone)
    }
    Write-Host "다음 단계 : 매핑표 검토 -> Replace-AsisIp.ps1 -Root ... -Map $MapOut  (DryRun)"
}
