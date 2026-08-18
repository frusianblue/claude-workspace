# ===========================================================================
# [표준 헤더] Phase3-Invoke-Diagnosis.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-4  분기 판정
#   역할 : 스캔 결과로 가설 1(인라이닝)/2(소스 MS949)/3(배포·런타임) 판정
#   입력 : -ConstantsDat + -ControllerDat (또는 -AllDat + 패턴)
#   출력 : 판정 매트릭스 결과
#   선행 : Scan-ClassFiles 선행. Constants와 참조 클래스를 반드시 함께 볼 것
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 3 — Phase 2 산출물을 읽어 가설 1/2/3 중 하나로 판정한다.

.DESCRIPTION
  입력은 Scan-ClassFiles.ps1 이 만든 요약 .dat 파일이다.
  (컬럼: File|JDK|Major|Status|Encoding|SrcEnc|Broken|Hangul)

  Constants 클래스와 참조 클래스(Controller 등)를 반드시 함께 측정해야 한다.
  하나만 보면 가설 1(인라이닝)을 검증할 수 없다.

.EXAMPLE
  .\Phase3-Invoke-Diagnosis.ps1 `
      -ConstantsDat  ".\Scan-ClassFiles\constants_20260812_090000.dat" `
      -ControllerDat ".\Scan-ClassFiles\controller_20260812_090100.dat"

.EXAMPLE
  # 스캔 1회로 전체를 뜬 경우, 클래스명 필터로 나눠서 판정
  .\Phase3-Invoke-Diagnosis.ps1 -AllDat ".\Scan-ClassFiles\app_20260812.dat" `
      -ConstantsPattern "Constants" -ControllerPattern "Controller|View"
#>
[CmdletBinding()]
param(
    [string] $ConstantsDat,
    [string] $ControllerDat,
    [string] $AllDat,
    [string] $ConstantsPattern  = 'Constant',
    [string] $ControllerPattern = 'Controller|View|Service'
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = 'Stop'

# Status 값 -> 판정 코드
function Resolve-Verdict($rows, [string] $label) {
    if (-not $rows -or @($rows).Count -eq 0) {
        Write-Warning "$label : 해당 행 없음"
        return $null
    }
    $st = @($rows | Select-Object -ExpandProperty Status -Unique)

    $v = 'NO_KOREAN'
    if     ($st -contains '파싱실패')      { $v = 'PARSE_FAIL' }
    elseif ($st -contains '손실(FFFD)')    { $v = 'FFFD' }
    elseif ($st -contains '깨짐(Latin1)')  { $v = 'LATIN1' }
    elseif ($st -contains '깨짐(949이중)') { $v = 'MS949DBL' }
    elseif ($st -contains '한글정상')      { $v = 'OK' }

    # Latin1 인 경우 원본 소스 계열까지 표시
    $detail = ''
    if ($v -eq 'LATIN1') {
        $enc = @($rows | Where-Object Status -eq '깨짐(Latin1)' |
                 Select-Object -ExpandProperty Encoding -Unique) -join ','
        $detail = " ($enc)"
    }
    $srcEnc = @($rows | Select-Object -ExpandProperty SrcEnc -Unique | Where-Object { $_ -and $_ -ne '-' }) -join ','
    if ($srcEnc) { $detail += " [소스: $srcEnc]" }

    Write-Host ("  {0,-12} : {1}{2}   (파일 {3}건, 깨짐 {4}건)" -f `
        $label, $v, $detail, @($rows).Count,
        (($rows | Measure-Object -Property Broken -Sum).Sum)) -ForegroundColor Yellow
    return $v
}

function Import-Dat([string] $p) {
    if (-not (Test-Path -LiteralPath $p)) { throw "파일 없음: $p" }
    return Import-Csv -LiteralPath $p -Delimiter '|'
}

Write-Host "=== Phase 3 — 측정 결과 ===" -ForegroundColor Cyan

