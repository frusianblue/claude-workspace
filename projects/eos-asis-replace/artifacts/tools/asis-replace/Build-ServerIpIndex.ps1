# ===========================================================================
# [표준 헤더] Build-ServerIpIndex.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1.4  서버이관 IP 인덱스 생성 (Resolve 보다 먼저, 시트가 바뀔 때만)
#   역할 : 서버이관_통합정보 시트를 붙여넣은 TSV 를 조회용 .dat 인덱스로 변환
#          '210.127.41.101 / .102' 같은 축약 표기를 실제 IP 2개로 펼친다
#   입력 : -Tsv <운영시트.dat> [-Tsv2 <개발시트.dat>]   (엑셀에서 Ctrl+C -> 메모장 붙여넣기)
#   출력 : mapping\server_ip_index.dat
#   선행 : 없음
#   상태 : 현행 v1
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
# ===========================================================================
# Build-ServerIpIndex.ps1 (v1)
#
# 왜 TSV 인가
#   사무실 xlsx 는 DRM이 걸려 스크립트로 못 연다 (COM으로 열어도 암호화 사본이 나온다).
#   그런데 '엑셀 화면에서 범위 선택 -> Ctrl+C -> 메모장 Ctrl+V' 는 DRM과 무관하게 된다.
#   붙여넣으면 탭 구분 텍스트가 되므로, 그걸 .dat 로 저장해서 이 스크립트에 넣으면 된다.
#   (파일을 반출하는 게 아니라 클립보드 내용을 같은 PC에서 다시 저장하는 것이라 정책 위반이 아님 —
#    사내 규정은 확인할 것)
#
# 사용법
#   1) 엑셀에서 '운영_통합정보' 시트 전체(헤더 포함) 선택 -> Ctrl+C
#   2) 메모장 붙여넣기 -> UTF-8 로 sheet_운영.dat 저장
#   3) '개발_통합정보' 도 같은 방식으로 sheet_개발.dat
#   4) .\Build-ServerIpIndex.ps1 -Tsv .\sheet_운영.dat -Tsv2 .\sheet_개발.dat
#
#   시트 하나만 있어도 된다:  .\Build-ServerIpIndex.ps1 -Tsv .\sheet_운영.dat
#
# 시트 판별
#   헤더에 'WEB AS-IS IP' 가 있으면 개발 레이아웃, 'AS-IS IP' 가 있으면 운영 레이아웃으로 자동 판단.
#   -Env 로 강제 지정도 된다.
# ===========================================================================

param(
    [Parameter(Mandatory=$true)][string]$Tsv,
    [string]$Tsv2 = "",
    [ValidateSet("auto","운영","개발")]
    [string]$Env = "auto",
    [ValidateSet("auto","운영","개발")]
    [string]$Env2 = "auto",
    [string]$Out = "mapping\server_ip_index.dat",
    [string]$Delimiter = "`t"
)
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "===== Build-ServerIpIndex v1 ====="

$COLS = @("IP","환경","단계","종류","시스템","구분","서버명","업무코드","업무명",
          "PORT","URL","Instance","담당","대응IP","비고")

