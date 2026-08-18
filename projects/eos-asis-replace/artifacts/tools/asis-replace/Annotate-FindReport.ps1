# ===========================================================================
# [표준 헤더] Annotate-FindReport.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1.5  Find 리포트에 서버 정보 붙이기 (A-1 이후, A-2 매핑표 이전)
#   역할 : Find 리포트의 ip/domain/host 값을 서버이관 인덱스와 대조해
#          '어느 시스템의 어느 서버인지'를 리포트에 컬럼으로 붙인다
#          -> 엑셀 왔다갔다 하며 값 하나씩 찾아보는 작업을 없앤다
#   입력 : -Report Find 리포트 .dat, -Index mapping\server_key_index.dat
#   출력 : report\<리포트명>_annotated.dat  (원본 전체 행 + 서버 컬럼)
#          report\<리포트명>_serverlist.dat (값 단위 집계 — 이쪽을 먼저 볼 것)
#   선행 : A-1 Find 실행 완료 / 인덱스 존재
#   상태 : 현행 v1
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
# ===========================================================================
# Annotate-FindReport.ps1 (v1)
#
# 왜 필요한가
#   Find 리포트에는 "10.10.88.164", "dm.mdbins.com" 같은 값만 있다.
#   그게 어느 서버인지는 서버이관 시트를 봐야 알고, 값이 수십 개면 그 대조가 곧 작업량이다.
#   이 스크립트는 그 대조를 리포트에 미리 박아 넣는다. 엑셀은 결과만 열면 된다.
#
# 사용법
#   .\Annotate-FindReport.ps1 -Report .\report\portal_asis_path_report.dat
#   .\Annotate-FindReport.ps1 -Report .\report\portal_asis_path_report.dat -Kind ip,domain
#   .\Annotate-FindReport.ps1 -RootList .\report\*_report.dat        # 리포트 여러 개 일괄
#
# 판정 상태
#   EXACT  : 인덱스에 그 값이 그대로 있다
#   SUFFIX : 도메인 상위/하위 관계로 걸렸다 (mdbins.com <-> dm.mdbins.com)
#   NEAR   : IP가 인덱스에 없지만 같은 /24에 아는 서버가 있다 (인접 IP 추정)
#   NONE   : 인덱스에 없다 -> 외부연계 / 시트 미기재 / 오탐 중 하나. 사람이 판정
# ===========================================================================

param(
    [string]$Report = "",
    [string]$RootList = "",              # 여러 리포트를 한 번에 (와일드카드 가능)
    [string]$Index = "mapping\server_key_index.dat",
    [string[]]$Kind = @("ip","domain","host","unc"),   # 붙일 대상 Kind
    [string]$OutDir = "report",
    [int]$NearMax = 3,
    [switch]$NoNear,
    [string[]]$IgnoreValues = @("127.0.0.1","0.0.0.0","255.255.255.255","localhost"),
    [switch]$SummaryOnly                 # 값 단위 집계만 (행 단위 annotated 생략)
)
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "===== Annotate-FindReport v1 ====="

# [v9 동일 처리] -File 실행 시 배열 파라미터가 문자열 하나로 뭉개진다
if ($Kind.Count -eq 1 -and ($Kind[0] -match '[,;]')) {
    $Kind = $Kind[0] -split '[,;]' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
} else {
    $Kind = $Kind | ForEach-Object { $_.Trim().ToLower() }
}
$kindSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in $Kind) { [void]$kindSet.Add($k) }

function Test-ValidIp([string]$s) {
    if ($s -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($o in $s.Split('.')) { if ([int]$o -gt 255) { return $false } }
    return $true
}
function Get-Slash24([string]$s) { return ($s.Split('.')[0..2] -join '.') }

# ---------- 인덱스 ----------
if (-not (Test-Path $Index)) {
    Write-Error "인덱스 파일 없음: $Index (현재 폴더: $PWD)"
    Write-Host  "  -> Build-ServerKeyIndex.ps1 로 먼저 생성할 것"
    exit 1
}
$raw = Get-Content -LiteralPath $Index -Encoding UTF8 |
       Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith("#") }
$idxRows = @($raw | ConvertFrom-Csv -Delimiter '|')
if (-not $idxRows -or -not ($idxRows[0].PSObject.Properties.Name -contains "키")) {
    Write-Error "인덱스에 '키' 컬럼이 없음: $Index (구분자 | 확인)"; exit 1
}

