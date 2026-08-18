# ===========================================================================
# [표준 헤더] Phase1-Get-TargetFilenameBytes.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-5  런타임 축
#   역할 : 디스크 실제 파일명 바이트 덤프 — D-1 방침을 여기서 결정
#   입력 : -Path 업로드 폴더, -Recurse
#   출력 : target-bytes.dat (Verdict: 정상/AS-IS깨짐저장/디스크손상/혼재)
#   선행 : ★ 코드를 고치기 전에 반드시 먼저 실행
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 1-1 — 업로드/다운로드 디렉터리의 실제 파일명을 바이트 수준으로 덤프한다.

.DESCRIPTION
  "UTF-8로 통일"이 목표가 아니다. 디스크에 실제로 존재하는 파일명 바이트가 목표다.
  여기서 나오는 결과가 Phase 5 의 CommExcelView 처리 방침(D-1)을 사전 결정한다.

  NTFS 는 파일명을 UTF-16 으로 저장한다. .NET 이 읽어온 시점의 문자열이 '진실'이다.

.EXAMPLE
  .\Phase1-Get-TargetFilenameBytes.ps1 -Path "D:\upload" -Recurse
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $Path,
    [string] $OutFile = ".\target-bytes.dat",
    [switch] $Recurse
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path)) { throw "경로 없음: $Path" }

$ms949  = [System.Text.Encoding]::GetEncoding(949)
$utf8   = [System.Text.Encoding]::UTF8
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Format-HexBytes([byte[]] $b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }

$gciArgs = @{ Path = $Path; File = $true }
if ($Recurse) { $gciArgs['Recurse'] = $true }

$rows = Get-ChildItem @gciArgs | ForEach-Object {
    $n = $_.Name

    $hasHangul = $n -match '[\uAC00-\uD7A3\u3131-\u318E]'
    $hasFFFD   = $n -match '\uFFFD'

    # 구 서버가 깨뜨린 채 저장한 흔적 (한글도 FFFD도 아닌데 상위 라틴문자가 있음)
    $looksMojibake = (-not $hasHangul) -and (-not $hasFFFD) -and ($n -match '[\u0080-\u00FF]')

    $verdict = "정상"
    if     ($hasFFFD)       { $verdict = "디스크손상" }
    elseif ($looksMojibake) { $verdict = "AS-IS깨짐저장" }
    elseif (-not $hasHangul){ $verdict = "ASCII" }

    [pscustomobject]@{
        FileName   = $n
        Verdict    = $verdict
        Hangul     = $(if ($hasHangul) { 'Y' } else { 'N' })
        FFFD       = $(if ($hasFFFD)   { 'Y' } else { 'N' })
        UTF16_Hex  = Format-HexBytes ([System.Text.Encoding]::Unicode.GetBytes($n))
        MS949_Hex  = Format-HexBytes ($ms949.GetBytes($n))
        UTF8_Hex   = Format-HexBytes ($utf8.GetBytes($n))
        Latin1_Hex = Format-HexBytes ($latin1.GetBytes($n))   # 매핑 불가 -> 3F
    }
}

$rows | Format-Table FileName, Verdict, Hangul, FFFD, MS949_Hex, UTF8_Hex -AutoSize -Wrap

$sw = New-Object System.IO.StreamWriter($OutFile, $false, (New-Object System.Text.UTF8Encoding($true)))
$sw.WriteLine("FileName|Verdict|Hangul|FFFD|UTF16_Hex|MS949_Hex|UTF8_Hex|Latin1_Hex")
foreach ($r in $rows) {
    $sw.WriteLine("$($r.FileName)|$($r.Verdict)|$($r.Hangul)|$($r.FFFD)|$($r.UTF16_Hex)|$($r.MS949_Hex)|$($r.UTF8_Hex)|$($r.Latin1_Hex)")
}
$sw.Close()

Write-Host ""
Write-Host "저장 완료: $OutFile  ($($rows.Count)건)" -ForegroundColor Green
Write-Host ""
Write-Host "=== 판독 가이드 -> Phase 5 D-1 방침 ===" -ForegroundColor Cyan
Write-Host '  정상(한글)      : 서버가 UTF-16으로 정상 저장 중  -> getBytes(8859_1) 변환 제거'
Write-Host "  AS-IS깨짐저장   : 구 서버 방식으로 저장된 레거시   -> 양방향 fallback 또는 rename 배치"
Write-Host "  디스크손상      : 파일명 자체가 이미 파괴됨        -> 파일 rename 선행 필요"
Write-Host ""

$mix = @($rows | Select-Object -ExpandProperty Verdict -Unique | Where-Object { $_ -ne 'ASCII' })
if ($mix.Count -gt 1) {
    Write-Host "혼재 상태 ($($mix -join ', ')) — 이관 전후 파일이 섞임. 양쪽 fallback 로직 필요." -ForegroundColor Yellow
}
