# ===========================================================================
# [폐기] Convert-ToUtf8.ps1
#   사유 : Phase4-Convert-SourceEncoding.ps1 로 대체됨
#   비고 : Phase4는 백업 파일 수 검증 / -StripBom / Action 분류 / -ExcludeDirs 를 갖췄다.
#   이 파일은 .bak 을 원본 옆에 만들고 제외 기능이 없어 치환 백업을 오염시킬 수 있다.
#   다만 -Extensions 다중 확장자 처리는 이쪽이 편하므로 Phase4로 이식 후 폐기 확정할 것.
#
#   이 폴더의 파일은 실행하지 말 것. 삭제하지 않고 남겨둔 이유는
#   '아직 이식되지 않은 기능이 있는지' 나중에 확인할 근거가 필요하기 때문이다.
# ===========================================================================
# 소스 파일 인코딩 판별 + MS949 → UTF-8 일괄 변환
# 사용법:
#   .\Convert-ToUtf8.ps1 -Root "D:\...\src" -WhatIf                       # 변환 없이 판별만
#   .\Convert-ToUtf8.ps1 -Root "D:\...\src" -WhatIf -OutFile src-enc.dat  # 판별 결과를 dat로 저장
#   .\Convert-ToUtf8.ps1 -Root "D:\...\src"                               # 실제 변환 (.bak 백업 생성)
#
# 판별 원리: UTF-8은 엄격한 포맷이라 MS949 한글 바이트를 UTF-8 strict로 읽으면 반드시 실패함.
#   UTF-8       : strict 디코드 성공 + 한글/비ASCII 포함
#   ASCII       : strict 디코드 성공 + 전부 ASCII (어느 쪽으로 컴파일해도 무관)
#   MS949(추정) : strict 디코드 실패 → 변환 대상
#
# 주의: 변환 저장은 BOM 없는 UTF-8 (javac은 BOM 있으면 "illegal character \ufeff" 에러 남)
#       리포트 dat만 BOM 포함 (엑셀 인식용)
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [string[]]$Extensions = @("*.java", "*.properties", "*.xml", "*.jsp", "*.js", "*.sql"),
    [string]$OutFile,
    [string]$Delimiter = "|",
    [switch]$WhatIf
)

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$ms949      = [System.Text.Encoding]::GetEncoding(949)
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)   # 소스 저장용: BOM 없음 (javac 호환)
$utf8Bom    = New-Object System.Text.UTF8Encoding($true)    # 리포트용: BOM 포함 (엑셀 인식)

$results = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $Root -Recurse -Include $Extensions -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $relFile = $_.FullName.Substring($Root.Length).TrimStart('\')

    $enc = ""; $action = ""
    try {
        $text = $utf8Strict.GetString($bytes)
        if ($text -match "[^\u0000-\u007F]") { $enc = "UTF-8" } else { $enc = "ASCII" }
        $action = "유지"
    } catch {
        $enc = "MS949(추정)"
        $text = $ms949.GetString($bytes)
        if ($WhatIf) {
            $action = "변환대상"
        } else {
            Copy-Item $_.FullName "$($_.FullName).bak" -Force
            [System.IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom)
            $action = "변환완료"
        }
    }

    $row = [PSCustomObject]@{ File = $relFile; Encoding = $enc; Action = $action }
    $results.Add($row)
    if (-not $OutFile) {
        if ($enc -ne "ASCII") { $row }   # 콘솔엔 ASCII 제외하고 출력 (노이즈 방지)
    }
}

if ($OutFile) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("File","Encoding","Action") -join $Delimiter)
    foreach ($r in $results) { $lines.Add(($r.File, $r.Encoding, $r.Action) -join $Delimiter) }
    [System.IO.File]::WriteAllLines($OutFile, $lines, $utf8Bom)
    Write-Host "저장 완료: $OutFile"
}

# 요약
Write-Host ""
$sum = $results | Group-Object Encoding | Sort-Object Count -Descending
Write-Host "총 $($results.Count) 건 스캔"
foreach ($g in $sum) { Write-Host ("  {0,-12} {1,6} 건" -f $g.Name, $g.Count) }
if ($WhatIf) { Write-Host "(-WhatIf 모드: 실제 변환 안 됨)" }
