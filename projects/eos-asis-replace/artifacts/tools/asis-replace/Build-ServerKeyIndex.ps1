# ===========================================================================
# [표준 헤더] Build-ServerKeyIndex.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1.4  서버이관 통합 인덱스 생성 (Annotate 보다 먼저, 시트가 바뀔 때만)
#   역할 : 서버이관_통합정보 시트를 붙여넣은 TSV 를 조회용 .dat 인덱스로 변환
#          IP / VIP / 도메인(URL) / 서버명 / Instance 를 전부 '키'로 올린다
#          '210.127.41.101 / .102', 'PZ-WMDBWEB1/2' 같은 축약 표기를 실제 값으로 펼친다
#   입력 : -Tsv <운영시트.dat> [-Tsv2 <개발시트.dat>]   (엑셀에서 Ctrl+C -> 메모장 붙여넣기)
#   출력 : mapping\server_key_index.dat
#   선행 : 없음
#   상태 : 현행 v2 (v1 = IP만 색인하던 Build-ServerIpIndex)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
# ===========================================================================
# Build-ServerKeyIndex.ps1 (v2)
#
# 왜 TSV 인가
#   사무실 xlsx 는 DRM이 걸려 스크립트로 못 연다 (COM으로 열어도 암호화 사본이 나온다).
#   그런데 '엑셀 화면에서 범위 선택 -> Ctrl+C -> 메모장 Ctrl+V' 는 DRM과 무관하게 된다.
#   붙여넣으면 탭 구분 텍스트가 되므로, .dat 로 저장해서 이 스크립트에 넣으면 된다.
#   (사내 규정은 확인할 것)
#
# 사용법
#   1) '운영_통합정보' 시트 전체(헤더 포함) 선택 -> Ctrl+C -> 메모장 -> UTF-8 로 sheet_운영.dat
#   2) '개발_통합정보' 도 같은 방식으로 sheet_개발.dat
#   3) .\Build-ServerKeyIndex.ps1 -Tsv .\sheet_운영.dat -Tsv2 .\sheet_개발.dat
#
# 시트 판별
#   헤더에 'WEB AS-IS IP' 가 있으면 개발, 'AS-IS IP' 가 있으면 운영 레이아웃으로 자동 판단.
# ===========================================================================

param(
    [Parameter(Mandatory=$true)][string]$Tsv,
    [string]$Tsv2 = "",
    [ValidateSet("auto","운영","개발")][string]$Env  = "auto",
    [ValidateSet("auto","운영","개발")][string]$Env2 = "auto",
    [string]$Out = "mapping\server_key_index.dat",
    [string]$Delimiter = "`t"
)
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "===== Build-ServerKeyIndex v2 ====="

$COLS  = @("키","키종류","환경","단계","시스템","구분","서버명","업무코드","업무명",
           "PORT","URL","Instance","담당","대응키","비고")
$MULTI = @("업무코드","업무명","PORT","URL","Instance","담당","비고")

