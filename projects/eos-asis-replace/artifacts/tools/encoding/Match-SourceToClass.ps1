# ===========================================================================
# [표준 헤더] Match-SourceToClass.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-4  대조
#   역할 : Scan-ClassFiles / Scan-JavaSources 결과 dat 2개를 클래스 단위로 대조
#   입력 : -ClassScan, -SrcScan (동반 -literals/-lines 자동 탐색)
#   출력 : Match-SourceToClass\<class>_vs_<src>_<일시>.dat (+ -detail)
#   선행 : ★ 두 스캔 선행. 원본 폴더에서 바로 시작할 땐 lev1을 쓸 것
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Match-SourceToClass.ps1 — [③ 대조 단계]
  Scan-ClassFiles 결과(배포 .class)와 Scan-JavaSources 결과(ChangeFlow .java)를
  클래스 단위로 매칭해서 "재컴파일 대상 / 소스 세대 불일치 / 정상" 을 판정한다.

.USAGE
  .\Match-SourceToClass.ps1 `
      -ClassScan .\Scan-ClassFiles\portal_20260802_132328.dat `
      -SrcScan   .\Scan-JavaSources\MAR_20260802_140000.dat

  → -literals.dat / -lines.dat 는 같은 이름 규칙으로 자동으로 찾아 읽음
  → 현재 위치에 .\Match-SourceToClass\ 폴더 자동 생성
     <클래스프로젝트>_vs_<소스프로젝트>_<일시>.dat        : 클래스별 판정 요약
     <클래스프로젝트>_vs_<소스프로젝트>_<일시>-detail.dat : 리터럴별 검색 상세

  엑셀에서 열기: 파일 → 열기 → 모든 파일 → .dat 선택 → 텍스트 마법사 → 구분기호 "기타" |

.판정 (Status 컬럼)
  정상일치            : 클래스 리터럴 정상 + 전부 소스에서 발견 → 조치 불필요
  정상-리터럴미발견   : 클래스 리터럴은 정상인데 소스에 없음 → 소스가 배포본보다 구버전 의심
  재컴파일(복구가능)  : 클래스 리터럴 깨짐 + 복원값/골격이 소스에 있음 → 소스 UTF-8 변환 후 재컴파일로 복구
  재컴파일(소스확인)  : 클래스 리터럴 깨짐 + 소스에서 못 찾음 → 소스 세대 불일치 or 전부 깨져 검색 불가
  소스없음            : 매칭되는 .java 자체가 없음 → 형상관리 누락 의심
  ASCII만             : 한글 리터럴 없음 → 인코딩 무관
  (별도) 클래스없음   : 한글 있는 소스인데 대응 클래스가 없음 → 미배포 의심

.발견위치 (detail의 FoundIn 컬럼) — 인라이닝 추적
  OWN    : 자기 소스 파일에서 발견
  OTHER  : 다른 소스 파일에서 발견 → static final 인라이닝 (정의 파일 표시됨)
  NOTFOUND / SKELETON부족 : 미발견 / FFFD가 많아 검색 골격이 부족
