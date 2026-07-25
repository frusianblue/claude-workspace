# Find-AsisPath.ps1 (v8)
# AS-IS 하드코딩 경로 전수 검색 -> 리포트 (.dat)
#
# ── Scope (검색 범위) — 지정 안 하면 all ──────────────────────────────
#   -Scope all   : [기본값] 텍스트 + .class + jar/war/ear/zip 전부
#                  용도: 소스 1건의 최초 전수조사 (전체 그림 + 소스유실 탐지)
#   -Scope src   : 텍스트 파일만. 빌드 산출물 폴더(target/bin/build/classes/dist)는 제외
#                  용도: 치환 직전·직후 소스 증적 (치환 대상만 깔끔하게)
#   -Scope build : .class + 아카이브만 (텍스트 제외)
#                  용도: 재빌드 후 산출물 검증 — 구경로 0건 확인
#
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal"              # Scope 생략 = all
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Scope src
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Scope build -Out portal_after.dat
#
# ── 특정 폴더만 조사 ─────────────────────────────────────────────────
#   -Root(또는 -RootList 파일의 각 줄)에는 아무 폴더나 지정 가능 —
#   그 폴더부터 하위 전체를 재귀 검색하므로, 소스 루트가 아니라
#   exploded 배포 폴더나 WEB-INF 같은 하위 폴더를 직접 지정해도 된다.
#   예) .\Find-AsisPath.ps1 -Root "D:\deploy\portal\WEB-INF"
#   [주의] WEB-INF만 조사할 때 -Scope src를 쓰면 안 됨!
#          src 모드는 'classes' 폴더를 제외하므로 WEB-INF\classes 안의
#          properties/xml을 전부 놓친다 → WEB-INF 조사는 기본값(all) 사용
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v7: 레거시 이클립스/Ant 레이아웃 인식 (WebContent, build/classes, exploded WEB-INF 등)
# v8: (1) Out 기본값 .dat (회사 DRM: csv 자동 암호화 회피)
#     (2) -RootList: 소스 목록 파일로 여러 소스 일괄 조사, 리포트는 소스별 파일로 분리
#     (3) -ExcludeFiles: 파일명 패턴 제외 (기본 *.bak, *.back)
#     (4) -ExcludeDirs 기본값에 bak/backup 및 치환 백업 폴더(_backup_path_*) 추가
#     (5) 출력 폴더 자동 생성 (-Out ".\증적\asis.dat"에서 증적 폴더 없어도 됨)
#
# 예) 단일:  .\Find-AsisPath.ps1 -Root "D:\src\portal" -Scope src -Out portal_src.dat
# 예) 일괄:  .\Find-AsisPath.ps1 -RootList "D:\작업\roots.dat" -Scope all
#            -> 소스별로 <소스폴더명>_asis_path_report.dat 생성 (Out 파일명 앞에 소스명 접두)
# 사용법: .\Find-AsisPath.ps1 -Root "C:\src" [-Pattern "..."] [-Out report.dat] [-ExcludeDirs @(...)] [-ExcludeFiles @(...)]

param(
    [string]$Root    = "C:\pgms",
    [string]$RootList = "",              # 소스 목록 파일 (한 줄에 경로 하나, # 주석). 지정 시 -Root 무시
    [string]$Pattern = "(?<![a-zA-Z0-9])[dD]:[/\\]",
    [string]$Out     = "asis_path_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","bak","backup"),
    [string[]]$ExcludeFiles = @("*.bak","*.back"),   # 파일명 패턴 제외. 예: @("*.bak","*_old.*","*백업*")
    [ValidateSet("all","src","build")]
    [string]$Scope = "all"
)

# 검색 범위 결정
switch ($Scope) {
    "src"   { $doText = $true;  $doClass = $false; $doArc = $false
              $ExcludeDirs += @("target","bin","build","classes","dist") }
    "build" { $doText = $false; $doClass = $true;  $doArc = $true }
    default { $doText = $true;  $doClass = $true;  $doArc = $true }
}

$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml")
$binExt  = @("*.class")
$arcExt  = @("*.jar","*.war","*.ear","*.zip")
$arcRegex = '\.(jar|war|ear|zip)$'

