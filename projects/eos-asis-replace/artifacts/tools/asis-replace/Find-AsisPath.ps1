# ===========================================================================
# [표준 헤더] Find-AsisPath.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1  전수조사
#   역할 : AS-IS 하드코딩 경로(로컬/NAS/UNC)·IP·포트·도메인을
#          텍스트·class·아카이브 전부에서 찾아 리포트
#   입력 : -Root 소스 폴더 (또는 -RootList 목록 파일)
#   출력 : report\<소스명>_asis_path_report.dat
#   선행 : 없음 — 소스 1건의 첫 작업
#   상태 : 현행 v9.1
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Find-AsisPath.ps1 (v9.1)
#
# ── Kind (무엇을 찾을지) — 지정 안 하면 path,unc ─────────────────────
#   -Kind path    : 드라이브 경로  d:\eos, W:/data, Z:\\share (java 리터럴 포함)
#                   대상 드라이브는 -Drives 로 제한 (기본 * = A-Z 전부)
#   -Kind unc     : NAS/네트워크 경로  \\nas\share, \\192.168.1.50\data,
#                   \\\\nas\\share (java 리터럴), //nas/share
#   -Kind ip      : IPv4
#   -Kind port    : port=8080 / server.port: 9090 / <host|ip>:8080
#   -Kind domain  : xxx.co.kr, api.company.com 등 (-DomainSuffix 로 접미사 조정)
#   -Kind host    : 점 없는 서버명 (WDAAD11 등) — -Hosts 로 직접 지정해야 동작
#   -Kind all     : 위 전부
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind all
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind ip,port,domain
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind path -Drives "d,w,x,y,z,t"
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind host -Hosts WDAAD11,WDDIM11
#
# ── Scope (어디를 뒤질지) — 지정 안 하면 all ─────────────────────────
#   -Scope all   : [기본값] 텍스트 + .class + jar/war/ear/zip 전부 (최초 전수조사)
#   -Scope src   : 텍스트 파일만, 빌드 산출물 폴더 제외 (치환 전후 소스 증적)
#   -Scope build : .class + 아카이브만 (재빌드 후 산출물 검증)
#
# ── 특정 폴더만 조사 ─────────────────────────────────────────────────
#   -Root 에는 아무 폴더나 지정 가능 (exploded 배포 폴더, WEB-INF 등)
#   [주의] WEB-INF만 조사할 때 -Scope src 금지 — classes 폴더가 제외되어
#          WEB-INF\classes 안의 properties/xml을 전부 놓친다. 기본값(all) 사용
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v7  : 레거시 이클립스/Ant 레이아웃 인식 (WebContent, build/classes, exploded WEB-INF)
# v8  : Out 기본 .dat / -RootList 일괄 / -ExcludeFiles / 백업폴더 제외 / 출력폴더 자동생성
# v8.1: Out 기본 report\ + 백업 폴더 자동제외 정규식 수정
# v8.2: 단일 모드 기본 리포트명에도 소스명 접두
# v9  : (1) [추가기능1] NAS/네트워크 폴더 탐지 — Kind=unc (\\nas, \\ip, //host,
#           java 리터럴 \\\\) + Kind=path 의 드라이브를 d 고정에서 -Drives 로 확장
#           (기본 A-Z 전부 → W:\ Z:\ X:\ T:\ Y:\ 등 매핑 드라이브가 자동으로 잡힘)
#       (2) [추가기능2] IP·포트·도메인·서버명 탐지 — Kind=ip,port,domain,host
#       (3) 리포트에 Kind / Target / Value 컬럼 추가
#           Value  = 매칭된 값 그 자체 (기존 Match는 '그 줄 전체'라 매핑표 재료로 쓰기 나빴음)
#           Target = 그 값의 뿌리 (d: / \\nas / 192.168.1.10 / xxx.co.kr / 8080)
#           → Extract-MappingDraft v2 가 이 두 컬럼을 바로 먹는다
#       (4) class/아카이브 매칭도 IgnoreCase — v8.2는 텍스트(Select-String)만
#           대소문자 무시라 W:\ 는 잡고 .class 안의 w:\ 는 놓치는 비대칭이 있었음
#       (5) -Pattern 을 지정하면 v8.2처럼 그 패턴 하나만 사용 (Kind=custom, 하위호환)
#
# v9.1: (1) 레거시 확장자 기본 추가 (jspf/jspx/tag/tld/vm/ftl/xsl/xsd/css/json/cfg/asp/php/
#            vbs/inc/.classpath/.project 등) — v9까지는 16종만 봐서 조용히 놓치던 파일이 있었다
#       (2) -AddExt "jspf,inc,frm" — 목록에 없는 확장자 추가
#       (3) -Inventory — 조사 전에 'Root 안에 어떤 확장자가 몇 개 있고, 그중 뭐가 조사 대상인지'만 출력
#
# 사용법: .\Find-AsisPath.ps1 -Root "C:\src" [-Kind all] [-Scope src] [-Out report.dat]
#         .\Find-AsisPath.ps1 -Root "C:\src" -Inventory            # 먼저 이걸로 사각지대 확인
# ===========================================================================

