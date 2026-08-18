# ===========================================================================
# [표준 헤더] Get-MappedDrives.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-0  사전조사 (Find보다 먼저)
#   역할 : 이 PC/서버에 연결된 네트워크 드라이브(W: Z: X: T: Y:)와 실제 UNC를 수집
#   입력 : 없음 (또는 -FromNetUse 로 저장해 둔 net use 출력 파일)
#   출력 : report\<컴퓨터명>_mapped_drives.dat
#          -EmitMapping 지정 시 mapping\<컴퓨터명>_drive_to_unc.dat (치환 매핑표 초안)
#   선행 : 없음
#   상태 : 현행 v1.1 (2026-08-18 신규 / 같은날 PS5.1 구문·BOM 패치)
#
#   버전이력
#     v1.1 [PATCH 2026-08-18] 보간 $() 안 중첩 따옴표 제거 (PS5.1/ISE)
#                             report 출력도 UTF-8 BOM + CRLF 고정 (Export-Csv 버전차 제거)
#                             mapping 출력 CRLF 고정 (WriteAllLines는 OS 개행을 따라감)
#     v1   신규
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Get-MappedDrives.ps1 (v1.1)
#
# 왜 필요한가
#   소스에 박힌 Z:\... 를 고치려면 'Z:가 실제로 어느 서버의 어느 공유인지'를 알아야 한다.
#   그런데 이건 소스 어디에도 안 적혀 있고, 서버/PC마다 다르다.
#   [실측 함정] 같은 Z: 가 시스템마다 다른 곳을 가리킨다 —
#       모바일DM  Z: = \\nas_digitsign_rdon\digitsign_rdon
#       모바일CSI Z: = \\windbvs1\MCSI_Res$
#   그래서 매핑표는 반드시 '소스별'로 따로 만들어야 한다 (Replace -RootList 의 소스경로,매핑파일).
#
# 사용법
#   .\Get-MappedDrives.ps1                          # 이 PC/서버에서 수집
#   .\Get-MappedDrives.ps1 -EmitMapping             # 치환 매핑표 초안까지 생성
#   .\Get-MappedDrives.ps1 -Tag 모바일DM            # 파일명·비고에 시스템 구분 붙이기
#   .\Get-MappedDrives.ps1 -FromNetUse .\netuse.dat # 다른 서버에서 받아온 net use 출력 파싱
#
#   운영 서버에 스크립트를 못 올리는 경우:
#       서버에서  net use > netuse.txt  (또는 화면 캡처)
#       -> 파일만 받아와서  -FromNetUse netuse.txt
#
# 수집 순서 (되는 것부터)
#   1) Win32_MappedLogicalDisk (WMI/CIM) — 드라이브문자 + ProviderName(UNC). 가장 정확
#   2) net use 파싱
#   3) Get-PSDrive -PSProvider FileSystem 의 DisplayRoot
# ===========================================================================