$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/]_backup_(path|ip)_') { return $true }   # Replace 스크립트의 자동 백업 폴더
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
    # -- 배포/패키징 구조 --
    if ($p -match 'WEB-INF/lib')           { return "WEB-INF/lib" }
    if ($p -match 'WEB-INF/classes')       { return "WEB-INF/classes" }
    # -- Maven 표준 --
    if ($p -match '(^|/)src/main/resources(/|$)') { return "src/main/resources" }
    if ($p -match '(^|/)src/main/java(/|$)')      { return "src/main/java" }
    if ($p -match '(^|/)src/main/webapp(/|$)')    { return "src/main/webapp" }
    # -- 레거시 이클립스/Ant 구조 --
    if ($p -match '(^|/)(WebContent|WebRoot|webRoot|webapp|web)(/|$)') { return "WebContent" }
    if ($p -match '(^|/)src(/|$)')         { return "src" }
    if ($p -match '(^|/)resources?(/|$)')  { return "resources" }
    if ($p -match '(^|/)(conf|config|properties)(/|$)') { return "config" }
    if ($p -match '(^|/)sql(/|$)')         { return "sql" }
    # -- 빌드 산출물 --
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

function Add-Result([string]$foundIn, [string]$container, [string]$file, [string]$entry, [string]$line, [string]$match) {
    $rel = Get-RelPath $file
    $relDir = Split-Path $rel -Parent
    $script:results.Add([pscustomobject]@{
        FoundIn   = $foundIn
        Action    = Get-Action $foundIn
        Container = $container
        Category  = Get-Category $rel $entry
        Ext       = Get-Ext $file $entry
        RelPath   = $relDir
        File      = $file
        Entry     = $entry
        Line      = $line
        Match     = $match
    })
}

# 중첩 아카이브 재귀 검색
# $containerChain: "portal.war" 또는 "portal.war > WEB-INF/lib/foo.jar"
function Search-Archive([System.IO.Stream]$stream, [string]$file, [string]$containerChain) {
    # 매칭 Type = 가장 안쪽 아카이브의 확장자 (WAR/JAR/EAR/ZIP)
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
                foreach ($m in [regex]::Matches($content, $Pattern)) {
                    Add-Result $typeLabel $containerChain $file $e.FullName "" (Get-Context $content $m.Index)
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

    # 1) 텍스트 파일
    if ($doText) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $textExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      Select-String -Pattern $Pattern -AllMatches -ErrorAction SilentlyContinue |
      ForEach-Object {
        $line = ($_.Line.Trim() -replace '\s+', ' ')
        Add-Result "FILE" "" $_.Path "" $_.LineNumber $line.Substring(0, [Math]::Min(200, $line.Length))
      }
    }

    # 2) .class
    if ($doClass) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $binExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      ForEach-Object {
        $raw = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($_.FullName))
        foreach ($m in [regex]::Matches($raw, $Pattern)) {
            Add-Result "CLASS" "" $_.FullName "" "" (Get-Context $raw $m.Index)
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

    # 출력 폴더 자동 생성 (예: -Out ".\증적\asis.dat"에서 증적 폴더가 없을 때)
    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $script:results | Sort-Object FoundIn, Container, Category, Ext, File |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot]"
    Write-Host "  총 $($script:results.Count)건 검출 -> $outFile"
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
Write-Host "===== Find-AsisPath v8 (Scope=$Scope) ====="
Write-Host "검색 범위: $($scopeDesc[$Scope])"
Write-Host "제외 폴더: $($ExcludeDirs -join ', ')"
Write-Host "제외 파일: $($ExcludeFiles -join ', ')"

if ($RootList) {
    # 일괄 모드: 목록 파일의 소스마다 조사, 리포트는 소스별로 분리
    if (-not (Test-Path $RootList)) { Write-Error "소스 목록 파일 없음: $RootList"; exit 1 }
    $roots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -and -not $_.StartsWith("#") }
    if (-not $roots) { Write-Error "소스 목록이 비어 있음: $RootList"; exit 1 }

    $outDir  = Split-Path $Out -Parent
    $outName = Split-Path $Out -Leaf
    $summary = New-Object System.Collections.Generic.List[object]
    $usedNames = @{}   # 소스 폴더명 중복 시 증적 덮어쓰기 방지 (web, web_2, web_3 ...)

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
    [void](Invoke-Scan $Root $Out)
}