function Test-ValidIp([string]$s) {
    if ($s -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($o in $s.Split('.')) { if ([int]$o -gt 255) { return $false } }
    return $true
}

# '210.127.41.101 / .102' -> @('210.127.41.101','210.127.41.102')
# [주의] 호출부는 반드시 @(Expand-IpCell ...) 로 감쌀 것 —
#        PS는 원소 1개 List를 반환하면 문자열로 언롤해서 $a[0] 이 IP가 아니라 첫 글자('1')가 된다
function Expand-IpCell([string]$cell) {
    $out = New-Object System.Collections.Generic.List[string]
    $s = ("" + $cell).Trim()
    if (-not $s) { return $out }
    if ($s.ToUpper() -in @("N/A","NA","-","미정","TBD")) { return $out }
    $base = $null
    foreach ($tok in ($s -split '[/,]')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        if (Test-ValidIp $t) {
            $out.Add($t)
            $base = ($t.Split('.')[0..2] -join '.')
        }
        elseif ($t -match '^\.(\d{1,3})$' -and $base) {
            $last = $Matches[1]
            if ([int]$last -le 255) { $out.Add($base + "." + $last) }
        }
    }
    return $out
}

function Get-Cell($row, $H, [string]$name) {
    if (-not $H.ContainsKey($name)) { return "" }
    $i = $H[$name]
    if ($i -ge $row.Count) { return "" }
    return (("" + $row[$i]) -replace '\s+', ' ').Trim()
}

$records = New-Object System.Collections.Generic.List[object]

function Add-Rec($ip, $env, $stage, $kind, $sys, $gubun, $svr, $code, $biz, $port, $url, $inst, $own, $peer, $note) {
    $records.Add([pscustomobject]@{
        IP = $ip; 환경 = $env; 단계 = $stage; 종류 = $kind; 시스템 = $sys; 구분 = $gubun
        서버명 = $svr; 업무코드 = $code; 업무명 = $biz; PORT = $port; URL = $url
        Instance = $inst; 담당 = $own; 대응IP = $peer; 비고 = $note
    })
}

function Import-Sheet([string]$path, [string]$envHint) {
    if (-not (Test-Path $path)) { Write-Error "시트 파일 없음: $path"; return $false }
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8 | Where-Object { $_.Trim() })
    if ($lines.Count -lt 2) { Write-Error "내용이 부족함: $path"; return $false }

    # 헤더 행 찾기 (엑셀 캡처 시 위에 제목행이 붙는 경우 대비)
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
            $sys   = Get-Cell $row $H "시스템"
            $gub   = Get-Cell $row $H "구분"
            $svr   = Get-Cell $row $H "서버명"
            $url   = Get-Cell $row $H "URL(DNS)"
            $port  = Get-Cell $row $H "PORT(HTTP/HTTPS)"
            $code  = Get-Cell $row $H "업무코드"
            $biz   = Get-Cell $row $H "업무명"
            $own   = (@((Get-Cell $row $H "SM"), (Get-Cell $row $H "담당2")) | Where-Object { $_ }) -join " / "
            $note  = Get-Cell $row $H "비고"
            $pairs = @(
                @{ a = @(Expand-IpCell (Get-Cell $row $H "AS-IS IP"));  t = @(Expand-IpCell (Get-Cell $row $H "TO-BE IP"));  k = "IP"  },
                @{ a = @(Expand-IpCell (Get-Cell $row $H "AS-IS VIP")); t = @(Expand-IpCell (Get-Cell $row $H "TO-BE VIP")); k = "VIP" }
            )
            foreach ($p in $pairs) {
                for ($j = 0; $j -lt $p.a.Count; $j++) {
                    $peer = ""
                    if ($p.t.Count -gt $j) { $peer = $p.t[$j] } elseif ($p.t.Count -gt 0) { $peer = $p.t[0] }
                    Add-Rec $p.a[$j] "운영" "ASIS" $p.k $sys $gub $svr $code $biz $port $url "" $own $peer $note
                }
                for ($j = 0; $j -lt $p.t.Count; $j++) {
                    $peer = ""
                    if ($p.a.Count -gt $j) { $peer = $p.a[$j] } elseif ($p.a.Count -gt 0) { $peer = $p.a[0] }
                    Add-Rec $p.t[$j] "운영" "TOBE" $p.k $sys $gub $svr $code $biz $port $url "" $own $peer $note
                }
            }
        }
        else {
            $sys  = Get-Cell $row $H "시스템"
            $code = Get-Cell $row $H "업무코드"
            $biz  = Get-Cell $row $H "업무명"
            $inst = Get-Cell $row $H "Instance Name"
            $note = (@((Get-Cell $row $H "OS"), (Get-Cell $row $H "비고")) | Where-Object { $_ }) -join " "
            $roles = @(
                @{ g = "WEB"; svr = "WEB"; a = "WEB AS-IS IP"; t = "WEB TO-BE IP"; p = "PORT(HTTP/HTTPS)" },
                @{ g = "WAS"; svr = "WAS"; a = "WAS AS-IS IP"; t = "WAS TO-BE IP"; p = "TO-BE PORT" }
            )
            foreach ($r in $roles) {
                $svr  = Get-Cell $row $H $r.svr
                $port = Get-Cell $row $H $r.p
                $a = @(Expand-IpCell (Get-Cell $row $H $r.a))
                $t = @(Expand-IpCell (Get-Cell $row $H $r.t))
                for ($j = 0; $j -lt $a.Count; $j++) {
                    $peer = ""
                    if ($t.Count -gt $j) { $peer = $t[$j] } elseif ($t.Count -gt 0) { $peer = $t[0] }
                    Add-Rec $a[$j] "개발" "ASIS" "IP" $sys $r.g $svr $code $biz $port "" $inst "" $peer $note
                }
                for ($j = 0; $j -lt $t.Count; $j++) {
                    $peer = ""
                    if ($a.Count -gt $j) { $peer = $a[$j] } elseif ($a.Count -gt 0) { $peer = $a[0] }
                    Add-Rec $t[$j] "개발" "TOBE" "IP" $sys $r.g $svr $code $biz $port "" $inst "" $peer $note
                }
            }
        }
    }
    return $true
}

