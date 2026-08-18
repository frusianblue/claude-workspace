# ===========================================================================
# [표준 헤더] Phase4-Convert-SourceEncoding.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-6  인코딩 통일
#   역할 : 소스 인코딩 분류 + MS949 -> UTF-8 변환 (백업·검증·BOM 제거)
#   입력 : -SrcPath, -Convert, -StripBom, -ExcludeDirs
#   출력 : source-encoding.dat + <BackupRoot>\<일시>\
#   선행 : ★ 경로/IP 치환(A-3,A-4)보다 먼저. 순서 뒤바뀌면 치환 백업이 오염됨
#   상태 : 현행 (2026-08-13 -ExcludeDirs 패치 적용)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 4 — .java 소스의 실제 인코딩을 분류하고, 필요 시 UTF-8 로 변환한다.

.DESCRIPTION
  기본 동작은 '분류만' 이다. 변환은 -Convert 를 붙여야 실행되며,
  변환 전에 자동 백업하고 검증까지 수행한다.

  U+FFFD 가 이미 박힌 소스는 변환으로 복구되지 않는다.
  형상관리(SVN/Git)에서 원본을 가져와야 한다.

.EXAMPLE
  # 1) 분류만 (드라이런)
  .\Phase4-Convert-SourceEncoding.ps1 -SrcPath "D:\workspace\myapp\src"

  # 2) 변환 실행 (백업 자동)
  .\Phase4-Convert-SourceEncoding.ps1 -SrcPath "D:\workspace\myapp\src" -Convert
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $SrcPath,
    [string] $OutFile = ".\source-encoding.dat",
    [switch] $Convert,                # 실제 변환 수행 (없으면 분류만)
    [switch] $StripBom,               # 변환 시 BOM 제거 (javac 8 은 BOM 미지원)
    [string] $BackupRoot = ".\src-backup",

    # [PATCH 2026-08-13] 제외 폴더. 직접 지정 시 기본값은 '대체'된다 (추가 아님 — Find v8.2와 동일 규칙)
    [string[]] $ExcludeDirs = @(".git",".svn",".metadata","node_modules","target","bin","build","classes","dist")
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SrcPath)) { throw "경로 없음: $SrcPath" }
$SrcPath = (Resolve-Path $SrcPath).Path.TrimEnd('\')

# ---------------------------------------------------------------------------
# [PATCH 2026-08-13] 제외 판정
#   ★ 치환 백업 폴더(<소스명>_backup_path_*, *_backup_ip_*)를 반드시 제외해야 한다.
#     Replace-AsisPath/-AsisIp가 -Apply 시 소스 옆에 만드는 롤백용 백업인데,
#     이걸 변환 대상에 넣으면 백업이 원본과 다른 인코딩으로 오염되어 롤백 구실을 못 한다.
#     (Find v8.2 / Replace v3에는 이 자동제외가 이미 있고, 이 스크립트에만 없었다)
# ---------------------------------------------------------------------------
$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/][^\\/]*_backup_(path|ip)_') { return $true }
    return $false
}

$encFail    = New-Object System.Text.EncoderExceptionFallback
$decFail    = New-Object System.Text.DecoderExceptionFallback
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$ms949      = [System.Text.Encoding]::GetEncoding(949, $encFail, $decFail)

# ---------------------------------------------------------------------------
# 4-1. 분류
# ---------------------------------------------------------------------------
$rows = Get-ChildItem $SrcPath -Filter *.java -Recurse -File |
        Where-Object { -not (Test-Excluded $_.FullName) } |
        ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)

    $bom = ''
    if     ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $bom = 'UTF8-BOM' }
    elseif ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { $bom = 'UTF16-LE' }
    elseif ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { $bom = 'UTF16-BE' }

    $nonAscii = $false
    foreach ($x in $b) { if ($x -ge 0x80) { $nonAscii = $true; break } }

    $enc  = 'ASCII'
    $text = $null
    if ($nonAscii) {
        $off = 0
        if ($bom -eq 'UTF8-BOM') { $off = 3 }
        try   { $text = $utf8Strict.GetString($b, $off, $b.Length - $off); $enc = 'UTF-8' }
        catch {
            try   { $text = $ms949.GetString($b); $enc = 'MS949' }
            catch { $enc = '미확인' }
        }
    }
    else { $text = [System.Text.Encoding]::ASCII.GetString($b) }

    # 이미 U+FFFD 가 소스에 박혀 있으면 원본 손실 — 변환해도 복구 불가
    $hasFFFD = $false
    for ($k = 0; $k -le $b.Length - 3; $k++) {
        if ($b[$k] -eq 0xEF -and $b[$k+1] -eq 0xBF -and $b[$k+2] -eq 0xBD) { $hasFFFD = $true; break }
    }

    $hasHangul = $false
    if ($text) { $hasHangul = $text -match '[\uAC00-\uD7A3]' }

    $action = '변환 불필요'
    if     ($hasFFFD)                          { $action = '원본 손실 - 형상관리에서 복원 필요' }
    elseif ($enc -eq '미확인')                 { $action = '인코딩 판별 실패 - 수동 확인' }
    elseif ($bom -like 'UTF16*')               { $action = 'UTF-16 - 수동 변환 필요' }
    elseif ($bom -eq 'UTF8-BOM')               { $action = 'BOM 제거 권장 (javac 8 미지원)' }
    elseif ($enc -eq 'MS949' -and $hasHangul)  { $action = 'UTF-8 변환 대상' }
    elseif ($enc -eq 'MS949')                  { $action = '변환 무해 (한글 없음)' }

    [pscustomobject]@{
        Path      = $_.FullName
        Rel       = $_.FullName.Substring($SrcPath.Length).TrimStart('\')
        Encoding  = $enc
        BOM       = $bom
        Hangul    = $(if ($hasHangul) { 'Y' } else { 'N' })
        FFFD      = $(if ($hasFFFD)   { 'Y' } else { 'N' })
        Action    = $action
    }
}

