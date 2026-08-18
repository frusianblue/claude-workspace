# ===========================================================================
# [표준 헤더] Phase2-Compare-Deployment.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-3  배포 동일성
#   역할 : 로컬 build/classes <-> 배포본 해시 대조 + jar 중복 + work 캐시 잔존
#   입력 : -LocalClasses, -DeployRoot, -TargetClass
#   출력 : 해시 비교 결과
#   선행 : ★ 해시 불일치면 소스 작업 자체가 무의미 — 배포부터 확인
#   상태 : 현행 (미실행 — 가설 3의 나머지 절반)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
<#
.SYNOPSIS
  Phase 2-3 / 2-4 — 배포본과 로컬 빌드의 동일성, jar 중복, WAS work 캐시를 검사한다.

.DESCRIPTION
  가설 3(배포/클래스로딩 문제)을 조기 판별한다.
  해시 불일치가 나오면 Phase 4/5 의 소스 작업은 무의미하다 — 배포부터 고쳐야 한다.

.EXAMPLE
  .\Phase2-Compare-Deployment.ps1 `
      -LocalClasses "D:\workspace\myapp\build\classes" `
      -DeployRoot   "D:\lena\AppServer\servers\WDMDB11\webapps\myapp" `
      -TargetClass  "com/test/constant/ExcelConstants.class"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $LocalClasses,
    [Parameter(Mandatory=$true)][string] $DeployRoot,
    [string] $TargetClass,                      # 중복 로딩을 확인할 클래스 (상대경로)
    [string[]] $WorkDirs                        # 추가로 확인할 WAS work/cache 경로
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

$ErrorActionPreference = 'Stop'
$LocalClasses = (Resolve-Path $LocalClasses).Path.TrimEnd('\')
$deployClasses = Join-Path $DeployRoot "WEB-INF\classes"
$deployLib     = Join-Path $DeployRoot "WEB-INF\lib"

# ---------------------------------------------------------------------------
Write-Host "=== 2-3. 배포본 vs 로컬 빌드 동일성 ===" -ForegroundColor Cyan

if (-not (Test-Path $deployClasses)) { Write-Warning "배포 classes 없음: $deployClasses" }
else {
    $diff = Get-ChildItem $LocalClasses -Filter *.class -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($LocalClasses.Length).TrimStart('\')
        $dep = Join-Path $deployClasses $rel
        if (-not (Test-Path -LiteralPath $dep)) {
            [pscustomobject]@{ Class=$rel; Status='배포본 없음'; Local=$_.LastWriteTime; Deployed='' }
        }
        else {
            $h1 = (Get-FileHash $_.FullName -Algorithm MD5).Hash
            $h2 = (Get-FileHash $dep        -Algorithm MD5).Hash
            if ($h1 -ne $h2) {
                [pscustomobject]@{
                    Class    = $rel
                    Status   = '불일치'
                    Local    = (Get-Item $_.FullName).LastWriteTime
                    Deployed = (Get-Item $dep).LastWriteTime
                }
            }
        }
    }

    if (-not $diff) { Write-Host "  전부 일치 — 배포는 정상" -ForegroundColor Green }
    else {
        $diff | Format-Table -AutoSize -Wrap
        Write-Host "  불일치 $(@($diff).Count)건 — 소스 작업 전에 배포부터 해결할 것" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 2-4. jar 버전 중복 ===" -ForegroundColor Cyan

if (-not (Test-Path $deployLib)) { Write-Warning "lib 없음: $deployLib" }
else {
    $dup = Get-ChildItem $deployLib -Filter *.jar |
        Group-Object { $_.BaseName -replace '-\d.*$','' } |
        Where-Object Count -gt 1
    if (-not $dup) { Write-Host "  중복 없음" -ForegroundColor Green }
    else {
        $dup | ForEach-Object { [pscustomobject]@{ Lib=$_.Name; Files=($_.Group.Name -join ', ') } } |
            Format-Table -AutoSize -Wrap
    }

    if ($TargetClass) {
        Write-Host ""
        Write-Host "=== 대상 클래스가 jar 안에도 있는지 ($TargetClass) ===" -ForegroundColor Cyan
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $needle = ($TargetClass -replace '\\','/')
        $found = $false
        Get-ChildItem $deployLib -Filter *.jar | ForEach-Object {
            $zip = $null
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
                foreach ($e in $zip.Entries) {
                    if ($e.FullName -like "*$needle") {
                        Write-Host "  중복 발견: $($_.Name) -> $($e.FullName)" -ForegroundColor Red
                        $found = $true
                    }
                }
            }
            catch { Write-Warning "$($_.Name): $($_.Exception.Message)" }
            finally { if ($zip) { $zip.Dispose() } }
        }
        if (-not $found) { Write-Host "  jar 내 중복 없음" -ForegroundColor Green }
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== WAS work / cache 잔존 ===" -ForegroundColor Cyan

$cands = @(
    (Join-Path $DeployRoot "work"),
    (Join-Path (Split-Path $DeployRoot -Parent) "work")
)
if ($WorkDirs) { $cands += $WorkDirs }

$any = $false
foreach ($c in ($cands | Select-Object -Unique)) {
    if (Test-Path $c) {
        $n = @(Get-ChildItem $c -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ("  {0,-60} {1} 파일" -f $c, $n)
        if ($n -gt 0) { $any = $true }
    }
}
if ($any) {
    Write-Host "  work 캐시 잔존 — 재배포 시 삭제 후 재기동할 것 (Phase 5 C-6)" -ForegroundColor Yellow
} else {
    Write-Host "  잔존 없음" -ForegroundColor Green
}