#>
param(
    [Parameter(Mandatory=$true)][string]$ClassScan,   # Scan-ClassFiles 요약 dat 경로
    [Parameter(Mandatory=$true)][string]$SrcScan,     # Scan-JavaSources 요약 dat 경로
    [string]$ProjectName,
    [string]$OutFile,
    [string]$Delimiter = "|"
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 입력 파일 확인 및 동반 파일(-literals / -lines) 자동 유도
# ---------------------------------------------------------------------------
function Get-Companion([string]$Path, [string]$Suffix) {
    $dir  = [System.IO.Path]::GetDirectoryName((Resolve-Path $Path).Path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [System.IO.Path]::GetExtension($Path)
    return [System.IO.Path]::Combine($dir, $base + $Suffix + $ext)
}
if (-not (Test-Path $ClassScan)) { Write-Error "파일 없음: $ClassScan"; exit 1 }
if (-not (Test-Path $SrcScan))   { Write-Error "파일 없음: $SrcScan";   exit 1 }
$ClassLit = Get-Companion $ClassScan "-literals"
$SrcLines = Get-Companion $SrcScan   "-lines"
if (-not (Test-Path $SrcLines)) { Write-Error "소스 라인 상세 파일 없음: $SrcLines"; exit 1 }
$hasLit = Test-Path $ClassLit
if (-not $hasLit) { Write-Warning "리터럴 상세 파일 없음(한글 리터럴 0건?): $ClassLit" }

# ---------------------------------------------------------------------------
# 출력 경로 자동 결정: .\Match-SourceToClass\<클래스proj>_vs_<소스proj>_<일시>.dat
# ---------------------------------------------------------------------------
$scanName = "Match-SourceToClass"
function Get-ProjFromFile([string]$Path) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($base -match '^(.*)_\d{8}_\d{6}$') { return $Matches[1] }
    return $base
}
if (-not $ProjectName) {
    $ProjectName = "{0}_vs_{1}" -f (Get-ProjFromFile $ClassScan), (Get-ProjFromFile $SrcScan)
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')
if (-not $OutFile) {
    $outDir = Join-Path (Get-Location).Path $scanName
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $OutFile = Join-Path $outDir ("{0}_{1}.dat" -f $ProjectName, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$detailOut = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutFile)),
    [System.IO.Path]::GetFileNameWithoutExtension($OutFile) + "-detail" + [System.IO.Path]::GetExtension($OutFile))

# ---------------------------------------------------------------------------
# dat 파싱 (BOM은 ReadAllLines가 자동 처리)
# 구분자는 파일마다 헤더 행에서 자동 감지 (| , 탭, 쉼표, 세미콜론 지원)
# → 스캔 시 -Delimiter를 뭘로 썼든 상관없이 읽힘
# ---------------------------------------------------------------------------
function Read-Dat([string]$Path, [int]$Cols) {
    $all = [System.IO.File]::ReadAllLines($Path)
    if ($all.Length -lt 1) { Write-Error "빈 파일: $Path"; exit 1 }

    $detected = $null
    foreach ($cand in @("|", "`t", ",", ";")) {
        $h = $all[0] -split [regex]::Escape($cand)
        if ($h.Count -eq $Cols -and $h[0].Trim() -eq "File") { $detected = $cand; break }
    }
    if ($null -eq $detected) {
        Write-Error ("구분자 감지 실패: {0}`n  헤더: {1}`n  기대 컬럼 수: {2} — 파일이 올바른 스캔 결과인지 확인" -f $Path, $all[0], $Cols)
        exit 1
    }

    $rd = [regex]::Escape($detected)
    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -lt $all.Length; $i++) {          # 헤더 스킵
        if (-not $all[$i]) { continue }
        $f = $all[$i] -split $rd, $Cols               # 마지막 컬럼에 구분자 있어도 보존
        if ($f.Count -lt $Cols) { continue }
        $rows.Add($f)
    }
    if ($rows.Count -eq 0) { Write-Error "데이터 0건: $Path — 파일 내용 확인"; exit 1 }
    return , $rows
}

Write-Host "[읽기] 클래스 요약  : $ClassScan"
$clsRows = Read-Dat $ClassScan 7      # File,JDK,Major,Status,Encoding,Broken,Hangul
Write-Host "        -> $($clsRows.Count) 건"
$litRows = @()
if ($hasLit) {
    Write-Host "[읽기] 리터럴 상세  : $ClassLit"
    $litRows = Read-Dat $ClassLit 4   # File,Type,Literal,Restored
    Write-Host "        -> $($litRows.Count) 건"
}
Write-Host "[읽기] 소스 요약    : $SrcScan"
$srcRows = Read-Dat $SrcScan 6        # File,판정,한글라인,FFFD라인,총라인,조치
Write-Host "        -> $($srcRows.Count) 건"
Write-Host "[읽기] 소스 라인    : $SrcLines"
$lineRows = Read-Dat $SrcLines 5      # File,판정,Line,유형,내용
Write-Host "        -> $($lineRows.Count) 건"