$byKey    = @{}     # 소문자 키 -> 행 목록
$bySlash  = @{}     # /24 -> 행 목록 (ip/vip만)
$domKeys  = New-Object System.Collections.Generic.List[string]
foreach ($row in $idxRows) {
    $k = ("" + $row.키).Trim()
    if (-not $k) { continue }
    $lk = $k.ToLower()
    if (-not $byKey.ContainsKey($lk)) { $byKey[$lk] = New-Object System.Collections.ArrayList }
    [void]$byKey[$lk].Add($row)
    if ($row.키종류 -eq "ip" -or $row.키종류 -eq "vip") {
        if (Test-ValidIp $k) {
            $s = Get-Slash24 $k
            if (-not $bySlash.ContainsKey($s)) { $bySlash[$s] = New-Object System.Collections.ArrayList }
            [void]$bySlash[$s].Add($row)
        }
    }
    elseif ($row.키종류 -eq "domain") { if (-not $domKeys.Contains($lk)) { $domKeys.Add($lk) } }
}
# 인덱스 도메인에서 맨 앞 라벨을 떼어 '자사 도메인 계열'을 만든다
#   dm.mdbins.com -> mdbins.com / prm.dbins.co.kr -> dbins.co.kr
#   (여기서 더 자르면 co.kr 같은 공용 접미사가 되어 외부 도메인까지 걸린다 — 한 단계만)
$baseDom = New-Object System.Collections.Generic.List[string]
foreach ($d in $domKeys) {
    $parts = $d.Split('.')
    if ($parts.Count -ge 3) {
        $b = ($parts[1..($parts.Count - 1)] -join '.')
        if ($b.Split('.').Count -ge 2 -and -not $baseDom.Contains($b)) { $baseDom.Add($b) }
    }
}
Write-Host ("인덱스 : {0} ({1}행 / 고유키 {2}개 / 자사도메인 {3}종)" -f $Index, $idxRows.Count, $byKey.Count, $baseDom.Count)

$ignore = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($v in $IgnoreValues) { [void]$ignore.Add(("" + $v).Trim().ToLower()) }

# ---------- 값 하나 판정 ----------
# 반환: @{ Status=..; Rows=@(인덱스행); Note=".." }
function Resolve-Value([string]$val, [string]$kind) {
    $v = ("" + $val).Trim()
    if (-not $v) { return @{ Status = ""; Rows = @(); Note = "" } }

    # "ip:port" / "host:port" / "http://host/path" 형태에서 키만 떼어낸다
    if ($v -match '^(?:https?://)?([^/:\s]+)') { $v = $Matches[1] }
    $lv = $v.ToLower().TrimEnd('.')
    if ($ignore.Contains($lv)) { return @{ Status = "IGNORE"; Rows = @(); Note = "상용구 — 판정 제외" } }

    if ($byKey.ContainsKey($lv)) { return @{ Status = "EXACT"; Rows = @($byKey[$lv]); Note = "" } }

    if (Test-ValidIp $v) {
        if ($NoNear) { return @{ Status = "NONE"; Rows = @(); Note = "인덱스에 없음" } }
        $s = Get-Slash24 $v
        if (-not $bySlash.ContainsKey($s)) { return @{ Status = "NONE"; Rows = @(); Note = "대역조차 인덱스에 없음" } }
        $last = [int]($v.Split('.')[3])
        $nb = @($bySlash[$s] |
                Sort-Object @{ Expression = { [Math]::Abs([int]($_.키.Split('.')[3]) - $last) } },
                            @{ Expression = { [int]($_.키.Split('.')[3]) } })
        if ($NearMax -gt 0 -and $nb.Count -gt $NearMax) { $nb = $nb[0..($NearMax - 1)] }
        return @{ Status = "NEAR"; Rows = $nb; Note = "같은 /24 이웃 — 인접 IP 추정. 사람이 판정" }
    }

    # 도메인: 상위/하위 포함 관계
    if ($lv -match '\.') {
        $hit = New-Object System.Collections.ArrayList
        foreach ($d in $domKeys) {
            if ($lv.EndsWith("." + $d) -or $d.EndsWith("." + $lv)) {
                foreach ($r in $byKey[$d]) { [void]$hit.Add($r) }
            }
        }
        if ($hit.Count -gt 0) { return @{ Status = "SUFFIX"; Rows = @($hit); Note = "도메인 상위/하위 일치 — 정확한 호스트는 확인 필요" } }
        # 인덱스에 정확한 호스트는 없지만 자사 도메인 계열인 경우 (시트 미기재 가능성이 높다)
        foreach ($b in $baseDom) {
            if ($lv -eq $b -or $lv.EndsWith("." + $b)) {
                $sib = New-Object System.Collections.ArrayList
                foreach ($d in $domKeys) { if ($d -eq $b -or $d.EndsWith("." + $b)) { foreach ($r in $byKey[$d]) { [void]$sib.Add($r) } } }
                return @{ Status = "SUFFIX"; Rows = @($sib); Note = ("자사 도메인 계열(" + $b + ") — 인덱스에 이 호스트는 없다. 시트 미기재/신규 확인") }
            }
        }
    }
    return @{ Status = "NONE"; Rows = @(); Note = "인덱스에 없음 — 외부연계/미기재/오탐 판정 필요" }
}

