# ===========================================================================
# [표준 헤더] Compare-SourceToClass-lev2.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-3  세대 대조 (재컴파일 확정)
#   역할 : 재컴파일 후 javap 역어셈블 비교. 로직 한 줄 수정까지 탐지
#   입력 : -SrcRoot -ClassRoot -LibDir -JdkHome + -Targets/-TargetFile
#   출력 : Compare-SourceToClass-lev2\<프로젝트>_<일시>.dat
#   선행 : ★ lev1으로 추린 의심 대상만. -All 전체는 30개 소스에서 비현실적
#   상태 : 현행 (2026-08-13 -shl 패치 적용)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Compare-SourceToClass-lev2.ps1
# ChangeFlow 소스 ↔ 배포 클래스 대조 — Level 2 (재컴파일 확정 판정)
#
# 원리: 소스를 로컬에서 재컴파일(classpath = 배포 classes + lib\*)한 뒤,
#       새 .class와 배포 .class를 javap -p -c 로 역어셈블 → 정규화 → 비교.
#   - 상수풀 인덱스(#숫자)는 컴파일마다 달라지므로 마스킹
#   - String 리터럴 주석은 별도 비교: "구조는 같은데 리터럴만 다름" = 인코딩 오컴파일 세대
#   - 로직 한 줄 수정까지 잡아내는 확정 판정. 대신 무겁고 컴파일 실패 가능 → lev1로
#     추린 의심 대상만 -TargetFile 로 넘겨서 돌리는 용도.
#
# 사용법:
#   .\Compare-SourceToClass-lev2.ps1 -SrcRoot "D:\ChangeFlow\MAR\src" `
#       -ClassRoot "D:\snap\WEB-INF\classes" -LibDir "D:\snap\WEB-INF\lib" `
#       -JdkHome "C:\Java\jdk1.8.0_xxx" -TargetFile .\targets.txt
#
#   -Targets  smart.web.LogController, smart\web\LogController.java 형식 혼용 가능
#   -TargetFile  한 줄에 하나 (FQCN 또는 상대경로). lev1 dat에서 SrcFile 열 복사해도 됨
#   -All  전체 소스 (오래 걸림 주의)
#   -SaveDiff  차이 나는 클래스의 정규화 덤프/차이를 work 폴더에 저장
#
# 출력: .\Compare-SourceToClass-lev2\<프로젝트명>_<일시>.dat
# Status:
#   동일          : 구조·리터럴 완전 일치 (세대 일치 확정)
#   리터럴만다름  : 바이트코드 구조 동일, String 리터럴만 차이 → 인코딩 오컴파일 세대일 가능성
#   구조다름      : 바이트코드 자체가 다름 → 세대 불일치 확정
#   미배포        : 컴파일 산출 클래스가 배포본에 없음 (신규 or 미배포)
#   컴파일실패    : javac 실패 (Note에 에러 요약) — classpath/의존성 확인
#   소스없음      : 타깃 소스를 못 찾음
param(
    [Parameter(Mandatory=$true)][string]$SrcRoot,
    [Parameter(Mandatory=$true)][string]$ClassRoot,
    [string]$LibDir,
    [Parameter(Mandatory=$true)][string]$JdkHome,
    [string[]]$Targets,
    [string]$TargetFile,
    [switch]$All,
    [string]$ProjectName,
    [string]$OutFile,
    [string]$Delimiter = "|",
    [switch]$SaveDiff
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

# [PATCH 2026-08-13] 상수풀 파싱·깨짐 판정을 공용 모듈로 위임 (로직 4벌 중복 해소)
Import-Module (Join-Path $PSScriptRoot '..\common\ClassParser.psm1') -Force


foreach ($p in @($SrcRoot, $ClassRoot, $JdkHome)) {
    if (-not (Test-Path $p)) { Write-Error "경로 없음: $p"; exit 1 }
}
if ($LibDir -and -not (Test-Path $LibDir)) { Write-Error "경로 없음: $LibDir"; exit 1 }
$SrcRoot   = (Resolve-Path $SrcRoot).Path.TrimEnd('\')
$ClassRoot = (Resolve-Path $ClassRoot).Path.TrimEnd('\')
$javac = Join-Path $JdkHome "bin\javac.exe"
$javap = Join-Path $JdkHome "bin\javap.exe"
foreach ($x in @($javac, $javap)) { if (-not (Test-Path $x)) { Write-Error "JDK 도구 없음: $x"; exit 1 } }

if (-not $All -and -not $Targets -and -not $TargetFile) {
    Write-Error "-Targets / -TargetFile / -All 중 하나는 지정해야 함 (전체는 -All 명시)"; exit 1
}

$scanName = "Compare-SourceToClass-lev2"
if (-not $ProjectName) {
    $generic = @('classes','class','web-inf','lib','target','build','bin','out','dist',
                 'src','main','java','resources','webapp','webcontent','deploy','app','work')
    $parts = $ClassRoot -split '\\'
    for ($k = $parts.Count - 1; $k -ge 0; $k--) {
        $p = $parts[$k]
        if ($p -and ($generic -notcontains $p.ToLower())) { $ProjectName = $p; break }
    }
    if (-not $ProjectName) { $ProjectName = "compare" }
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')

$stamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path (Get-Location).Path $scanName
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (-not $OutFile) { $OutFile = Join-Path $outDir ("{0}_{1}.dat" -f $ProjectName, $stamp) }
$workDir = Join-Path $outDir ("work_{0}_{1}" -f $ProjectName, $stamp)
New-Item -ItemType Directory -Path $workDir | Out-Null

$ms949      = [System.Text.Encoding]::GetEncoding(949)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$srcTgtMap  = @{ 49="1.5"; 50="1.6"; 51="1.7"; 52="1.8" }

function Detect-SourceEncoding([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return "UTF-8" }
    try { $null = $utf8Strict.GetString($b); return "UTF-8" } catch { return "MS949" }
}

# [PATCH 2026-08-13] 자체 구현 제거 — ClassParser 모듈의 Get-ClassMajor 사용.
#   구 구현은 ($b[6] -shl 8) -bor $b[7] 로 [int] 캐스팅이 없었다.
#   major가 256 미만(50/51/52)이라 우연히 맞았을 뿐이고, 8/12에 전면 교체한 패턴이
#   이 파일 한 곳에만 남아 있었다. 모듈로 옮겨 재발을 막는다.

# 소스 인덱스: package 선언 기반 키 → 실제 경로 (레이아웃 무관 매칭)
Write-Host "소스 인덱싱: $SrcRoot"
$pkgRe = [regex]'(?m)^\s*package\s+([\w\.]+)\s*;'
$srcByKey = @{}
Get-ChildItem -Path $SrcRoot -Recurse -Filter *.java -File | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    $head = try { $utf8Strict.GetString($b) } catch { $ms949.GetString($b) }
    $pm = $pkgRe.Match($head)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $key = if ($pm.Success) { $pm.Groups[1].Value + "." + $base } else { $base }
    if (-not $srcByKey.ContainsKey($key)) { $srcByKey[$key] = $_.FullName }
}
Write-Host "  $($srcByKey.Count) 건"

# 타깃 목록 구성 → FQCN 리스트
$targetKeys = New-Object System.Collections.Generic.List[string]
if ($All) { foreach ($k in $srcByKey.Keys) { $targetKeys.Add($k) } }
else {
    $rawList = @()
    if ($Targets)    { $rawList += $Targets }
    if ($TargetFile) { $rawList += (Get-Content $TargetFile | Where-Object { $_.Trim() }) }
    foreach ($t in $rawList) {
        $t = $t.Trim()
        $k = $t -replace '\.java$','' -replace '\.class$',''
        $k = $k -replace '[\\/]', '.'
        # 경로형 입력이면 앞쪽 레이아웃 조각(src.main.java 등)이 붙어 있을 수 있음 → 뒤에서부터 매칭
        if ($srcByKey.ContainsKey($k)) { $targetKeys.Add($k); continue }
        $hit = $srcByKey.Keys | Where-Object { $k.EndsWith($_) -or $_.EndsWith($k) } | Select-Object -First 1
        if ($hit) { $targetKeys.Add($hit) }
        else { $targetKeys.Add("?" + $t) }   # 못 찾음 표시
    }
}
$targetKeys = $targetKeys | Select-Object -Unique
Write-Host "타깃: $($targetKeys.Count) 건"

$cp = $ClassRoot
if ($LibDir) { $cp = "$ClassRoot;$((Resolve-Path $LibDir).Path.TrimEnd('\'))\*" }

# javap 정규화: 인덱스 마스킹(+옵션: 리터럴 마스킹), 리터럴 주석 수집
function Get-JavapNorm([string]$classPath) {
    $raw = & $javap -p -c $classPath 2>&1 | ForEach-Object { [string]$_ }
    $norm = New-Object System.Collections.Generic.List[string]
    $masked = New-Object System.Collections.Generic.List[string]
    $strs = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $raw) {
        if ($ln -match '^Compiled from') { continue }
        $n = ($ln -replace '#\d+', '#').TrimEnd()
        $norm.Add($n)
        if ($n -match '// String (.*)$') {
            $strs.Add($Matches[1])
            $masked.Add(($n -replace '// String .*$', '// String *'))
        } else { $masked.Add($n) }
    }
    return @{ Norm = $norm; Masked = $masked; Strings = $strs }
}

$rows = New-Object System.Collections.Generic.List[object]
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$idx = 0

foreach ($key in $targetKeys) {
    $idx++
    if ($key.StartsWith("?")) {
        $rows.Add([PSCustomObject]@{ SrcFile=$key.Substring(1); ClassFile=""; JDK=""; Status="소스없음"; Note="" })
        continue
    }
    $srcPath = $srcByKey[$key]
    $srcRel  = $srcPath.Substring($SrcRoot.Length).TrimStart('\')
    Write-Host ("[{0}/{1}] {2}" -f $idx, $targetKeys.Count, $key)

    # 배포 클래스 major → -source/-target 결정 (기본 1.8)
    $clsRel = ($key -replace '\.', '\') + ".class"
    $deployed = Join-Path $ClassRoot $clsRel
    $major = if (Test-Path $deployed) { Get-ClassMajor $deployed } else { 52 }
    $sv = if ($srcTgtMap.ContainsKey([int]$major)) { $srcTgtMap[[int]$major] } else { "1.8" }
    $jdkDisp = $sv

    $enc = Detect-SourceEncoding $srcPath
    $safe = ($key -replace '[^\w\.]','_')
    $cOut = Join-Path $workDir "out_$safe"
    New-Item -ItemType Directory -Path $cOut | Out-Null

    $err = & $javac -encoding $enc -nowarn -source $sv -target $sv `
                    -cp $cp -sourcepath '""' -d $cOut $srcPath 2>&1
    $errTxt = ($err | Out-String).Trim()

    $produced = @(Get-ChildItem -Path $cOut -Recurse -Filter *.class -File)
    if ($produced.Count -eq 0) {
        $short = ($errTxt -split "`r?`n" | Select-Object -First 2) -join " / "
        $rows.Add([PSCustomObject]@{ SrcFile=$srcRel; ClassFile=$clsRel; JDK=$jdkDisp; Status="컴파일실패"; Note=$short })
        continue
    }

    foreach ($nc in $produced) {
        $ncRel = $nc.FullName.Substring($cOut.Length).TrimStart('\')
        $dep   = Join-Path $ClassRoot $ncRel
        if (-not (Test-Path $dep)) {
            $rows.Add([PSCustomObject]@{ SrcFile=$srcRel; ClassFile=$ncRel; JDK=$jdkDisp; Status="미배포"; Note="" })
            continue
        }
        $a = Get-JavapNorm $nc.FullName
        $b = Get-JavapNorm $dep

        $structSame = ($a.Masked -join "`n") -eq ($b.Masked -join "`n")
        $fullSame   = ($a.Norm   -join "`n") -eq ($b.Norm   -join "`n")

        if ($fullSame) { $status = "동일"; $note = "" }
        elseif ($structSame) {
            $status = "리터럴만다름"
            $onlyDep = @($b.Strings | Where-Object { $a.Strings -notcontains $_ } | Select-Object -First 3)
            $note = "배포측예: " + (($onlyDep -join " ;; ") -replace "`r?`n","\n")
        }
        else { $status = "구조다름"; $note = "" }

        if ($SaveDiff -and $status -ne "동일") {
            $dDir = Join-Path $workDir "diff"
            if (-not (Test-Path $dDir)) { New-Item -ItemType Directory -Path $dDir | Out-Null }
            $tag = ($ncRel -replace '[\\/]','.') -replace '\.class$',''
            [System.IO.File]::WriteAllLines((Join-Path $dDir "$tag.new.txt"), $a.Norm, $utf8Bom)
            [System.IO.File]::WriteAllLines((Join-Path $dDir "$tag.dep.txt"), $b.Norm, $utf8Bom)
            $cmp = Compare-Object $a.Norm $b.Norm | ForEach-Object {
                $side = if ($_.SideIndicator -eq "<=") { "NEW" } else { "DEP" }
                "[$side] $($_.InputObject)"
            }
            [System.IO.File]::WriteAllLines((Join-Path $dDir "$tag.diff.txt"), $cmp, $utf8Bom)
            $note = ($note + " diff저장").Trim()
        }
        $rows.Add([PSCustomObject]@{ SrcFile=$srcRel; ClassFile=$ncRel; JDK=$jdkDisp; Status=$status; Note=$note })
    }
}

# 저장
$cols = @("SrcFile","ClassFile","JDK","Status","Note")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($cols -join $Delimiter)
foreach ($r in $rows) {
    $vals = $cols | ForEach-Object {
        $v = [string]$r.$_
        $v -replace "`r?`n","\n" -replace [regex]::Escape($Delimiter)," "
    }
    $lines.Add($vals -join $Delimiter)
}
[System.IO.File]::WriteAllLines($OutFile, $lines, $utf8Bom)

Write-Host ""
Write-Host "프로젝트  : $ProjectName"
Write-Host "저장 완료 : $OutFile ($($rows.Count) 건)"
Write-Host "작업 폴더 : $workDir  (산출 클래스/diff — 확인 후 삭제 가능)"
$rows | Group-Object Status | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,-14} {1,6} 건" -f $_.Name, $_.Count)
}