param(
    [string]$Root    = "C:\pgms",
    [string]$RootList = "",              # 소스 목록 파일 (한 줄에 경로 하나, # 주석). 지정 시 -Root 무시
    [string[]]$Kind  = @("path","unc"),  # v9 기본: 로컬 드라이브 + NAS/UNC
                                         # path|unc|ip|port|domain|host|all (콤마 나열 가능)
    [string]$Drives  = "*",              # Kind=path 대상 드라이브. "*"=A-Z 전부, "d,w,x,y,z" 처럼 제한 가능
    [string[]]$Hosts = @(),              # Kind=host / port 판정용 서버명 (점 없는 이름)
    [string[]]$DomainSuffix = @("co.kr","go.kr","or.kr","re.kr","ne.kr","ac.kr","pe.kr",
                                "kr","com","net","org","edu","gov","mil","io","biz","info",
                                "local","intra","internal","lan","corp"),
    [string]$Pattern = "",               # 지정 시 -Kind 무시하고 이 정규식만 사용 (v8.2 호환)
    [string]$Out     = "report\asis_path_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","bak","backup"),
    [string[]]$ExcludeFiles = @("*.bak","*.back"),   # 파일명 패턴 제외
    [string[]]$AddExt = @(),             # 조사할 확장자 추가. 예: -AddExt "jspf,inc,frm" / -AddExt "*.pc"
                                         #   -AddExt "*" = 확장자 없는 파일까지 전부 (class/jar도 텍스트로 한 번 더 스캔됨)
    [switch]$Inventory,                  # 조사 안 하고, Root 안의 확장자 분포 + 조사대상 여부만 출력
    [ValidateSet("all","src","build")]
    [string]$Scope = "all"
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

# [v9] powershell -File 로 실행하면 배열 파라미터가 문자열 하나로 뭉개진다
#      ("-Kind ip,port,domain" -> @("ip,port,domain")). 콤마/세미콜론을 직접 쪼개
#      콘솔·ISE(배열)와 -File(문자열) 양쪽에서 같게 동작시킨다.
function Split-ListArg([string[]]$v) {
    $out = @()
    foreach ($e in $v) {
        if ($null -eq $e) { continue }
        foreach ($p in ($e -split '[,;]')) { $t = $p.Trim(); if ($t) { $out += $t } }
    }
    return ,$out
}
$Kind         = Split-ListArg $Kind
$Hosts        = Split-ListArg $Hosts
$DomainSuffix = Split-ListArg $DomainSuffix
$ExcludeDirs  = Split-ListArg $ExcludeDirs
$ExcludeFiles = Split-ListArg $ExcludeFiles
$AddExt       = Split-ListArg $AddExt

$KindAllowed = @("path","unc","ip","port","domain","host","all")
foreach ($k in $Kind) {
    if ($KindAllowed -notcontains $k) {
        Write-Error "-Kind 값이 잘못됨: '$k' (가능: $($KindAllowed -join ', '))"; exit 1
    }
}

# 검색 범위 결정
switch ($Scope) {
    "src"   { $doText = $true;  $doClass = $false; $doArc = $false
              $ExcludeDirs += @("target","bin","build","classes","dist") }
    "build" { $doText = $false; $doClass = $true;  $doArc = $true }
    default { $doText = $true;  $doClass = $true;  $doArc = $true }
}

