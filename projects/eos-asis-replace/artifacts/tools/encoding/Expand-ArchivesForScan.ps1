# ===========================================================================
# [표준 헤더] Expand-ArchivesForScan.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-4  보조
#   역할 : jar/war/ear 내부 .class 를 폴더로 추출 (중첩 아카이브 재귀)
#   입력 : -Root 아카이브 폴더, -Out 추출 위치
#   출력 : <Out>\<아카이브체인>\...class + _extracted.dat
#   선행 : 없음. 추출 후 Scan-ClassFiles -Root <Out>
#   상태 : 현행 v1 (2026-08-13 신규)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# ===========================================================================
# Expand-ArchivesForScan.ps1  (v1, 2026-08-13 신규)
#   계열 : B (인코딩 진단)
#   단계 : B-4 보조 — 운영 jar/war 안의 .class 를 평평한 폴더로 추출
#   입력 : 아카이브가 들어있는 폴더 (webapps, WEB-INF/lib 등)
#   출력 : <Out>\<아카이브체인>\<엔트리경로>.class  + 추출 목록 .dat
#   후속 : .\Scan-ClassFiles.ps1 -Root <Out>
# ===========================================================================
#
# ── 왜 이 스크립트가 따로 있는가 ────────────────────────────────────
#   HANDOFF 열린 질문 3번(운영 jar/war 전수 점검)을 하려면 아카이브 내부
#   .class 를 읽어야 하는데, 현행 Scan-ClassFiles.ps1 에는 그 기능이 없다.
#   (-IncludeArchives 는 폐기된 Check-ClassEncoding.ps1 에만 있었다)
#
#   Scan-ClassFiles 본체를 고치는 방법도 있었지만, 그 파일은 상수풀 파서를
#   품은 핵심 도구이고 8/12에 이미 파서 결함으로 측정치 전량을 폐기한 이력이 있다.
#   PS 5.1 실기기 검증 없이 본체를 건드리는 것보다, 아카이브를 풀어서
#   기존 도구에 그대로 먹이는 편이 훨씬 안전하다. 판정 로직이 단 한 벌로 유지된다.
#
# ── 사용법 ──────────────────────────────────────────────────────────
#   .\Expand-ArchivesForScan.ps1 -Root "D:\lena\AppServer\servers\WDMDB11\webapps" -Out .\_arc
#   .\Scan-ClassFiles.ps1 -Root .\_arc
#
#   중첩 아카이브(war > WEB-INF/lib/*.jar)도 재귀로 따라간다.
#   출력 폴더명이 곧 컨테이너 체인이므로, 스캔 리포트의 File 컬럼만 보고
#   "어느 war 안의 어느 jar" 인지 역추적할 수 있다.
#     예) _arc\portal.war\WEB-INF_lib_common.jar\smart\common\Constants.class
#
# ── 주의 ────────────────────────────────────────────────────────────
#   - 추출본은 조사용 사본이다. 여기서 무엇을 고쳐도 운영본에는 반영되지 않는다
#   - 용량이 크므로 Out 은 작업 드라이브에. 조사 후 삭제해도 무방(재실행 가능)
#   - 50MB 초과 엔트리는 건너뛴다 (Find-AsisPath v8.2와 동일 기준)
# ===========================================================================

param(
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$Out = ".\_arc",
    [string[]]$ArchiveExt = @("*.jar","*.war","*.ear","*.zip"),
    [string]$ListFile,                   # 미지정 시 <Out>\_extracted.dat
    [switch]$Force                       # 기존 Out 폴더가 있어도 진행
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

if (-not (Test-Path $Root)) { Write-Error "경로 없음: $Root"; exit 1 }
$Root = (Resolve-Path $Root).Path.TrimEnd('\')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ((Test-Path $Out) -and -not $Force) {
    Write-Error "출력 폴더가 이미 있음: $Out`n  → 이전 추출본과 섞이면 판정이 오염된다. 삭제하거나 -Force 지정"
    exit 1
}
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$OutFull = (Resolve-Path $Out).Path.TrimEnd('\')
if (-not $ListFile) { $ListFile = Join-Path $OutFull "_extracted.dat" }

$script:records = New-Object System.Collections.Generic.List[object]
$script:count   = 0
$script:skipped = 0

# 폴더명으로 쓸 수 있게 정리 (경로 구분자 -> _)
function ConvertTo-SafeName([string]$s) {
    return ($s -replace '[\\/]','_' -replace '[:*?"<>|]','_')
}

# $stream 안의 .class 를 꺼내고, 중첩 아카이브는 메모리로 재귀
function Expand-Stream([System.IO.Stream]$stream, [string]$destDir, [string]$chain) {
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
    } catch {
        Write-Warning "아카이브 열기 실패: $chain"
        return
    }
    try {
        foreach ($e in $zip.Entries) {
            if ($e.Length -eq 0) { continue }
            if ($e.Length -gt 50MB) { $script:skipped++; continue }

            if ($e.FullName -match '\.(jar|war|ear|zip)$') {
                $ms = New-Object System.IO.MemoryStream
                $es = $e.Open(); $es.CopyTo($ms); $es.Close()
                $ms.Position = 0
                $innerDir = Join-Path $destDir (ConvertTo-SafeName $e.FullName)
                Expand-Stream $ms $innerDir ($chain + " > " + $e.FullName)
                $ms.Dispose()
            }
            elseif ($e.FullName -match '\.class$') {
                $target = Join-Path $destDir ($e.FullName -replace '/','\')
                $tdir = Split-Path $target -Parent
                if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Path $tdir -Force | Out-Null }
                $es = $e.Open()
                $fs = [System.IO.File]::Create($target)
                try { $es.CopyTo($fs) } finally { $fs.Close(); $es.Close() }
                $script:count++
                $script:records.Add([pscustomobject]@{
                    Container = $chain
                    Entry     = $e.FullName
                    Extracted = $target.Substring($OutFull.Length).TrimStart('\')
                    Bytes     = $e.Length
                })
            }
        }
    } finally { $zip.Dispose() }
}

Write-Host "===== Expand-ArchivesForScan v1 ====="
Write-Host "대상: $Root"
Write-Host "출력: $OutFull"
Write-Host ""

$archives = @(Get-ChildItem -Path $Root -Recurse -File -Include $ArchiveExt -ErrorAction SilentlyContinue)
if ($archives.Count -eq 0) { Write-Warning "아카이브 없음: $Root"; exit 1 }

foreach ($a in $archives) {
    $rel  = $a.FullName.Substring($Root.Length).TrimStart('\')
    $dest = Join-Path $OutFull (ConvertTo-SafeName $rel)
    Write-Host "  $rel"
    $fs = [System.IO.File]::OpenRead($a.FullName)
    try { Expand-Stream $fs $dest $rel } finally { $fs.Dispose() }
}

$records | Sort-Object Container, Entry |
    Export-Csv -Path $ListFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "아카이브 $($archives.Count)개 / .class $($script:count)개 추출 (50MB 초과 스킵 $($script:skipped)건)"
Write-Host "목록 -> $ListFile"
Write-Host ""
Write-Host "다음 단계 : .\Scan-ClassFiles.ps1 -Root `"$OutFull`""