Write-Host "=== 4-1. 소스 인코딩 분류 ===" -ForegroundColor Cyan
$rows | Group-Object Encoding | Format-Table @{n='인코딩';e={$_.Name}}, Count -AutoSize
Write-Host ""
$todo = @($rows | Where-Object { $_.Action -ne '변환 불필요' })
if ($todo.Count -gt 0) { $todo | Format-Table Rel, Encoding, BOM, Hangul, FFFD, Action -AutoSize -Wrap }
else { Write-Host "  조치 대상 없음" -ForegroundColor Green }

$sw = New-Object System.IO.StreamWriter($OutFile, $false, (New-Object System.Text.UTF8Encoding($true)))
$sw.WriteLine("Path|Encoding|BOM|Hangul|FFFD|Action")
foreach ($r in $rows) { $sw.WriteLine("$($r.Path)|$($r.Encoding)|$($r.BOM)|$($r.Hangul)|$($r.FFFD)|$($r.Action)") }
$sw.Close()
Write-Host ""
Write-Host "저장 완료: $OutFile ($($rows.Count)건)" -ForegroundColor Green

$lost = @($rows | Where-Object FFFD -eq 'Y')
if ($lost.Count -gt 0) {
    Write-Host ""
    Write-Host "U+FFFD 포함 소스 $($lost.Count)건 — 변환으로 복구되지 않는다." -ForegroundColor Red
    Write-Host "형상관리(SVN/Git)에서 원본을 가져올 것. 이 파일들은 변환 대상에서 제외한다."
}

# ---------------------------------------------------------------------------
# 4-2 / 4-3. 백업 + 변환
# ---------------------------------------------------------------------------
$targets = @($rows | Where-Object { $_.Encoding -eq 'MS949' -and $_.FFFD -eq 'N' })
if ($StripBom) { $targets += @($rows | Where-Object { $_.BOM -eq 'UTF8-BOM' }) }
$targets = @($targets | Sort-Object Path -Unique)

Write-Host ""
if (-not $Convert) {
    Write-Host "=== 드라이런 — 변환 대상 $($targets.Count)건 ===" -ForegroundColor Yellow
    $targets | ForEach-Object { Write-Host "  $($_.Rel)  [$($_.Encoding)$(if($_.BOM){'/'+$_.BOM})]" }
    Write-Host ""
    Write-Host "실제 변환하려면 -Convert 를 붙일 것." -ForegroundColor Yellow
    return
}

if ($targets.Count -eq 0) { Write-Host "변환 대상 없음 — 종료" -ForegroundColor Green; return }

# 백업
# [PATCH 2026-08-13] BackupRoot가 SrcPath 하위면 자기 자신을 재귀 복사하게 되므로 차단
$bakFull = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $BackupRoot))
if ($bakFull.StartsWith($SrcPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "BackupRoot가 소스 트리 안에 있음: $bakFull`n  → 소스 밖 경로로 지정할 것 (예: -BackupRoot D:\backup\src)"
}
$bak = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $bak -Force | Out-Null
Copy-Item $SrcPath $bak -Recurse -Force
$srcCount = @(Get-ChildItem $SrcPath -Recurse -File).Count
$bakCount = @(Get-ChildItem $bak     -Recurse -File).Count
if ($srcCount -ne $bakCount) { throw "백업 파일 수 불일치: 원본 $srcCount vs 백업 $bakCount" }
Write-Host "백업 완료: $bak ($bakCount 파일)" -ForegroundColor Green

# 변환
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ok = 0; $fail = 0
foreach ($t in $targets) {
    try {
        $b = [System.IO.File]::ReadAllBytes($t.Path)
        $text = $null
        if ($t.Encoding -eq 'MS949') { $text = $ms949.GetString($b) }
        else {
            $off = 0
            if ($t.BOM -eq 'UTF8-BOM') { $off = 3 }
            $text = $utf8Strict.GetString($b, $off, $b.Length - $off)
        }
        [System.IO.File]::WriteAllText($t.Path, $text, $utf8NoBom)
        $ok++
    }
    catch { Write-Warning "$($t.Rel) : $($_.Exception.Message)"; $fail++ }
}
Write-Host "변환 완료: 성공 $ok / 실패 $fail" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4-4. 변환 후 검증
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 4-4. 변환 후 검증 ===" -ForegroundColor Cyan
$bad = 0
foreach ($t in $targets) {
    $b = [System.IO.File]::ReadAllBytes($t.Path)
    try { $null = $utf8Strict.GetString($b) }
    catch { Write-Warning "UTF-8 아님: $($t.Rel)"; $bad++ }
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Warning "BOM 남음: $($t.Rel)"; $bad++
    }
}
if ($bad -eq 0) { Write-Host "  전부 UTF-8(BOM 없음) 확인" -ForegroundColor Green }
Write-Host ""
Write-Host "다음: build.xml 의 javac encoding 을 UTF-8 로 맞추고 Phase 5 로 진행." -ForegroundColor Yellow