# v9.1: 레거시 소스 확장자 추가 (jspf/tld/vm/xsl/eclipse 메타 등)
#       여기 없는 확장자는 '조사 안 된다' — -Inventory 로 먼저 확인하고 -AddExt 로 붙일 것
$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml",
             "*.jspf","*.jspx","*.tag","*.tagx","*.tld","*.vm","*.ftl","*.tpl","*.inc",
             "*.xsl","*.xslt","*.xsd","*.dtd","*.css","*.json","*.cfg","*.config","*.policy",
             "*.asp","*.php","*.vbs","*.reg","*.mf","*.classpath","*.project","*.prefs")
if ($AddExt.Count -gt 0) {
    $textExt += ($AddExt | ForEach-Object {
        $e = $_.Trim()
        if ($e -eq "*") { "*" }                                   # 모든 파일 (확장자 없는 파일 포함)
        elseif ($e -notlike "*.*") { "*." + $e.TrimStart('*','.') }
        elseif ($e.StartsWith(".")) { "*" + $e }
        else { $e }
    })
    $textExt = $textExt | Select-Object -Unique
}
$binExt  = @("*.class")
$arcExt  = @("*.jar","*.war","*.ear","*.zip")
$arcRegex = '\.(jar|war|ear|zip)$'

# ===========================================================================
# 탐지 패턴 조립 (v9)
#   SEG = 경로 세그먼트 한 글자 (따옴표·공백·괄호·콤마에서 끊는다)
#   SEP = 경로 구분자 — \ 또는 \\(java 리터럴) 또는 /
# ===========================================================================
# 제어문자(\x00-\x1F,\x7F)를 반드시 뺀다 — .class 상수풀은 길이바이트가 구분자라
# 이걸 허용하면 한 매치가 다음 상수까지 통째로 삼켜 UNC 항목을 놓친다 (v9 개발 중 실측)
# = ( [ { 도 뺀다 (properties의 key=value, 코드의 괄호에서 끊기게)
$SEG = '[^\s"''<>|*?:,;=(){}\[\]\\/\x00-\x1F\x7F]'
$SEP = '(?:\\{1,2}|/)'
$KindNames = @("unc","path","ip","domain","host","port")

function Get-DriveClass([string]$drives) {
    if (-not $drives -or $drives.Trim() -eq "*") { return "A-Za-z" }
    $letters = @()
    foreach ($d in ($drives -split '[,\s;]+')) {
        $t = $d.Trim().TrimEnd(':')
        if ($t) { $letters += $t.Substring(0,1).ToLower() }
    }
    $letters = $letters | Select-Object -Unique
    if (-not $letters) { return "A-Za-z" }
    return (($letters | ForEach-Object { $_ + $_.ToUpper() }) -join '')
}

