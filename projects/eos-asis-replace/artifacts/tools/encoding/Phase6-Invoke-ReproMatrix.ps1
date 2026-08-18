# ===========================================================================
# [표준 헤더] Phase6-Invoke-ReproMatrix.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-0  검출기 검증
#   역할 : 소스 인코딩 x javac 인코딩 4조합을 실제 빌드해 판정 결과 대조
#   입력 : -JavacHome JDK 경로
#   출력 : 조합별 기대 판정 대조표
#   선행 : JDK 8 설치(javac.exe 필요 — JRE 단독 불가). Scan-ClassFiles.ps1이 같은 폴더에 있을 것
#          ★ 전체 착수 시 1회 — 소스별 반복 아님
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 6 — 소스 인코딩 x javac 인코딩 4가지 조합을 실제로 빌드해 재현하고,
            Scan-ClassFiles.ps1 의 판정이 기대값과 맞는지 검증한다.

.DESCRIPTION
  이 단계의 목적은 두 가지다.
    1) 어떤 조합이 현장의 증상과 일치하는지 확인 (원인 특정)
    2) 검출기 자체가 신뢰할 수 있는지 확인 (대조군 검증)

  두 번째가 중요하다. 정상 빌드만 스캔하면 "깨짐 0건"이 진짜인지
  검출기가 고장난 것인지 구분할 수 없다.

.EXAMPLE
  .\Phase6-Invoke-ReproMatrix.ps1 -JavacHome "D:\AppDev\Bin\java_home\jdk-1.8.0"