function Test-ValidIp([string]$s) {
    if ($s -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($o in $s.Split('.')) { if ([int]$o -gt 255) { return $false } }
    return $true
}

# [주의] 아래 Expand-* 는 호출부에서 반드시 @( ) 로 감쌀 것.
#        PS는 원소 1개짜리 List를 반환하면 배열이 아니라 문자열로 언롤한다.
#        그 상태에서 $a[0] 을 하면 값이 아니라 첫 '글자'가 나온다 (v1에서 실제로 터진 버그).

# '210.127.41.101 / .102' -> 210.127.41.101, 210.127.41.102
function Expand-IpCell([string]$cell) {
    $out = New-Object System.Collections.Generic.List[string]
    $s = ("" + $cell).Trim()
    if (-not $s) { return $out }
    if ($s.ToUpper() -in @("N/A","NA","-","미정","TBD")) { return $out }
    $base = $null
    foreach ($tok in ($s -split '[/,]')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        if (Test-ValidIp $t) { $out.Add($t); $base = ($t.Split('.')[0..2] -join '.') }
        elseif ($t -match '^\.(\d{1,3})$' -and $base) {
            if ([int]$Matches[1] -le 255) { $out.Add($base + "." + $Matches[1]) }
        }
    }
    return $out
}

# 'PZ-WMDBWEB1/2' -> PZ-WMDBWEB1, PZ-WMDBWEB2   /   'd1gptwb1 / d1gptewb1' -> 둘 다
function Expand-HostCell([string]$cell) {
    $out = New-Object System.Collections.Generic.List[string]
    $s = ("" + $cell).Trim()
    if (-not $s -or $s -eq "-" -or $s.ToUpper() -eq "N/A") { return $out }
    $base = $null
    foreach ($tok in ($s -split '/')) {
        $t = $tok.Trim()
        if (-not $t -or $t -eq "-") { continue }
        if ($t -match '^\d+$') { if ($base) { $out.Add($base + $t) } }
        else {
            $out.Add($t)
            if ($t -match '^(.*?)(\d+)$') { $base = $Matches[1] } else { $base = $t }
        }
    }
    return $out
}

# 'https://dm.mdbins.com:8443 (내부)' -> dm.mdbins.com  (IP 리터럴이면 빈 값 — ip 키가 이미 있다)
function Get-UrlHost([string]$cell) {
    $s = ("" + $cell).Trim()
    if (-not $s) { return "" }
    if ($s -notmatch '(?:https?)://([A-Za-z0-9._-]+)') { return "" }
    $h = $Matches[1]
    if (Test-ValidIp $h) { return "" }
    return $h
}

# [주의] 두 번째 인자 이름을 $H 로 두면 호출부의 foreach 변수와 충돌한다 (PS는 대소문자 무시).
#        v2에서 실제로 헤더맵이 문자열로 덮여 1행만 파싱되는 사고가 났다.
function Get-Cell($row, $hdrMap, [string]$name) {
    if (-not $hdrMap.ContainsKey($name)) { return "" }
    $i = $hdrMap[$name]
    if ($i -ge $row.Count) { return "" }
    return (("" + $row[$i]) -replace '\s+', ' ').Trim()
}

$records = New-Object System.Collections.Generic.List[object]
function Add-Rec($key, $ktype, $env, $stage, $sys, $gubun, $svr, $code, $biz, $port, $url, $inst, $own, $peer, $note) {
    if (-not $key) { return }
    $records.Add([pscustomobject]@{
        키 = $key; 키종류 = $ktype; 환경 = $env; 단계 = $stage; 시스템 = $sys; 구분 = $gubun
        서버명 = $svr; 업무코드 = $code; 업무명 = $biz; PORT = $port; URL = $url
        Instance = $inst; 담당 = $own; 대응키 = $peer; 비고 = $note
    })
}

function Import-Sheet([string]$path, [string]$envHint) {
    if (-not (Test-Path $path)) { Write-Error "시트 파일 없음: $path"; return $false }
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8 | Where-Object { $_.Trim() })
    if ($lines.Count -lt 2) { Write-Error "내용이 부족함: $path"; return $false }

    $hIdx = -1
    for ($i = 0; $i -lt [Math]::Min(10, $lines.Count); $i++) {
        if ($lines[$i] -match '업무코드' -and $lines[$i] -match 'IP') { $hIdx = $i; break }
    }
    if ($hIdx -lt 0) { Write-Error "헤더 행을 못 찾음 (업무코드 + IP 컬럼 필요): $path"; return $false }

    $hdr = $lines[$hIdx] -split $Delimiter | ForEach-Object { (("" + $_) -replace '\s+',' ').Trim() }
    $H = @{}
    for ($i = 0; $i -lt $hdr.Count; $i++) { if ($hdr[$i] -and -not $H.ContainsKey($hdr[$i])) { $H[$hdr[$i]] = $i } }

    $layout = $envHint
    if ($layout -eq "auto") {
        if ($H.ContainsKey("WEB AS-IS IP")) { $layout = "개발" }
        elseif ($H.ContainsKey("AS-IS IP"))  { $layout = "운영" }
        else { Write-Error "레이아웃 판별 실패 — 'AS-IS IP' 또는 'WEB AS-IS IP' 컬럼이 없음: $path"; return $false }
    }
    Write-Host ("  {0}  -> {1} 레이아웃 / 데이터 {2}행" -f $path, $layout, ($lines.Count - $hIdx - 1))

    for ($i = $hIdx + 1; $i -lt $lines.Count; $i++) {
        $row = $lines[$i] -split $Delimiter
        if (-not (($row -join "").Trim())) { continue }

        if ($layout -eq "운영") {
            $sys  = Get-Cell $row $H "시스템"
            $gub  = Get-Cell $row $H "구분"
            $svr  = Get-Cell $row $H "서버명"
            $url  = Get-Cell $row $H "URL(DNS)"
            $port = Get-Cell $row $H "PORT(HTTP/HTTPS)"
            $code = Get-Cell $row $H "업무코드"
            $biz  = Get-Cell $row $H "업무명"
            $own  = (@((Get-Cell $row $H "SM"), (Get-Cell $row $H "담당2")) | Where-Object { $_ }) -join " / "
            $note = Get-Cell $row $H "비고"

            $sets = @(
                @{ k = "ip";  a = @(Expand-IpCell (Get-Cell $row $H "AS-IS IP"));  t = @(Expand-IpCell (Get-Cell $row $H "TO-BE IP"))  },
                @{ k = "vip"; a = @(Expand-IpCell (Get-Cell $row $H "AS-IS VIP")); t = @(Expand-IpCell (Get-Cell $row $H "TO-BE VIP")) }
            )
            foreach ($p in $sets) {
                for ($j = 0; $j -lt $p.a.Count; $j++) {
                    $peer = ""
                    if ($p.t.Count -gt $j) { $peer = $p.t[$j] } elseif ($p.t.Count -gt 0) { $peer = $p.t[0] }
                    Add-Rec $p.a[$j] $p.k "운영" "ASIS" $sys $gub $svr $code $biz $port $url "" $own $peer $note
                }
                for ($j = 0; $j -lt $p.t.Count; $j++) {
                    $peer = ""
                    if ($p.a.Count -gt $j) { $peer = $p.a[$j] } elseif ($p.a.Count -gt 0) { $peer = $p.a[0] }
                    Add-Rec $p.t[$j] $p.k "운영" "TOBE" $sys $gub $svr $code $biz $port $url "" $own $peer $note
                }
            }
            $dom = Get-UrlHost $url
            if ($dom) { Add-Rec $dom "domain" "운영" "ASIS" $sys $gub $svr $code $biz $port $url "" $own "" $note }
            foreach ($hn in @(Expand-HostCell $svr)) {
                Add-Rec $hn "host" "운영" "ASIS" $sys $gub $svr $code $biz $port $url "" $own "" $note
            }
        }
        else {
            $sys  = Get-Cell $row $H "시스템"
            $code = Get-Cell $row $H "업무코드"
            $biz  = Get-Cell $row $H "업무명"
            $inst = Get-Cell $row $H "Instance Name"
            $note = (@((Get-Cell $row $H "OS"), (Get-Cell $row $H "비고")) | Where-Object { $_ }) -join " "
            $roles = @(
                @{ g = "WEB"; a = "WEB AS-IS IP"; t = "WEB TO-BE IP"; p = "PORT(HTTP/HTTPS)" },
                @{ g = "WAS"; a = "WAS AS-IS IP"; t = "WAS TO-BE IP"; p = "TO-BE PORT" }
            )
            foreach ($r in $roles) {
                $svr  = Get-Cell $row $H $r.g
                $port = Get-Cell $row $H $r.p
                $a = @(Expand-IpCell (Get-Cell $row $H $r.a))
                $t = @(Expand-IpCell (Get-Cell $row $H $r.t))
                for ($j = 0; $j -lt $a.Count; $j++) {
                    $peer = ""
                    if ($t.Count -gt $j) { $peer = $t[$j] } elseif ($t.Count -gt 0) { $peer = $t[0] }
                    Add-Rec $a[$j] "ip" "개발" "ASIS" $sys $r.g $svr $code $biz $port "" $inst "" $peer $note
                }
                for ($j = 0; $j -lt $t.Count; $j++) {
                    $peer = ""
                    if ($a.Count -gt $j) { $peer = $a[$j] } elseif ($a.Count -gt 0) { $peer = $a[0] }
                    Add-Rec $t[$j] "ip" "개발" "TOBE" $sys $r.g $svr $code $biz $port "" $inst "" $peer $note
                }
                foreach ($hn in @(Expand-HostCell $svr)) {
                    Add-Rec $hn "host" "개발" "ASIS" $sys $r.g $svr $code $biz $port "" $inst "" "" $note
                }
                if ($inst) {
                    Add-Rec $inst "instance" "개발" "ASIS" $sys $r.g $svr $code $biz $port "" $inst "" "" $note
                }
            }
        }
    }
    return $true
}

