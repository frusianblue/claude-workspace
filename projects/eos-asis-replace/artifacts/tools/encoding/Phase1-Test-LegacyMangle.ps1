# ===========================================================================
# [표준 헤더] Phase1-Test-LegacyMangle.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-5  런타임 축
#   역할 : new String(s.getBytes("8859_1"),"UTF-8") 파괴 로직을 Java 없이 재현
#   입력 : 파이프 입력 (파일명 문자열)
#   출력 : 원본/레거시결과/소실여부/왕복일치
#   선행 : Phase1-Get-TargetFilenameBytes 결과를 넘겨 쓰면 실측 검증
#   상태 : 현행
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 1-2 — new String(s.getBytes("8859_1"), "UTF-8") 을 .NET 으로 동일 재현한다.

.DESCRIPTION
  Java 와 .NET 모두 매핑 불가 문자를 '?'(0x3F)로 대체하므로 결과가 일치한다.
  CommExcelView 의 레거시 변환이 실제로 무엇을 만드는지 Java 없이 확인할 수 있다.

.EXAMPLE
  '매출현황.xls' | .\Phase1-Test-LegacyMangle.ps1 | Format-List

.EXAMPLE
  (Import-Csv .\target-bytes.dat -Delimiter '|').FileName |
      .\Phase1-Test-LegacyMangle.ps1 |
      Format-Table 원본, 레거시결과, 소실여부 -AutoSize
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)][string[]] $FileName
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath
begin {
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $utf8   = [System.Text.Encoding]::UTF8
    $ms949  = [System.Text.Encoding]::GetEncoding(949)
    function Format-HexBytes([byte[]] $b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }
}
process {
    foreach ($n in $FileName) {
        if (-not $n) { continue }

        # 1) getBytes("8859_1") — 한글은 전부 0x3F 로 소실
        $step1 = $latin1.GetBytes($n)
        # 2) new String(bytes, "UTF-8")
        $step2 = $utf8.GetString($step1)

        # 참고: 구 Tomcat 에서 '동작했던' 경로 (MS949 바이트가 Latin-1 로 디코딩되어 도착)
        $ms949Bytes  = $ms949.GetBytes($n)
        $arrivedAsL1 = $latin1.GetString($ms949Bytes)
        $recovered   = $ms949.GetString($latin1.GetBytes($arrivedAsL1))

        [pscustomobject]@{
            '원본'            = $n
            '원본_MS949'      = Format-HexBytes $ms949Bytes
            'getBytes8859_1'  = Format-HexBytes $step1
            '레거시결과'      = $step2
            '소실여부'        = $(if ($step2 -match '\?') { '소실(비가역)' } else { '보존' })
            '구서버_도착값'   = $arrivedAsL1
            '구서버_복원값'   = $recovered
            '왕복일치'        = $(if ($recovered -eq $n) { 'Y' } else { 'N' })
        }
    }
}
end {
    Write-Host ""
    Write-Host "소실(비가역) 이 나오면 그 코드 경로는 파일을 절대 찾을 수 없다." -ForegroundColor Yellow
    Write-Host "왕복일치=Y 이면 구 서버에서 동작했던 이유가 설명된다 (커넥터가 Latin-1이었음)." -ForegroundColor Yellow
}