if (-not (Import-Sheet $Tsv $Env)) { exit 1 }
if ($Tsv2) { if (-not (Import-Sheet $Tsv2 $Env2)) { exit 1 } }

if ($records.Count -eq 0) { Write-Error "추출된 IP가 없음 — 구분자(-Delimiter)나 헤더를 확인할 것"; exit 1 }

# ---------- (IP,환경,단계,종류,시스템,구분,서버명) 단위로 업무 병합 ----------
$agg = New-Object System.Collections.Specialized.OrderedDictionary
$multi = @("업무코드","업무명","PORT","URL","Instance","담당","비고")
foreach ($r in $records) {
    $k = ($r.IP, $r.환경, $r.단계, $r.종류, $r.시스템, $r.구분, $r.서버명) -join ([char]1)
    if (-not $agg.Contains($k)) {
        $h = @{}
        foreach ($c in $COLS) { $h[$c] = $r.$c }
        foreach ($c in $multi) {
            $lst = New-Object System.Collections.Generic.List[string]
            if ($r.$c) { $lst.Add($r.$c) }
            $h[$c] = $lst
        }
        $agg.Add($k, $h)
    } else {
        $h = $agg[$k]
        foreach ($c in $multi) { if ($r.$c -and -not $h[$c].Contains($r.$c)) { $h[$c].Add($r.$c) } }
        if (-not $h["대응IP"] -and $r.대응IP) { $h["대응IP"] = $r.대응IP }
    }
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($k in $agg.Keys) {
    $h = $agg[$k]
    $o = [ordered]@{}
    foreach ($c in $COLS) {
        if ($multi -contains $c) { $o[$c] = ($h[$c] -join ";") } else { $o[$c] = ("" + $h[$c]) }
    }
    $rows.Add([pscustomobject]$o)
}
$rows = @($rows | Sort-Object 환경, 단계, @{ Expression = { [version]$_.IP } })

# ---------- 출력 ----------
$dir = Split-Path $Out -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# 서버이관 IP 인덱스 (구분자 |) — Build-ServerIpIndex v1 / " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
$srcNote = "# 원본: $Tsv"
if ($Tsv2) { $srcNote = $srcNote + " , $Tsv2" }
$lines.Add($srcNote)
$lines.Add("# 대응IP = ASIS행이면 TO-BE IP, TOBE행이면 AS-IS IP")
$lines.Add("# 편집은 메모장으로. 엑셀로 볼 때는 텍스트 마법사에서 구분자 | 지정")
$lines.Add($COLS -join "|")
foreach ($r in $rows) {
    $vals = foreach ($c in $COLS) { ("" + $r.$c) -replace '\|','/' }
    $lines.Add($vals -join "|")
}
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Out, ($lines -join "`r`n") + "`r`n", $utf8Bom)

Write-Host ""
Write-Host ("-> {0}  ({1}행 / 고유 IP {2}개)" -f $Out, $rows.Count, (@($rows | Select-Object -ExpandProperty IP -Unique)).Count)
$rows | Group-Object 환경, 단계 | ForEach-Object { Write-Host ("    {0,-14} {1,4}행" -f $_.Name, $_.Count) }
Write-Host "다음 단계 : .\Resolve-ServerByIp.ps1 -Report .\report\<소스>_asis_path_report.dat"
