# ===========================================================================
# [표준 헤더] Phase0-Init-EncodingConsole.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-0  계측 환경 고정
#   역할 : 콘솔 코드페이지·출력 인코딩·실행정책을 UTF-8로 일괄 고정
#   입력 : 없음
#   출력 : 콘솔 설정 (한글/U+FFFD/? 세 줄이 서로 다르게 보이면 통과)
#   선행 : ★ 점 소싱 필수: . .\Phase0-Init-EncodingConsole.ps1
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 0 — 인코딩 진단 세션용 콘솔 초기화. 새 PowerShell 창을 열 때마다 실행할 것.

.DESCRIPTION
  MS949 콘솔은 U+FFFD 와 실제 0x3F 를 똑같이 '?' 로 보여준다.
  이 단계를 건너뛰면 Phase 2/3 의 판정이 전부 무효가 된다.

  ※ 이 파일은 UTF-8 with BOM 으로 저장할 것.
     Windows PowerShell 5.1 은 BOM 없는 파일을 MS949 로 읽어서,
     깨진 바이트가 따옴표를 삼켜 엉뚱한 구문 오류를 낸다.

.EXAMPLE
  . .\Phase0-Init-EncodingConsole.ps1        # 반드시 점(.) 소싱 — 현재 세션에 적용
#>
[CmdletBinding()]
param(
    [switch] $SkipPolicy      # 실행 정책 조정을 건너뛴다
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "=== Phase 0 — 계측 환경 고정 ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1) 실행 정책
# ---------------------------------------------------------------------------
if (-not $SkipPolicy) {
    $cur = Get-ExecutionPolicy -Scope Process
    if ($cur -ne 'Bypass' -and $cur -ne 'Unrestricted') {
        try {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            Write-Host "  실행 정책  : Process 스코프 Bypass (창 닫으면 원복)" -ForegroundColor Green
        }
        catch {
            Write-Warning "  실행 정책 변경 실패 — GPO 강제일 수 있음."
            Write-Host "    우회: powershell -ExecutionPolicy Bypass -File .\<스크립트>.ps1"
        }
    }
    $mp = (Get-ExecutionPolicy -List | Where-Object Scope -eq 'MachinePolicy').ExecutionPolicy
    if ($mp -and $mp -ne 'Undefined') {
        Write-Warning "  MachinePolicy=$mp — GPO 강제. -File Bypass 도 무시될 수 있음."
    }
}

# ---------------------------------------------------------------------------
# 2) 코드 페이지 -> UTF-8
# ---------------------------------------------------------------------------
$prevCP = (chcp) -replace '[^\d]', ''
chcp 65001 > $null
Write-Host "  코드페이지 : $prevCP -> 65001" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3) 콘솔 입출력 디코딩
# ---------------------------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# 4) PS 5.1 필수 — 네이티브 프로그램(javap 등)으로 '보낼 때' 인코딩. 기본값 ASCII.
$global:OutputEncoding = [System.Text.Encoding]::UTF8

# 5) Out-File / Set-Content 기본 인코딩 통일
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $global:PSDefaultParameterValues['*:Encoding'] = 'utf8BOM'
} else {
    $global:PSDefaultParameterValues['*:Encoding'] = 'UTF8'   # PS5.1은 BOM 포함됨
}
Write-Host "  출력 인코딩: Console/OutputEncoding/PSDefault 모두 UTF-8" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 6) 게이트 — 자가 진단
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 게이트 확인 ===" -ForegroundColor Cyan

$probe = "매출현황.xls"
$fffd  = [string][char]0xFFFD
$qmark = "?"

Write-Host "  한글 표시   : $probe"
Write-Host "  U+FFFD 표시 : $fffd"
Write-Host "  물음표 표시 : $qmark"
Write-Host ""
Write-Host "  위 세 줄이 각각 다르게 보여야 한다." -ForegroundColor Yellow
Write-Host "  U+FFFD 와 물음표가 똑같이 '?' 로 보이면 콘솔 폰트를 바꿀 것"
Write-Host "  (속성 -> 글꼴 -> D2Coding / Consolas / NanumGothicCoding)"
Write-Host ""
Write-Host "  ※ 콘솔이 깨져도 스크립트의 '판정 결과' 자체는 영향받지 않는다."
Write-Host "     판정은 바이트 기반이고, 파일 저장은 항상 UTF-8 BOM 이다."