if ($AllDat) {
    $all = Import-Dat $AllDat
    $cRows = $all | Where-Object { $_.File -match $ConstantsPattern }
    $lRows = $all | Where-Object { $_.File -match $ControllerPattern }
}
else {
    if (-not $ConstantsDat -or -not $ControllerDat) {
        throw "-AllDat 또는 (-ConstantsDat + -ControllerDat) 중 하나는 지정해야 한다."
    }
    $cRows = Import-Dat $ConstantsDat
    $lRows = Import-Dat $ControllerDat
}

$c = Resolve-Verdict $cRows 'Constants'
$l = Resolve-Verdict $lRows 'Controller'

Write-Host ""
Write-Host "=== 판정 ===" -ForegroundColor Cyan

if ($c -eq 'PARSE_FAIL' -or $l -eq 'PARSE_FAIL') {
    Write-Host "판정 보류 — 파싱실패 행이 있다. 해당 class 를 먼저 확인할 것." -ForegroundColor Magenta
    Write-Host "  (읽지 못한 클래스가 있으면 '깨짐 없음'이 근거가 되지 못한다)"
}
elseif ($c -eq 'FFFD' -or $l -eq 'FFFD') {
    Write-Host "가설 2 확정 — 소스가 MS949인데 javac -encoding UTF-8로 컴파일됨" -ForegroundColor Red
    Write-Host "  -> Phase 4(소스 변환)부터 전부 수행. class 만으로는 복구 불가."
    Write-Host "  -> 소스에도 U+FFFD 가 박혀 있으면 형상관리에서 원본을 가져와야 한다."
}
elseif ($c -eq 'LATIN1' -or $l -eq 'LATIN1') {
    Write-Host "가설 2 변형 — javac encoding 이 ISO-8859-1" -ForegroundColor Red
    Write-Host "  -> build.xml 의 javac encoding 점검 + Phase 4. 복원은 가능."
    Write-Host "  -> Encoding 컬럼의 (UTF8소스)/(949소스) 로 원본 인코딩을 알 수 있다."
}
elseif ($c -eq 'MS949DBL' -or $l -eq 'MS949DBL') {
    Write-Host "MS949 이중해석 — UTF-8 문자열을 MS949 로 읽은 흔적" -ForegroundColor Red
    Write-Host "  -> 컴파일보다 런타임 경로일 가능성이 높다. Phase 5 D-1 로 직행."
}
elseif ($c -eq 'OK' -and $l -ne 'OK') {
    Write-Host "가설 1 확정 — 인라이닝. Constants 만 재컴파일되고 참조 클래스는 구값 유지" -ForegroundColor Red
    Write-Host "  -> Phase 4 생략. Phase 5 의 C-4(clean + 전체 재빌드)부터 수행."
    Write-Host "  -> static final String 상수는 컴파일 타임에 참조 클래스로 복사된다."
}
elseif ($c -eq 'OK' -and $l -eq 'OK') {
    Write-Host "가설 3 확정 — 상수 풀은 정상. 배포/클래스로딩 문제" -ForegroundColor Green
    Write-Host "  -> Phase 2-3/2-4 결과 확인 후 Phase 5 의 C-6(work 삭제)·C-7 만 수행."
    Write-Host "  -> 그래도 FNFE 가 남으면 원인은 컴파일이 아니라 런타임(Case A)."
    Write-Host "     Phase 5 의 D-1 로 직행할 것." -ForegroundColor Yellow
}
else {
    Write-Host "한글 리터럴이 검출되지 않음" -ForegroundColor Magenta
    Write-Host "  -> 대상 클래스 선정이 잘못되었을 수 있다. 전체 스캔에서 한글 보유 클래스를 먼저 찾을 것:"
    Write-Host '     Import-Csv .\<전체스캔>.dat -Delimiter "|" | ? { [int]$_.Hangul -gt 0 } | ft File,Status'
}

Write-Host ""
Write-Host "※ 상수 풀의 '?' (Case A 소스 오염) 는 이 도구로 판별할 수 없다." -ForegroundColor DarkYellow
Write-Host "   정상 물음표와 구분이 불가능하기 때문이다. 의심되면 Phase 4 에서 소스를 육안 확인할 것."