param(
    [string]$Tag = "",                   # 시스템 구분 (모바일DM 등). 파일명과 비고에 들어간다
    [string]$FromNetUse = "",            # 저장해 둔 net use 출력 파일에서 파싱
    [string]$Out = "",                   # 미지정 시 report\<컴퓨터명>[_<Tag>]_mapped_drives.dat
    [switch]$EmitMapping                 # 치환 매핑표 초안(드라이브 -> UNC)도 생성
)
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$rows = New-Object System.Collections.Generic.List[object]
function Add-Drive([string]$drive, [string]$unc, [string]$src) {
    if (-not $drive -or -not $unc) { return }
    $d = $drive.Trim().TrimEnd('\','/')
    if ($d -notmatch '^[A-Za-z]:$') { return }
    if ($unc -notmatch '^\\\\[^\\]+\\') { return }
    foreach ($r in $rows) { if ($r.Drive -eq $d.ToUpper()) { return } }   # 먼저 잡힌 소스 우선
    $parts  = $unc.TrimStart('\').Split('\')
    $rows.Add([pscustomobject]@{
        Drive  = $d.ToUpper()
        UNC    = $unc.TrimEnd('\')
        Server = $parts[0]
        Share  = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        IsIp   = if ($parts[0] -match '^(?:\d{1,3}\.){3}\d{1,3}$') { "Y" } else { "N" }
        Hidden = if ($parts.Count -gt 1 -and $parts[1].EndsWith('$')) { "Y" } else { "N" }
        Tag    = $Tag
        Source = $src
    })
}

Write-Host "===== Get-MappedDrives v1.1 ====="

if ($FromNetUse) {
    if (-not (Test-Path $FromNetUse)) { Write-Error "파일 없음: $FromNetUse"; exit 1 }
    Write-Host "입력: $FromNetUse (net use 출력 파싱)"
    # 한 줄에 '드라이브문자 + UNC'가 같이 오는 경우와, 줄바꿈으로 갈라진 경우 둘 다 처리
    $lines = Get-Content $FromNetUse
    $pending = ""
    foreach ($ln in $lines) {
        $m = [regex]::Match($ln, '([A-Za-z]:)\s+(\\\\[^\s]+)')
        if ($m.Success) { Add-Drive $m.Groups[1].Value $m.Groups[2].Value "net use"; $pending = ""; continue }
        $d = [regex]::Match($ln, '(?<![\w])([A-Za-z]:)(?:\s|$)')
        if ($d.Success -and $ln -notmatch '\\\\') { $pending = $d.Groups[1].Value; continue }
        if ($pending) {
            $u = [regex]::Match($ln, '(\\\\[^\s]+)')
            if ($u.Success) { Add-Drive $pending $u.Groups[1].Value "net use"; $pending = "" }
        }
    }
}
else {
    # 1) CIM/WMI
    try {
        $cim = $null
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $cim = Get-CimInstance -ClassName Win32_MappedLogicalDisk -ErrorAction Stop
        } else {
            $cim = Get-WmiObject -Class Win32_MappedLogicalDisk -ErrorAction Stop
        }
        foreach ($c in $cim) { Add-Drive $c.DeviceID $c.ProviderName "Win32_MappedLogicalDisk" }
    } catch { Write-Verbose "CIM 수집 실패: $_" }

    # 2) net use
    try {
        $nu = & net use 2>$null
        $pending = ""
        foreach ($ln in $nu) {
            $m = [regex]::Match($ln, '([A-Za-z]:)\s+(\\\\[^\s]+)')
            if ($m.Success) { Add-Drive $m.Groups[1].Value $m.Groups[2].Value "net use"; $pending = ""; continue }
            $d = [regex]::Match($ln, '(?<![\w])([A-Za-z]:)(?:\s|$)')
            if ($d.Success -and $ln -notmatch '\\\\') { $pending = $d.Groups[1].Value; continue }
            if ($pending) {
                $u = [regex]::Match($ln, '(\\\\[^\s]+)')
                if ($u.Success) { Add-Drive $pending $u.Groups[1].Value "net use"; $pending = "" }
            }
        }
    } catch { Write-Verbose "net use 실패: $_" }

    # 3) PSDrive
    try {
        Get-PSDrive -PSProvider FileSystem -ErrorAction Stop |
          Where-Object { $_.DisplayRoot -and $_.DisplayRoot -like '\\*' } |
          ForEach-Object { Add-Drive ($_.Name + ":") $_.DisplayRoot "Get-PSDrive" }
    } catch { Write-Verbose "PSDrive 실패: $_" }
}

if ($rows.Count -eq 0) {
    Write-Warning "연결된 네트워크 드라이브를 못 찾았다."
    Write-Warning "  - 서비스 계정으로 도는 WAS는 대화형 세션과 매핑이 다를 수 있다 (그 계정으로 실행할 것)"
    Write-Warning "  - 스크립트를 못 올리는 서버면:  net use > netuse.txt  후  -FromNetUse netuse.txt"
    exit 1
}

$comp = $env:COMPUTERNAME
if (-not $comp) { $comp = "local" }
$name = if ($Tag) { "$comp`_$Tag" } else { $comp }

if (-not $Out) { $Out = Join-Path "report" ($name + "_mapped_drives.dat") }
$outParent = Split-Path $Out -Parent
if ($outParent -and -not (Test-Path $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }
# [PATCH 2026-08-18 v1.1] Export-Csv -Encoding UTF8 은 PS5.1=BOM有 / PS7.x=BOM無 로 갈린다.
#   7.x로 만든 리포트를 5.1로 다시 읽으면 Tag·Share 한글이 ANSI(MS949)로 읽혀 깨진다.
#   mapping\ 쪽과 동일하게 BOM+CRLF를 명시해 버전 무관하게 고정한다.
$utf8Bom  = New-Object System.Text.UTF8Encoding($true)
$csvLines = $rows | Sort-Object Drive | ConvertTo-Csv -NoTypeInformation
[System.IO.File]::WriteAllText($Out, (($csvLines -join "`r`n") + "`r`n"), $utf8Bom)

Write-Host ""
Write-Host "연결된 네트워크 드라이브 $($rows.Count)개 -> $Out"
$rows | Sort-Object Drive | ForEach-Object {
    $flag = ""
    if ($_.Hidden -eq "Y") { $flag += " [숨김공유]" }
    if ($_.IsIp   -eq "Y") { $flag += " [IP직접]" }
    Write-Host ("  {0}  ->  {1}{2}" -f $_.Drive, $_.UNC, $flag)
}

# Find에 그대로 붙여넣을 인자
$drives = (($rows.Drive | ForEach-Object { $_.TrimEnd(':').ToLower() }) -join ",")
$hosts  = (($rows | Where-Object { $_.IsIp -eq "N" } | ForEach-Object { $_.Server } | Select-Object -Unique) -join ",")
Write-Host ""
Write-Host "== Find-AsisPath 에 붙여넣기 =="
Write-Host "  -Drives `"$drives`""
if ($hosts) { Write-Host "  -Hosts `"$hosts`"   (-Kind host 와 같이)" }

if ($EmitMapping) {
    $mapDir = "mapping"
    if (-not (Test-Path $mapDir)) { New-Item -ItemType Directory -Path $mapDir -Force | Out-Null }
    $mapFile = Join-Path $mapDir ($name + "_drive_to_unc.dat")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 드라이브 -> UNC 정규화 매핑표 초안 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    # [PATCH 2026-08-18 v1.1] 보간 $() 안 중첩 큰따옴표 제거 (PS5.1 / ISE 컬러라이저)
    $tagNote = if ($Tag) { "/ $Tag" } else { "" }
    $lines.Add("# 수집: $comp $tagNote")
    $lines.Add("# ")
    $lines.Add("# [확인 필수] 이 드라이브 문자가 '이 시스템에서만' 이 UNC를 가리킨다는 전제다.")
    $lines.Add("#   같은 Z: 라도 시스템마다 다른 공유일 수 있으므로 소스별로 매핑파일을 분리할 것.")
    $lines.Add("# [주의] 드라이브 루트 매핑이라 해당 문자로 시작하는 모든 경로가 바뀐다. DryRun 리포트를 반드시 검토.")
    $lines.Add("# ")
    $lines.Add("# OldPath,NewPath,비고")
    foreach ($r in ($rows | Sort-Object Drive)) {
        $note = if ($Tag) { "$Tag $($r.Share)" } else { $r.Share }
        $lines.Add(("{0},{1},{2}" -f $r.Drive.ToLower(), $r.UNC, $note))
    }
    # [PATCH 2026-08-18 v1.1] $utf8Bom 은 위에서 이미 만들었다 (중복 생성 제거).
    #   WriteAllLines 는 Environment.NewLine 을 따라가 리눅스/컨테이너에서 LF가 된다 → CRLF 고정.
    [System.IO.File]::WriteAllText($mapFile, (($lines -join "`r`n") + "`r`n"), $utf8Bom)
    Write-Host ""
    Write-Host "-> $mapFile  (Replace-AsisPath.ps1 -Map 으로 바로 사용 가능)"
    Write-Host "   반대 방향(UNC -> 드라이브)로 가려면 두 열을 바꿔서 저장할 것"
}