if (-not (Import-Sheet $Tsv $Env)) { exit 1 }
if ($Tsv2) { if (-not (Import-Sheet $Tsv2 $Env2)) { exit 1 } }
if ($records.Count -eq 0) { Write-Error "추출된 키가 없음 — 구분자(-Delimiter)나 헤더를 확인할 것"; exit 1 }

# ---------- (키,키종류,환경,단계,시스템,구분,서버명) 단위 병합 ----------
$agg = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($r in $records) {
    $k = ($r.키.ToLower(), $r.키종류, $r.환경, $r.단계, $r.시스템, $r.구분, $r.서버명) -join ([char]1)
    if (-not $agg.Contains($k)) {
        $h = @{}
        foreach ($c in $COLS) { $h[$c] = $r.$c }
        foreach ($c in $MULTI) {
            $lst = New-Object System.Collections.Generic.List[string]
            if ($r.$c) { $lst.Add($r.$c) }
            $h[$c] = $lst
        }
        $agg.Add($k, $h)
    } else {
        $h = $agg[$k]
        foreach ($c in $MULTI) { if ($r.$c -and -not $h[$c].Contains($r.$c)) { $h[$c].Add($r.$c) } }
        if (-not $h["대응키"] -and $r.대응키) { $h["대응키"] = $r.대응키 }
    }
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($k in $agg.Keys) {
    $h = $agg[$k]
    $o = [ordered]@{}
    foreach ($c in $COLS) {
        if ($MULTI -contains $c) { $o[$c] = ($h[$c] -join ";") } else { $o[$c] = ("" + $h[$c]) }
    }
    $rows.Add([pscustomobject]$o)
}
# IP는 숫자 순, 나머지는 이름 순
$rows = @($rows | Sort-Object 키종류, 환경, 단계,
    @{ Expression = { if ($_.키종류 -eq "ip" -or $_.키종류 -eq "vip") { [version]$_.키 } else { [version]"0.0.0.0" } } },
    @{ Expression = { $_.키.ToLower() } })

# ---------- 출력 ----------
$dir = Split-Path $Out -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$srcNote = "# 원본: $Tsv"
if ($Tsv2) { $srcNote = $srcNote + " , $Tsv2" }

$L = New-Object System.Collections.Generic.List[string]
$L.Add("# 서버이관 통합 인덱스 (구분자 |) — Build-ServerKeyIndex v2 / " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
$L.Add($srcNote)
$L.Add("# 키종류: ip / vip / domain / host(서버명) / instance")
$L.Add("# 대응키 = ASIS행이면 TO-BE IP, TOBE행이면 AS-IS IP (ip/vip에만 존재)")
$L.Add("# 메모장으로 편집. 엑셀은 텍스트 마법사에서 구분자 | 지정")
$L.Add($COLS -join "|")
foreach ($r in $rows) {
    $L.Add((@(foreach ($c in $COLS) { ("" + $r.$c) -replace '\|','/' }) -join "|"))
}
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Out, ($L -join "`r`n") + "`r`n", $utf8Bom)

Write-Host ""
Write-Host ("-> {0}  ({1}행)" -f $Out, $rows.Count)
$rows | Group-Object 키종류 | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,-10} {1,4}행 / 고유키 {2}개" -f $_.Name, $_.Count,
        (@($_.Group | ForEach-Object { $_.키.ToLower() } | Select-Object -Unique)).Count)
}
Write-Host "다음 단계 : .\Annotate-FindReport.ps1 -Report .\report\<소스>_asis_path_report.dat"