function New-KindPattern([string[]]$kinds) {
    $alts = New-Object System.Collections.Generic.List[string]

    $hostAlt = ""
    if ($Hosts.Count -gt 0) {
        $hostAlt = (($Hosts | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|')
    }

    # 1) UNC / NAS  — \\nas\share, \\192.168.1.50\data, \\\\nas\\share(java), //nas/share
    if ($kinds -contains "unc") {
        $alts.Add('(?<unc>(?<![\w:])\\{2,4}(?![\\/])[A-Za-z0-9][\w.\-]*(?:' + $SEP + $SEG + '*)*)')
        # //host/share — 앞에 : 가 오면(http://) 제외, 공유명이 있어야만 인정(주석 //foo 오탐 방지)
        $alts.Add('(?<unc>(?<![\w:/])//(?![/])[A-Za-z0-9][\w.\-]*(?:/' + $SEG + '*)+)')
    }
    # 2) 드라이브 경로 — d:\eos, W:/data, Z:\\share
    if ($kinds -contains "path") {
        $dc = Get-DriveClass $Drives
        $alts.Add('(?<path>(?<![A-Za-z0-9])[' + $dc + ']:(?=' + $SEP + ')(?:' + $SEP + $SEG + '*)+)')
    }
    # 3) IPv4
    if ($kinds -contains "ip") {
        $alts.Add('(?<ip>(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.]))')
    }
    # 4) 도메인 — 접미사가 끝에 와야 매칭 (java 패키지 com.foo.Bar 오탐 방지)
    if ($kinds -contains "domain") {
        $sfx = (($DomainSuffix | Where-Object { $_ } | Sort-Object { $_.Length } -Descending |
                 ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|')
        # 앞 경계에 / \ 를 넣지 않는다 — http://host, \\nas\host 안의 호스트도 잡아야 한다
        # (path/unc Kind가 켜져 있으면 경로 토큰이 먼저 통째로 소비되므로 파일명 오탐은 나지 않는다)
        $alts.Add('(?<domain>(?<![\w.\-@])(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+(?:' +
                  $sfx + ')(?!\.?[A-Za-z0-9]))')
    }
    # 5) 서버명 직접 지정
    if ($kinds -contains "host") {
        if ($hostAlt) { $alts.Add('(?<host>(?<![\w.\-])(?:' + $hostAlt + ')(?![\w\-]))') }
        elseif ($script:HostExplicit) {
            Write-Warning "-Kind host 는 -Hosts 로 서버명을 줘야 동작한다 (예: -Hosts WDAAD11,WDDIM11)" }
    }
    # 6) 포트 — ①키워드형 port=8080 / server.port: 9090  ②호스트뒤 :8080
    if ($kinds -contains "port") {
        $alts.Add('(?<port>[A-Za-z0-9_.\-]{0,20}port\s*[=:]\s*\d{1,5}(?!\d))')
        $lb = '(?:\d{1,3}\.){3}\d{1,3}|localhost|[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)+'
        if ($hostAlt) { $lb = $lb + '|' + $hostAlt }
        # 가변길이 lookbehind — .NET 정규식만 됨(PS 5.1/7 모두 OK). 시각 12:30 등은 걸리지 않는다
        $alts.Add('(?<port>(?<=' + $lb + '):\d{2,5}(?!\d))')
    }

    if ($alts.Count -eq 0) { Write-Error "탐지할 Kind가 없다"; exit 1 }
    return ($alts -join '|')
}

if ($Pattern) {
    $kinds = @("custom")
    $detectPattern = $Pattern
} else {
    $script:HostExplicit = ($Kind -contains "host")   # -Kind all 일 땐 경고 안 냄
    $kinds = if ($Kind -contains "all") { $KindNames } else { $Kind }
    $detectPattern = New-KindPattern $kinds
}
$rxDetect = New-Object System.Text.RegularExpressions.Regex(
    $detectPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-MatchKind([System.Text.RegularExpressions.Match]$m) {
    foreach ($k in $KindNames) { if ($m.Groups[$k].Success) { return $k } }
    return "custom"
}

# Target = 값의 뿌리. 요약·매핑표 초안에서 이 단위로 묶는다
function Get-Target([string]$kind, [string]$value) {
    switch ($kind) {
        "path"   { if ($value.Length -ge 2) { return $value.Substring(0,2).ToLower() } else { return $value } }
        "unc"    { $h = [regex]::Match($value, '^[\\/]+([A-Za-z0-9][\w.\-]*)')
                   if ($h.Success) { return '\\' + $h.Groups[1].Value.ToLower() } else { return $value } }
        "ip"     { return $value }
        "domain" { return $value.ToLower() }
        "host"   { return $value }
        "port"   { $d = [regex]::Match($value, '(\d{1,5})\s*$')
                   if ($d.Success) { return $d.Groups[1].Value } else { return $value } }
        default  { return "" }
    }
}

$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/][^\\/]*_backup_(path|ip)_') { return $true }   # <이름>_backup_path_* 자동 제외
    $leaf = Split-Path $path -Leaf
    foreach ($pat in $ExcludeFiles) { if ($leaf -like $pat) { return $true } }
    return $false
}

function Get-RelPath([string]$path) {
    if ($path.StartsWith($script:RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($script:RootFull.Length).TrimStart('\')
    }
    return $path
}

function Get-Category([string]$relPath, [string]$entry) {
    # 파일경로 + 아카이브 엔트리를 합쳐 판별 (exploded 배포의 WEB-INF도 잡힘)
    $p = ($relPath + "/" + $entry) -replace '\\','/'
    if ($p -match 'WEB-INF/lib')           { return "WEB-INF/lib" }
    if ($p -match 'WEB-INF/classes')       { return "WEB-INF/classes" }
    if ($p -match '(^|/)src/main/resources(/|$)') { return "src/main/resources" }
    if ($p -match '(^|/)src/main/java(/|$)')      { return "src/main/java" }
    if ($p -match '(^|/)src/main/webapp(/|$)')    { return "src/main/webapp" }
    if ($p -match '(^|/)(WebContent|WebRoot|webRoot|webapp|web)(/|$)') { return "WebContent" }
    if ($p -match '(^|/)src(/|$)')         { return "src" }
    if ($p -match '(^|/)resources?(/|$)')  { return "resources" }
    if ($p -match '(^|/)(conf|config|properties)(/|$)') { return "config" }
    if ($p -match '(^|/)sql(/|$)')         { return "sql" }
    if ($p -match '(^|/)target/classes(/|$)') { return "target/classes" }
    if ($p -match '(^|/)target(/|$)')      { return "target" }
    if ($p -match '(^|/)build/classes(/|$)') { return "build/classes" }
    if ($p -match '(^|/)build(/|$)')       { return "build" }
    if ($p -match '(^|/)bin(/|$)')         { return "bin" }
    if ($p -match '(^|/)classes(/|$)')     { return "classes" }
    if ($p -match '(^|/)lib(/|$)')         { return "lib" }
    if ($p -match '(^|/)WEB-INF(/|$)')     { return "WEB-INF" }
    $first = ($relPath -split '[\\/]')[0]
    if ($first -and $first -notmatch '\.') { return $first }
    return "(root)"
}

function Get-Ext([string]$file, [string]$entry) {
    $name = if ($entry) { $entry } else { $file }
    $ext = [System.IO.Path]::GetExtension($name)
    if ($ext) { return $ext.TrimStart('.').ToLower() } else { return "" }
}

function Get-Context([string]$text, [int]$idx) {
    $s = [Math]::Max(0, $idx - 40)
    $len = [Math]::Min(160, $text.Length - $s)
    return ($text.Substring($s, $len) -replace '[^\x20-\x7E]', '.')
}

function Get-Action([string]$foundIn) {
    switch ($foundIn) {
        "FILE"  { return "직접수정" }
        "CLASS" { return "재빌드(소스수정 후)" }
        default { return "재패키징(재배포)" }
    }
}

function Add-Result([string]$foundIn, [string]$container, [string]$file, [string]$entry,
                    [string]$line, [string]$kind, [string]$value, [string]$match) {
    $rel = Get-RelPath $file
    $relDir = Split-Path $rel -Parent
    $script:results.Add([pscustomobject]@{
        FoundIn   = $foundIn
        Kind      = $kind
        Action    = Get-Action $foundIn
        Container = $container
        Category  = Get-Category $rel $entry
        Ext       = Get-Ext $file $entry
        RelPath   = $relDir
        File      = $file
        Entry     = $entry
        Line      = $line
        Target    = (Get-Target $kind $value)
        Value     = $value
        Match     = $match
    })
}

# 중첩 아카이브 재귀 검색
function Search-Archive([System.IO.Stream]$stream, [string]$file, [string]$containerChain) {
    $inner = ($containerChain -split ' > ')[-1]
    $typeLabel = ([System.IO.Path]::GetExtension($inner)).TrimStart('.').ToUpper()
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
        foreach ($e in $zip.Entries) {
            if ($e.Length -eq 0 -or $e.Length -gt 50MB) { continue }
            if ($e.FullName -match $arcRegex) {
                $ms = New-Object System.IO.MemoryStream
                $es = $e.Open(); $es.CopyTo($ms); $es.Close()
                $ms.Position = 0
                Search-Archive $ms $file ($containerChain + " > " + $e.FullName)
                $ms.Dispose()
            }
            elseif ($e.FullName -match '\.(class|properties|xml|txt|conf|ini|sql|js|jsp|html|htm|yml|yaml|MF)$') {
                $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::ASCII)
                $content = $sr.ReadToEnd(); $sr.Close()
                foreach ($m in $rxDetect.Matches($content)) {
                    Add-Result $typeLabel $containerChain $file $e.FullName "" `
                               (Get-MatchKind $m) $m.Value (Get-Context $content $m.Index)
                }
            }
        }
        $zip.Dispose()
    } catch { Write-Warning ("아카이브 처리 실패: {0} ({1})" -f $file, $containerChain) }
}

# ---------- 소스 1건 조사 ----------
function Invoke-Scan([string]$scanRoot, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $script:results = New-Object System.Collections.Generic.List[object]

    # 1) 텍스트 파일 — Select-String 이 인코딩 판정과 줄번호를 처리한다
    if ($doText) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $textExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      Select-String -Pattern $detectPattern -AllMatches -ErrorAction SilentlyContinue |
      ForEach-Object {
        $line = ($_.Line.Trim() -replace '\s+', ' ')
        $line = $line.Substring(0, [Math]::Min(200, $line.Length))
        $path = $_.Path; $ln = $_.LineNumber
        foreach ($m in $_.Matches) {
            Add-Result "FILE" "" $path "" $ln (Get-MatchKind $m) $m.Value $line
        }
      }
    }

    # 2) .class
    if ($doClass) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $binExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      ForEach-Object {
        $raw = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($_.FullName))
        foreach ($m in $rxDetect.Matches($raw)) {
            Add-Result "CLASS" "" $_.FullName "" "" (Get-MatchKind $m) $m.Value (Get-Context $raw $m.Index)
        }
      }
    }

    # 3) jar/war/ear/zip (중첩 포함)
    if ($doArc) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $arcExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      ForEach-Object {
        $fs = [System.IO.File]::OpenRead($_.FullName)
        Search-Archive $fs $_.FullName $_.Name
        $fs.Dispose()
      }
    }

    # 출력 폴더 자동 생성
    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $script:results | Sort-Object Kind, FoundIn, Container, Category, Ext, File |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot]"
    Write-Host "  총 $($script:results.Count)건 검출 -> $outFile"
    Write-Host "  == Kind별 (무엇이) =="
    $script:results | Group-Object Kind | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    Write-Host "  == Target별 (뿌리: 드라이브/서버/IP/도메인/포트) =="
    $script:results | Where-Object { $_.Target } | Group-Object Target | Sort-Object Count -Descending |
      Select-Object -First 30 |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    Write-Host "  == FoundIn별 (발견 위치) =="
    $script:results | Group-Object FoundIn | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    $inArc = $script:results | Where-Object { $_.Container }
    if ($inArc) {
        Write-Host "  == Container별 (아카이브 내부 매칭) =="
        $inArc | Group-Object Container | Sort-Object Count -Descending |
          ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    }
    Write-Host "  == 위치(Category)별 =="
    $script:results | Group-Object Category | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }

    return $script:results.Count
}

# ---------- 확장자 인벤토리 (v9.1) ----------
# "레거시 소스에 뭐가 들어 있는데, 그중 뭐가 조사 대상인가"를 먼저 보는 모드.
# 조사는 하지 않는다. 미조사 확장자가 나오면 -AddExt 로 붙여서 다시 돌린다.
function Invoke-Inventory([string]$scanRoot, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $cov = @{}
    foreach ($e in $textExt) { $cov[$e.TrimStart('*','.').ToLower()] = "텍스트" }
    foreach ($e in $binExt)  { $cov[$e.TrimStart('*','.').ToLower()] = "class" }
    foreach ($e in $arcExt)  { $cov[$e.TrimStart('*','.').ToLower()] = "아카이브" }

    $files = Get-ChildItem -Path $scanRoot -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { -not (Test-Excluded $_.FullName) }
    $rows = New-Object System.Collections.Generic.List[object]
    $files | Group-Object { $x = $_.Extension.TrimStart('.').ToLower(); if ($x) { $x } else { "(확장자없음)" } } |
      ForEach-Object {
        $ext = $_.Name
        $hit = $cov[$ext]
        $rows.Add([pscustomobject]@{
            Ext      = $ext
            Count    = $_.Count
            SizeKB   = [int](($_.Group | Measure-Object Length -Sum).Sum / 1KB)
            Scanned  = if ($hit) { "O" } else { "X" }
            How      = if ($hit) { $hit } else { "미조사 — 필요하면 -AddExt $ext" }
            Sample   = (Get-RelPath $_.Group[0].FullName)
        })
      }

    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }
    $rows | Sort-Object Scanned, @{Expression="Count";Descending=$true} |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot] 파일 $($files.Count)개 / 확장자 $($rows.Count)종 -> $outFile"
    Write-Host "  == 미조사 확장자 (필요하면 -AddExt 로 추가) =="
    $miss = $rows | Where-Object { $_.Scanned -eq "X" } | Sort-Object Count -Descending
    if ($miss) { $miss | Select-Object -First 25 |
        ForEach-Object { Write-Host ("    {0,6}개  .{1,-12} 예: {2}" -f $_.Count, $_.Ext, $_.Sample) } }
    else { Write-Host "    없음 — 전부 조사 대상" }
    Write-Host "  == 조사 대상 확장자 =="
    $rows | Where-Object { $_.Scanned -eq "O" } | Sort-Object Count -Descending | Select-Object -First 25 |
      ForEach-Object { Write-Host ("    {0,6}개  .{1,-12} ({2})" -f $_.Count, $_.Ext, $_.How) }
    return $rows.Count
}

# ---------- 실행 ----------
if ($doArc) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

$scopeDesc = @{
    all   = "텍스트 + CLASS + 아카이브 전부 (최초 전수조사)"
    src   = "텍스트만, 빌드산출물 폴더 제외 (소스 증적)"
    build = "CLASS + 아카이브만 (재빌드 후 검증)"
}
Write-Host "===== Find-AsisPath v9.1 (Scope=$Scope) ====="
Write-Host "검색 범위: $($scopeDesc[$Scope])"
$kindDesc = ($kinds -join ', ')
if ($kinds -contains 'path') { $kindDesc = $kindDesc + '  (Drives=' + $Drives + ')' }
Write-Host "탐지 종류: $kindDesc"
if ($Hosts.Count -gt 0) { Write-Host "서버명    : $($Hosts -join ', ')" }
Write-Host "제외 폴더: $($ExcludeDirs -join ', ')"
Write-Host "제외 파일: $($ExcludeFiles -join ', ')"

if ($Inventory) {
    Write-Host "[Inventory 모드] 조사는 하지 않는다 — 확장자 분포와 조사대상 여부만 본다"
    $invRoots = @()
    if ($RootList) {
        if (-not (Test-Path $RootList)) { Write-Error "소스 목록 파일 없음: $RootList"; exit 1 }
        $invRoots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -and -not $_.StartsWith("#") }
    } else { $invRoots = @($Root) }
    foreach ($r in $invRoots) {
        if (-not (Test-Path $r)) { Write-Warning "소스 없음, 건너뜀: $r"; continue }
        $leaf = Split-Path ((Resolve-Path $r).Path.TrimEnd('\')) -Leaf
        $outDir = Split-Path $Out -Parent
        $invOut = if ($outDir) { Join-Path $outDir ($leaf + "_ext_inventory.dat") } else { $leaf + "_ext_inventory.dat" }
        [void](Invoke-Inventory $r $invOut)
    }
    return
}

if ($RootList) {
    if (-not (Test-Path $RootList)) { Write-Error "소스 목록 파일 없음: $RootList"; exit 1 }
    $roots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -and -not $_.StartsWith("#") }
    if (-not $roots) { Write-Error "소스 목록이 비어 있음: $RootList"; exit 1 }

    $outDir  = Split-Path $Out -Parent
    $outName = Split-Path $Out -Leaf
    $summary = New-Object System.Collections.Generic.List[object]
    $usedNames = @{}

    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { Write-Warning "소스 없음, 건너뜀: $r"; continue }
        $leaf = Split-Path ((Resolve-Path $r).Path.TrimEnd('\')) -Leaf
        if ($usedNames.ContainsKey($leaf)) {
            $usedNames[$leaf]++
            $tag = "$leaf`_$($usedNames[$leaf])"
            Write-Warning "소스 폴더명 중복: '$leaf' -> 증적은 '$tag'로 저장 ($r)"
            $leaf = $tag
        } else { $usedNames[$leaf] = 1 }
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
        $cnt = Invoke-Scan $r $outFile
        $summary.Add([pscustomobject]@{ Source = $leaf; Count = $cnt; Report = $outFile })
    }

    Write-Host "`n===== 일괄 조사 요약 ($($summary.Count)개 소스) ====="
    $summary | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("  {0,6}건  {1,-30}  -> {2}" -f $_.Count, $_.Source, $_.Report) }
}
else {
    if (-not (Test-Path $Root)) { Write-Error "Root 없음: $Root"; exit 1 }
    $outFile = $Out
    if (-not $PSBoundParameters.ContainsKey('Out')) {
        $leaf = Split-Path ((Resolve-Path $Root).Path.TrimEnd('\')) -Leaf
        $outDir  = Split-Path $Out -Parent
        $outName = Split-Path $Out -Leaf
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
    }
    [void](Invoke-Scan $Root $outFile)
}