# ---------------------------------------------------------------------------
# 인덱스 구성
# ---------------------------------------------------------------------------
function Norm([string]$p) { return $p.Replace('\','/').ToLower() }

# 소스 요약: 정규화 경로 → (원경로, 판정)
$srcMap = @{}
foreach ($r in $srcRows) { $srcMap[(Norm $r[0])] = @{ File = $r[0]; Enc = $r[1] } }

# 소스 라인: 전체 목록 + 파일별 그룹
$allLines = New-Object System.Collections.Generic.List[object]
$linesByFile = @{}
foreach ($r in $lineRows) {
    $k = Norm $r[0]
    $o = [PSCustomObject]@{ File = $r[0]; Key = $k; Line = $r[2]; Content = $r[4] }
    $allLines.Add($o)
    if (-not $linesByFile.ContainsKey($k)) { $linesByFile[$k] = New-Object System.Collections.Generic.List[object] }
    $linesByFile[$k].Add($o)
}

# 클래스 리터럴: 클래스파일별 그룹 (ASCII 전용 등 관심 외 타입 제외)
$litByClass = @{}
foreach ($r in $litRows) {
    $k = $r[0]
    if (-not $litByClass.ContainsKey($k)) { $litByClass[$k] = New-Object System.Collections.Generic.List[object] }
    $litByClass[$k].Add([PSCustomObject]@{ Type = $r[1]; Literal = $r[2]; Restored = $r[3] })
}

# ---------------------------------------------------------------------------
# 클래스 → 소스 매칭:  a\b\Foo$1.class → a/b/foo.java (내부클래스는 외부클래스 소스로)
# ---------------------------------------------------------------------------
$srcKeys = @($srcMap.Keys)
function Find-SourceKey([string]$ClassRel) {
    $j = (Norm $ClassRel) -replace '\.class$', ''
    $j = $j -replace '\$[^/]*$', ''          # 내부 클래스 제거
    $j = "$j.java"
    if ($srcMap.ContainsKey($j)) { return @($j) }
    # 접미사 매칭: 소스 루트/클래스 루트 기준점이 달라도 패키지 경로로 맞춤 (Ordinal: PS5.1 문화권 비교 회피)
    $ord = [System.StringComparison]::Ordinal
    $hits = @($srcKeys | Where-Object { $_.EndsWith($j, $ord) -or $j.EndsWith($_, $ord) })
    if ($hits.Count -gt 0) { return $hits }
    # 최후: 파일명만 매칭
    $fn = [System.IO.Path]::GetFileName($j)
    return @($srcKeys | Where-Object { $_.EndsWith("/$fn", $ord) -or $_ -eq $fn })
}

# ---------------------------------------------------------------------------
# 리터럴 검색: 자기 소스 우선 → 전체 소스. FFFD는 골격 정규식으로.
# ---------------------------------------------------------------------------
function Get-SearchSpec([object]$Lit) {
    switch -Regex ($Lit.Type) {
        '^한글정상$'   { return @{ Mode='plain'; Key=$Lit.Literal } }
        '^깨짐Latin1$' { return @{ Mode='plain'; Key=$Lit.Restored } }
        '^깨짐949이중$'{ return @{ Mode='plain'; Key=$Lit.Restored } }
        '^깨짐FFFD$'   {
            # U+FFFD 연속 구간을 .+ 로 바꾼 골격 정규식
            $parts = $Lit.Literal -split "\uFFFD+"
            $skel  = ($parts | Where-Object { $_ }) -join ""
            if ($skel.Length -lt 3) { return @{ Mode='none'; Key=$skel } }   # 골격 부족 → 검색 불가
            $pattern = ($parts | ForEach-Object { [regex]::Escape($_) }) -join '.+'
            return @{ Mode='regex'; Key=$Lit.Literal; Rx=[regex]$pattern }
        }
        default { return @{ Mode='skip'; Key='' } }
    }
}
function Test-LineHit([object]$Spec, [string]$Content) {
    if ($Spec.Mode -eq 'plain') { return $Content.Contains($Spec.Key) }
    if ($Spec.Mode -eq 'regex') { return $Spec.Rx.IsMatch($Content) }
    return $false
}
function Find-Literal([object]$Spec, [string[]]$OwnKeys) {
    if ($Spec.Mode -eq 'none') { return @{ Where='SKELETON부족'; File=''; Line='' } }
    if ($Spec.Mode -eq 'skip') { return @{ Where='-'; File=''; Line='' } }
    foreach ($ok in $OwnKeys) {
        if ($linesByFile.ContainsKey($ok)) {
            foreach ($l in $linesByFile[$ok]) {
                if (Test-LineHit $Spec $l.Content) { return @{ Where='OWN'; File=$l.File; Line=$l.Line } }
            }
        }
    }
    foreach ($l in $allLines) {
        if ($OwnKeys -contains $l.Key) { continue }
        if (Test-LineHit $Spec $l.Content) { return @{ Where='OTHER'; File=$l.File; Line=$l.Line } }
    }
    return @{ Where='NOTFOUND'; File=''; Line='' }
}

# ---------------------------------------------------------------------------
# 본 처리
# ---------------------------------------------------------------------------
$summary = New-Object System.Collections.Generic.List[object]
$detail  = New-Object System.Collections.Generic.List[object]
$matchedSrcKeys = New-Object System.Collections.Generic.HashSet[string]
$total = $clsRows.Count; $n = 0

foreach ($c in $clsRows) {
    $n++
    if ($n % 100 -eq 0) { Write-Progress -Activity "대조" -Status "$n / $total" -PercentComplete (100*$n/$total) }

    $cFile = $c[0]; $cJdk = $c[1]; $cStatus = $c[3]; $cEnc = $c[4]

    $srcHits = @(Find-SourceKey $cFile)   # @() 필수: 원소 1개면 PS가 문자열로 풀어버림
    foreach ($sk in $srcHits) { [void]$matchedSrcKeys.Add($sk) }
    $srcFile = if ($srcHits.Count -ge 1) { $srcMap[$srcHits[0]].File } else { "" }
    $srcEnc  = if ($srcHits.Count -ge 1) { $srcMap[$srcHits[0]].Enc }  else { "" }
    $ambig   = if ($srcHits.Count -gt 1) { "매칭후보 $($srcHits.Count)개" } else { "" }

    $lits = if ($litByClass.ContainsKey($cFile)) { $litByClass[$cFile] } else { @() }

    $cntOwn = 0; $cntOther = 0; $cntNot = 0; $cntSkel = 0
    foreach ($lit in $lits) {
        $spec = Get-SearchSpec $lit
        $hit  = Find-Literal $spec $srcHits
        switch ($hit.Where) {
            'OWN'          { $cntOwn++ }
            'OTHER'        { $cntOther++ }
            'NOTFOUND'     { $cntNot++ }
            'SKELETON부족' { $cntSkel++ }
        }
        $foundIn = if ($hit.Where -eq 'OTHER') { "OTHER(인라이닝): $($hit.File)" } else { $hit.Where }
        $detail.Add([PSCustomObject]@{
            ClassFile = $cFile; Type = $lit.Type
            SearchKey = $spec.Key
            FoundIn   = $foundIn
            SrcFile   = $hit.File; SrcLine = $hit.Line
        })
    }

    # 클래스 단위 판정
    if ($cStatus -eq "ASCII만") {
        $status = "ASCII만";    $action = "-"
    }
    elseif ($srcHits.Count -eq 0) {
        $status = "소스없음";   $action = "형상관리 누락 의심 — 소스 확보 필요"
    }
    elseif ($cStatus -eq "한글정상") {
        if ($cntNot -eq 0 -and $cntSkel -eq 0) {
            $status = "정상일치";           $action = "-"
        } else {
            $status = "정상-리터럴미발견";  $action = "소스가 배포본보다 구버전 의심 — 확인 필요"
        }
    }
    else {  # 깨짐(FFFD)/깨짐(Latin1)/깨짐(949이중)
        if ($cntNot -eq 0 -and $cntSkel -eq 0) {
            $status = "재컴파일(복구가능)"; $action = "소스 UTF-8 변환 후 참조클래스 포함 일괄 재컴파일"
        } else {
            $status = "재컴파일(소스확인)"; $action = "재컴파일 대상 + 소스 세대/골격 확인 필요"
        }
    }
    if ($cntOther -gt 0) { $action = "$action / 인라이닝 리터럴 ${cntOther}건 → 정의 클래스와 묶어 재컴파일" }

    $summary.Add([PSCustomObject]@{
        ClassFile = $cFile; JDK = $cJdk; ClassStatus = $cStatus; ClassEnc = $cEnc
        SrcFile = $srcFile; SrcEnc = $srcEnc
        일치 = $cntOwn; 인라이닝 = $cntOther; 미발견 = ($cntNot + $cntSkel)
        Status = $status; 조치 = $action; 비고 = $ambig
    })
}
Write-Progress -Activity "대조" -Completed

# 역방향: 한글 있는 소스인데 클래스가 없는 경우 (미배포 의심)
foreach ($k in $srcKeys) {
    if ($matchedSrcKeys.Contains($k)) { continue }
    $s = $srcMap[$k]
    if ($s.Enc -in @("ASCII")) { continue }
    $summary.Add([PSCustomObject]@{
        ClassFile = ""; JDK = ""; ClassStatus = ""; ClassEnc = ""
        SrcFile = $s.File; SrcEnc = $s.Enc
        일치 = ""; 인라이닝 = ""; 미발견 = ""
        Status = "클래스없음"; 조치 = "대응 클래스 미발견 — 미배포 or 클래스 스캔 범위 확인"; 비고 = ""
    })
}

# ---------------------------------------------------------------------------
# 저장 (파이프 구분, UTF-8 BOM) — 자유 텍스트 컬럼은 구분자 제거
# ---------------------------------------------------------------------------
$reDelim = [regex]::Escape($Delimiter)
function Safe([string]$s) { return ($s -replace "`r?`n", "\n" -replace $reDelim, " ") }
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

$statusOrder = @{ "재컴파일(소스확인)"=1; "재컴파일(복구가능)"=2; "정상-리터럴미발견"=3;
                  "소스없음"=4; "클래스없음"=5; "정상일치"=6; "ASCII만"=7 }
$sorted = $summary | Sort-Object @{Expression={ $statusOrder[$_.Status] }}, ClassFile

$l1 = New-Object System.Collections.Generic.List[string]
$l1.Add(("ClassFile","JDK","ClassStatus","ClassEnc","SrcFile","SrcEnc","일치","인라이닝","미발견","Status","조치","비고") -join $Delimiter)
foreach ($r in $sorted) {
    $l1.Add(($r.ClassFile,$r.JDK,$r.ClassStatus,$r.ClassEnc,$r.SrcFile,$r.SrcEnc,
             $r.일치,$r.인라이닝,$r.미발견,$r.Status,(Safe $r.조치),$r.비고) -join $Delimiter)
}
[System.IO.File]::WriteAllLines($OutFile, $l1, $utf8Bom)

$l2 = New-Object System.Collections.Generic.List[string]
$l2.Add(("ClassFile","Type","SearchKey","FoundIn","SrcFile","SrcLine") -join $Delimiter)
foreach ($r in $detail) {
    $l2.Add(($r.ClassFile,$r.Type,(Safe $r.SearchKey),(Safe $r.FoundIn),$r.SrcFile,$r.SrcLine) -join $Delimiter)
}
[System.IO.File]::WriteAllLines($detailOut, $l2, $utf8Bom)

# ---------------------------------------------------------------------------
# 콘솔 요약
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============== 대조 요약 ===============" -ForegroundColor Yellow
$grp = $summary | Group-Object Status | Sort-Object @{Expression={ $statusOrder[$_.Name] }}
foreach ($g in $grp) {
    $color = switch ($g.Name) {
        "재컴파일(소스확인)" { "Red" }
        "재컴파일(복구가능)" { "Yellow" }
        "정상-리터럴미발견"  { "Red" }
        "소스없음"           { "Magenta" }
        "클래스없음"         { "Magenta" }
        default              { "Green" }
    }
    Write-Host ("  {0,-20} : {1,6} 건" -f $g.Name, $g.Count) -ForegroundColor $color
}
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "  프로젝트 : $ProjectName"
Write-Host "  요약     : $OutFile" -ForegroundColor Cyan
Write-Host "  상세     : $detailOut" -ForegroundColor Cyan
Write-Host ""
Write-Host "  * 재컴파일(복구가능) 의 ClassFile 목록 = 일괄 재컴파일 대상 명단" -ForegroundColor Gray
Write-Host "  * 인라이닝 컬럼 > 0 이면 상수 정의 클래스와 반드시 함께 재컴파일" -ForegroundColor Gray
Write-Host "  * 정상-리터럴미발견 / 소스없음 은 소스 세대 확인이 먼저" -ForegroundColor Gray