function Join-Uniq($rows, [string]$prop) {
    $vals = @($rows | ForEach-Object { ("" + $_.$prop).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    return ($vals -join " ; ")
}

# ---------- 리포트 1건 처리 ----------
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$ADD = @("판정","환경","단계","키종류","시스템","구분","서버명","업무코드","업무명","대응키","PORT","URL","Instance","판정비고")

function Invoke-Annotate([string]$repPath) {
    $rep = $null
    try { $rep = @(Import-Csv -LiteralPath $repPath) } catch {}
    if (-not $rep -or $rep.Count -eq 0) { Write-Warning "읽을 수 없거나 빈 리포트: $repPath"; return }
    $cols0 = @($rep[0].PSObject.Properties.Name)
    if (-not ($cols0 -contains "Value")) {
        Write-Warning "Value 컬럼이 없음 (Find v9 리포트가 아님): $repPath"; return
    }
    $hasKind = $cols0 -contains "Kind"

    $name = [System.IO.Path]::GetFileNameWithoutExtension($repPath)
    Write-Host ""
    Write-Host ("[{0}]  {1}행" -f $name, $rep.Count)

    $cache = @{}
    $out   = New-Object System.Collections.Generic.List[object]
    $sum   = New-Object System.Collections.Specialized.OrderedDictionary
    $stat  = @{}

    foreach ($r in $rep) {
        $kd = if ($hasKind) { ("" + $r.Kind).Trim().ToLower() } else { "" }
        $doIt = $true
        if ($hasKind -and $kd -and -not $kindSet.Contains($kd)) { $doIt = $false }

        $res = $null
        if ($doIt) {
            $ck = $kd + "|" + ("" + $r.Value).Trim().ToLower()
            if ($cache.ContainsKey($ck)) { $res = $cache[$ck] }
            else { $res = Resolve-Value $r.Value $kd; $cache[$ck] = $res }
        }

        $o = [ordered]@{}
        foreach ($c in $cols0) { $o[$c] = ("" + $r.$c) }
        if ($res) {
            $rows = @($res.Rows)
            $o["판정"]     = $res.Status
            $o["환경"]     = (Join-Uniq $rows "환경")
            $o["단계"]     = (Join-Uniq $rows "단계")
            $o["키종류"]   = (Join-Uniq $rows "키종류")
            $o["시스템"]   = (Join-Uniq $rows "시스템")
            $o["구분"]     = (Join-Uniq $rows "구분")
            $o["서버명"]   = (Join-Uniq $rows "서버명")
            $o["업무코드"] = (Join-Uniq $rows "업무코드")
            $o["업무명"]   = (Join-Uniq $rows "업무명")
            $o["대응키"]   = (Join-Uniq $rows "대응키")
            $o["PORT"]     = (Join-Uniq $rows "PORT")
            $o["URL"]      = (Join-Uniq $rows "URL")
            $o["Instance"] = (Join-Uniq $rows "Instance")
            if ($res.Status -eq "NEAR" -and $rows.Count -gt 0) {
                $o["판정비고"] = $res.Note + " (" + (Join-Uniq $rows "키") + ")"
            } else { $o["판정비고"] = $res.Note }

            if (-not $stat.ContainsKey($res.Status)) { $stat[$res.Status] = 0 }
            $stat[$res.Status] = $stat[$res.Status] + 1

            # 값 단위 집계
            $sk = $kd + "|" + ("" + $r.Value).Trim()
            if (-not $sum.Contains($sk)) {
                $sum.Add($sk, [ordered]@{
                    Kind = $kd; Value = ("" + $r.Value).Trim(); 검출건수 = 0
                    판정 = $o["판정"]; 환경 = $o["환경"]; 단계 = $o["단계"]
                    시스템 = $o["시스템"]; 구분 = $o["구분"]; 서버명 = $o["서버명"]
                    업무코드 = $o["업무코드"]; 업무명 = $o["업무명"]; 대응키 = $o["대응키"]
                    PORT = $o["PORT"]; URL = $o["URL"]; Instance = $o["Instance"]
                    판정비고 = $o["판정비고"]; 예시파일 = ("" + $r.File)
                })
            }
            $sum[$sk]["검출건수"] = [int]$sum[$sk]["검출건수"] + 1
        } else {
            foreach ($c in $ADD) { $o[$c] = "" }
            $o["판정"] = "-"
        }
        $out.Add([pscustomobject]$o)
    }

    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

    # 값 단위 집계 (사람이 먼저 볼 파일)
    $sumCols = @("Kind","Value","검출건수","판정","환경","단계","시스템","구분","서버명",
                 "업무코드","업무명","대응키","PORT","URL","Instance","판정비고","예시파일")
    $sumOut = Join-Path $OutDir ($name + "_serverlist.dat")
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add("# Annotate-FindReport v1 — 값 단위 집계 (구분자 |) " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
    $L.Add("# EXACT=인덱스 일치 / SUFFIX=도메인 상하위 / NEAR=같은 /24 이웃 추정 / NONE=미확인 / IGNORE=상용구")
    $L.Add($sumCols -join "|")
    $order = @{ "NONE" = 0; "NEAR" = 1; "SUFFIX" = 2; "EXACT" = 3; "IGNORE" = 4 }
    $sumRows = @()
    foreach ($k in $sum.Keys) { $sumRows += ,([pscustomobject]$sum[$k]) }
    $sumRows = @($sumRows | Sort-Object @{ Expression = { if ($order.ContainsKey($_.판정)) { $order[$_.판정] } else { 9 } } },
                                        @{ Expression = { -[int]$_.검출건수 } }, Kind, Value)
    foreach ($r in $sumRows) {
        $L.Add((@(foreach ($c in $sumCols) { ("" + $r.$c) -replace '\|','/' }) -join "|"))
    }
    [System.IO.File]::WriteAllText($sumOut, ($L -join "`r`n") + "`r`n", $utf8Bom)

    # 행 단위 (원본 컬럼 전부 보존 + 서버 컬럼)
    if (-not $SummaryOnly) {
        $allCols = @($cols0) + $ADD
        $annOut = Join-Path $OutDir ($name + "_annotated.dat")
        $L2 = New-Object System.Collections.Generic.List[string]
        $L2.Add("# Annotate-FindReport v1 — 원본 리포트 + 서버 컬럼 (구분자 |) " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
        $L2.Add($allCols -join "|")
        foreach ($r in $out) {
            $L2.Add((@(foreach ($c in $allCols) { ("" + $r.$c) -replace '\|','/' -replace '[\r\n]',' ' }) -join "|"))
        }
        [System.IO.File]::WriteAllText($annOut, ($L2 -join "`r`n") + "`r`n", $utf8Bom)
    }

    # 콘솔 요약
    $line = @()
    foreach ($s in @("EXACT","SUFFIX","NEAR","NONE","IGNORE")) {
        if ($stat.ContainsKey($s)) { $line += ("{0} {1}" -f $s, $stat[$s]) }
    }
    Write-Host ("  판정(행 기준) : " + ($line -join " / "))
    Write-Host ("  고유 값       : {0}개" -f $sumRows.Count)

    $todo = @($sumRows | Where-Object { $_.판정 -eq "NONE" -or $_.판정 -eq "NEAR" -or $_.판정 -eq "SUFFIX" })
    if ($todo.Count -gt 0) {
        Write-Host "  -- 사람이 판정해야 하는 값 --"
        foreach ($r in ($todo | Select-Object -First 20)) {
            $hint = $r.서버명
            if (-not $hint) { $hint = $r.판정비고 }
            Write-Host ("    {0,-6} {1,-32} {2,4}건  {3}" -f $r.판정, $r.Value, $r.검출건수, $hint)
        }
        if ($todo.Count -gt 20) { Write-Host ("    ... 외 {0}건 (파일 참조)" -f ($todo.Count - 20)) }
    }
    Write-Host ("  -> {0}" -f $sumOut)
    if (-not $SummaryOnly) { Write-Host ("  -> {0}" -f (Join-Path $OutDir ($name + "_annotated.dat"))) }
}

# ---------- 실행 ----------
$targets = @()
if ($RootList) {
    $targets = @(Get-ChildItem -Path $RootList -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch '_(annotated|serverlist|skipped)' } |
                 ForEach-Object { $_.FullName })
    if ($targets.Count -eq 0) { Write-Error "일치하는 리포트가 없음: $RootList"; exit 1 }
} elseif ($Report) {
    if (-not (Test-Path $Report)) { Write-Error "리포트 없음: $Report"; exit 1 }
    $targets = @((Resolve-Path $Report).Path)
} else {
    Write-Error "-Report 또는 -RootList 를 지정할 것"; exit 1
}

foreach ($t in $targets) { Invoke-Annotate $t }

Write-Host ""
Write-Host "다음 단계 : *_serverlist.dat 에서 NONE/NEAR 판정 -> Extract-MappingDraft / ip_mapping 작성"