#>
[CmdletBinding()]
param(
    [string] $JavacHome,                          # 미지정 시 PATH 의 javac 사용
    [string] $WorkDir  = ".\repro-matrix",
    # [PATCH 2026-08-13] 기본값을 '현재 폴더'가 아니라 '이 스크립트가 있는 폴더' 기준으로.
    #   tools\encoding\ 로 분리한 뒤, tools\ 에서 .\encoding\Phase6-...ps1 로 실행하면
    #   .\Scan-ClassFiles.ps1 이 tools\Scan-ClassFiles.ps1 로 해석돼 "스캔 스크립트 없음"이 났다.
    [string] $ScanScript
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = 'Stop'

if (-not $ScanScript) { $ScanScript = Join-Path $PSScriptRoot 'Scan-ClassFiles.ps1' }

$javac = 'javac'
if ($JavacHome) { $javac = Join-Path $JavacHome 'bin\javac.exe' }
if ($JavacHome -and -not (Test-Path $javac)) { throw "javac 없음: $javac" }
if (-not (Test-Path $ScanScript)) {
    throw "스캔 스크립트 없음: $ScanScript`n  → -ScanScript 로 Scan-ClassFiles.ps1 경로를 직접 지정하거나, 두 파일을 같은 폴더에 둘 것"
}
Write-Host "스캔 스크립트: $ScanScript"

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# [PATCH 2026-08-13] WorkDir을 절대경로로 확정한다.
#   New-Item 같은 PowerShell cmdlet은 PS의 현재 위치(Get-Location) 기준으로 상대경로를 풀지만,
#   [System.IO.File]::WriteAllText/WriteAllBytes 같은 .NET 정적 메서드는 PS 위치를 모르고
#   [Environment]::CurrentDirectory(프로세스 시작 디렉터리, 보통 C:\Users\<계정>) 기준으로 푼다.
#   그래서 D:\tools\repro-matrix\ 를 만들어놓고 C:\Users\<계정>\repro-matrix\ 에 쓰려다
#   DirectoryNotFoundException 이 났다. 절대경로로 바꾸면 두 세계가 같은 곳을 가리킨다.
$WorkDir = (Resolve-Path $WorkDir).Path.TrimEnd('\')
Write-Host "작업 폴더  : $WorkDir"

$srcDir = Join-Path $WorkDir 'src\com\repro'
New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

# ---------------------------------------------------------------------------
# 대조군 소스 생성 (내용 동일, 인코딩만 다르게)
# ---------------------------------------------------------------------------
$java = @'
package com.repro;
public class ReproConst {
    public static final String TEMPLATE = "매출현황.xls";
    public static final String DOWNLOAD = "매출현황_다운로드.xls";
    public static final String DOT      = "재컴파일·재배포";
    public static final String ASCII    = "sales.xls";
}
'@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ms949     = [System.Text.Encoding]::GetEncoding(949)

$srcUtf8  = Join-Path $srcDir 'ReproConst.java'
[System.IO.File]::WriteAllText($srcUtf8, $java, $utf8NoBom)

# MS949 소스는 · (U+00B7) 를 뺀다 — CP949 에 없는 문자가 섞이면 비교가 흐려진다
$src949Dir = Join-Path $WorkDir 'src949\com\repro'
New-Item -ItemType Directory -Path $src949Dir -Force | Out-Null
$src949 = Join-Path $src949Dir 'ReproConst.java'
[System.IO.File]::WriteAllBytes($src949, $ms949.GetBytes(($java -replace '·', '')))

# ---------------------------------------------------------------------------
# 4가지 조합
# ---------------------------------------------------------------------------
$combos = @(
    [pscustomobject]@{ Name='UTF8소스_UTF8컴파일';   Src=$srcUtf8; Enc='UTF-8';      Expect='한글정상' }
    [pscustomobject]@{ Name='UTF8소스_L1컴파일';     Src=$srcUtf8; Enc='ISO-8859-1'; Expect='깨짐(Latin1)' }
    [pscustomobject]@{ Name='949소스_L1컴파일';      Src=$src949;  Enc='ISO-8859-1'; Expect='깨짐(Latin1)' }
    [pscustomobject]@{ Name='949소스_UTF8컴파일';    Src=$src949;  Enc='UTF-8';      Expect='손실(FFFD) 또는 컴파일에러' }
)

$results = @()
foreach ($c in $combos) {
    $out = Join-Path $WorkDir $c.Name
    New-Item -ItemType Directory -Path $out -Force | Out-Null

    Write-Host ""
    Write-Host "=== $($c.Name) (javac -encoding $($c.Enc)) ===" -ForegroundColor Cyan

    $log = & $javac -encoding $c.Enc -d $out $c.Src 2>&1
    $compiled = Test-Path (Join-Path $out 'com\repro\ReproConst.class')

    if (-not $compiled) {
        Write-Host "  컴파일 실패 (javac 가 막음)" -ForegroundColor Yellow
        $log | Select-Object -First 3 | ForEach-Object { Write-Host "    $_" }
        $results += [pscustomobject]@{ 조합=$c.Name; 기대=$c.Expect; 실제='컴파일에러'; 일치='-' }
        continue
    }

    $scan = & $ScanScript -Root $out -ConsoleOnly
    $status = @($scan | Select-Object -ExpandProperty Status -Unique) -join ','
    $enc    = @($scan | Select-Object -ExpandProperty Encoding -Unique) -join ','

    $match = 'N'
    if ($c.Expect -like "*$status*" -or $status -eq $c.Expect) { $match = 'Y' }

    Write-Host "  판정: $status / $enc"
    $results += [pscustomobject]@{ 조합=$c.Name; 기대=$c.Expect; 실제="$status ($enc)"; 일치=$match }
}

Write-Host ""
Write-Host "=== 재현 매트릭스 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Wrap

Write-Host ""
Write-Host "판독:" -ForegroundColor Yellow
Write-Host "  · 현장 증상과 같은 Status 가 나온 조합 = 현장에서 벌어진 일"
Write-Host "  · 949소스_UTF8컴파일 은 javac 버전에 따라 갈린다."
Write-Host "    JDK 8  : 경고만 내고 U+FFFD 로 치환 -> 손실(FFFD)"
Write-Host "    JDK 12+: unmappable character 에러로 컴파일 자체가 실패"
Write-Host "  · 정상 조합에서 '한글정상', 깨진 조합에서 '깨짐'이 모두 나와야"
Write-Host "    검출기를 신뢰할 수 있다. 한쪽만 맞으면 판정 로직을 의심할 것."
