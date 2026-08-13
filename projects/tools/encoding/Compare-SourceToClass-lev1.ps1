# ===========================================================================
# [표준 헤더] Compare-SourceToClass-lev1.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-3  세대 대조 (무컴파일 전수)
#   역할 : 소스 <-> 배포 class 대조: 리터럴·멤버명·역방향 3축. 인라이닝 추적
#   입력 : -ClassRoot WEB-INF\classes, -SrcRoot 소스 루트
#   출력 : Compare-SourceToClass-lev1\<프로젝트>_<일시>.dat (+ -detail)
#   선행 : 없음. 여기서 '소스없음/시그니처불일치'가 많으면 이후 단계 무의미
#   상태 : 현행 (2026-08-02 패치판)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Compare-SourceToClass-lev1.ps1  (2026-08-02 패치판)
# ChangeFlow 소스(.java) ↔ 배포 클래스(.class) 세대/내용 일치 대조 — Level 1 (무컴파일)
#
# [이번 패치 — 반드시 읽을 것]
#   ★ 치명 버그 수정: PowerShell에서 [byte] -shl 8 은 0이 된다 (byte 폭 오버플로).
#     이전 판은 상수풀 256개 이상 / Utf8 길이 256바이트 이상 클래스에서 파싱이 붕괴해
#     "멤버명미발견=디스크립터", "소스만존재리터럴 대량" 오탐을 만들었다. [int] 캐스팅으로 수정.
#   ★ JDK9+ 문자열 연결 레시피("prefix\u0001suffix", \u0001=인자 자리) 자동 처리:
#     조각 단위로 소스 검색, 전부 확인되면 통과. 엑셀에서 \u0001은 <\u0001>로 표기해 출력.
#   ★ "a"+"b" 상수 접기("ab"): 자기 소스 리터럴 조합으로 재구성(DP) 성공 시 자동 통과
#     (detail에 상수접기(자동통과)로 기록만 남김).
#   ★ 역방향(소스에만): 레시피/접기에 흡수된 리터럴(클래스 Utf8 안에 부분 문자열로 존재)은 미보고.
#   ★ enum: values/valueOf 제외 판정 정상화(shl 수정의 부수효과) + enum 상수명이
#     클래스에 String으로 합성되는 것("BBS" 등) 자동 통과.
#   ★ 자기검증: this_class가 파일 경로와 다르면 "파싱검증실패", 멤버명이 디스크립터 형태면
#     "파싱이상" — 이 두 상태는 리터럴/멤버 대조를 하지 않고 격리한다. 이 상태가 나오면 공유 바람.
#   ★ 경로 구분자 / \ 모두 허용 (리눅스/윈도우 겸용).
#
# 판정 로직 (한글 여부와 무관):
#   ① 클래스 상수풀의 "진짜 String 리터럴"(CONSTANT_String이 참조하는 Utf8만) 전체를
#      ASCII 포함으로 뽑아 소스의 리터럴 집합과 대조 (인라이닝은 타 소스까지 검색)
#   ② 클래스의 메서드/필드명을 소스 본문에서 검색 (시그니처 세대 차이 탐지)
#   ③ 역방향: 소스에만 있고 클래스(자기 + 내부클래스 전부)에 없는 리터럴 탐지
#   ④ 깨진 리터럴(FFFD/Latin1/949이중)은 복원값·ASCII 골격으로 소스 검색
#
# 한계(문서화된 오탐 소스 — detail 보고 판단할 것):
#   - Lombok/AP 생성 메서드는 소스에 없음 → 멤버명미발견 오탐 (-SkipNameCheck 로 끔)
#   - 리터럴·시그니처가 하나도 안 바뀐 순수 로직 수정은 탐지 불가 → lev2로 확정
#
# 사용법:
#   .\Compare-SourceToClass-lev1.ps1 -ClassRoot "D:\snap\WEB-INF\classes" -SrcRoot "D:\ChangeFlow\MAR\src"
#   옵션: -ProjectName, -OutFile, -MinLiteralLen 3, -SkipNameCheck, -Delimiter "|"
#
# 출력: .\Compare-SourceToClass-lev1\<프로젝트명>_<yyyyMMdd_HHmmss>.dat (+ -detail.dat)
#   파이프 구분 + UTF-8 BOM. 엑셀은 파일→열기→모든파일→텍스트마법사(65001, 기타 |)로만 열 것.
#
# Status 판정 (우선순위 순):
#   파싱검증실패           : this_class ≠ 파일 경로 (판정 무효 — 파일/도구 점검)
#   파싱이상               : 멤버명이 디스크립터 형태 (판정 무효 — 공유 바람)
#   소스없음               : 대응 .java를 못 찾음 (형상 누락 의심)
#   재컴파일(소스확인)     : 깨진 리터럴이 있고 복원/골격으로도 소스에서 미발견
#   재컴파일(복구가능)     : 깨진 리터럴이 있으나 소스에서 원문 확인됨 → 재컴파일 명단
#   리터럴불일치(클래스에만): 정상 리터럴인데 어떤 소스에서도 미발견 → 소스 구버전 의심
#   시그니처불일치         : 클래스 멤버명이 소스에 없음 → 세대 불일치 의심
#   리터럴불일치(소스에만) : 소스 리터럴이 클래스군(자기+내부)에 없음 → 클래스 구버전 의심
#   일치추정               : 위 어디에도 안 걸림
#   클래스없음             : 소스는 있는데 대응 클래스 미배포
param(
    [Parameter(Mandatory=$true)][string]$ClassRoot,
    [Parameter(Mandatory=$true)][string]$SrcRoot,
    [string]$ProjectName,
    [string]$OutFile,
    [string]$Delimiter = "|",
    [int]$MinLiteralLen = 3,
    [switch]$SkipNameCheck,
    [switch]$ConsoleOnly
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

# [PATCH 2026-08-13] 상수풀 파싱·깨짐 판정을 공용 모듈로 위임 (로직 4벌 중복 해소)
Import-Module (Join-Path $PSScriptRoot '..\common\ClassParser.psm1') -Force


foreach ($p in @($ClassRoot, $SrcRoot)) {
    if (-not (Test-Path $p)) { Write-Error "경로 없음: $p"; exit 1 }
}
$ClassRoot = (Resolve-Path $ClassRoot).Path.TrimEnd('\').TrimEnd('/')
$SrcRoot   = (Resolve-Path $SrcRoot).Path.TrimEnd('\').TrimEnd('/')

# ---------------------------------------------------------------------------
# 출력 경로: .\Compare-SourceToClass-lev1\<프로젝트명>_<일시>.dat
# ---------------------------------------------------------------------------
$scanName = "Compare-SourceToClass-lev1"
if (-not $ProjectName) {
    $generic = @('classes','class','web-inf','lib','target','build','bin','out','dist',
                 'src','main','java','resources','webapp','webcontent','deploy','app','work')
    $parts = $ClassRoot -split '[\\/]'
    for ($k = $parts.Count - 1; $k -ge 0; $k--) {
        $p = $parts[$k]
        if ($p -and ($generic -notcontains $p.ToLower())) { $ProjectName = $p; break }
    }
    if (-not $ProjectName) { $ProjectName = "compare" }
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')

if ($ConsoleOnly) { $OutFile = $null }
elseif (-not $OutFile) {
    $outDir = Join-Path (Get-Location).Path $scanName
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $OutFile = Join-Path $outDir ("{0}_{1}.dat" -f $ProjectName, (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$jdkMap = @{ 45="1.1"; 46="1.2"; 47="1.3"; 48="1.4"; 49="5"; 50="6"; 51="7"; 52="8";
             53="9"; 54="10"; 55="11"; 56="12"; 57="13"; 58="14"; 59="15"; 60="16";
             61="17"; 62="18"; 63="19"; 64="20"; 65="21" }

$ms949      = [System.Text.Encoding]::GetEncoding(949)
$latin1Enc  = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$RECIPE_CH  = [char]1   # JDK9+ makeConcatWithConstants 레시피의 인자 자리표시

# ★ 패치 핵심: 반드시 [int] 캐스팅. [byte] -shl 8 은 PowerShell에서 0이 된다.
function Read-U2($b, [ref]$p) {
    $v = ([int]$b[$p.Value] -shl 8) -bor [int]$b[$p.Value+1]
    $p.Value += 2; return $v
}
function Read-U4($b, [ref]$p) {
    $v = ([long]$b[$p.Value] -shl 24) -bor ([long]$b[$p.Value+1] -shl 16) -bor ([long]$b[$p.Value+2] -shl 8) -bor [long]$b[$p.Value+3]
    $p.Value += 4; return $v
}
# [주의 2026-08-13] 아래 두 함수는 모듈에도 같은 이름이 있으나 반환 형식이 다르다.
#   (모듈: PSCustomObject{Restored;Origin} / 여기: 문자열)
#   스크립트 스코프가 모듈보다 우선하므로 이 파일 안에서는 아래 정의가 쓰인다.
#   깨짐 판정 자체는 이미 모듈의 Test-Mojibake로 옮겼고, 이 둘은 Find-BySkeleton 등
#   보조 경로에서만 쓰인다. 다음 정리 대상 — A/B 대조로 리포트가 동일한지 확인 후 제거할 것.
function Restore-Latin1($s)   { try { return $ms949.GetString($latin1Enc.GetBytes($s)) } catch { return "" } }
function Restore-949Double($s){ try { return $utf8Strict.GetString($ms949.GetBytes($s)) } catch { return $null } }

# 자바 리터럴 이스케이프 해제 ("..." 내부 텍스트 → 실제 값)
function Unescape-JavaLiteral([string]$s) {
    if ($s.IndexOf('\') -lt 0) { return $s }
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -ne '\') { [void]$sb.Append($c); $i++; continue }
        $i++
        if ($i -ge $s.Length) { break }
        $e = $s[$i]
        switch -Regex ([string]$e) {
            '^n$' { [void]$sb.Append([char]10); $i++ }
            '^t$' { [void]$sb.Append([char]9);  $i++ }
            '^r$' { [void]$sb.Append([char]13); $i++ }
            '^b$' { [void]$sb.Append([char]8);  $i++ }
            '^f$' { [void]$sb.Append([char]12); $i++ }
            '^u$' {
                while ($i -lt $s.Length -and $s[$i] -eq 'u') { $i++ }   # \uuuuXXXX 허용
                if ($i + 3 -lt $s.Length) {
                    $hex = $s.Substring($i, 4)
                    $cp = 0
                    if ([int]::TryParse($hex, [System.Globalization.NumberStyles]::HexNumber, $null, [ref]$cp)) {
                        [void]$sb.Append([char]$cp); $i += 4
                    }
                }
            }
            '^[0-7]$' {
                $oct = ""
                while ($i -lt $s.Length -and $oct.Length -lt 3 -and $s[$i] -match '[0-7]') { $oct += $s[$i]; $i++ }
                [void]$sb.Append([char][Convert]::ToInt32($oct, 8))
            }
            default { [void]$sb.Append($e); $i++ }   # \" \\ \' 등
        }
    }
    return $sb.ToString()
}

function Read-SourceText([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        return @{ Text = [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3); Enc = "UTF-8(BOM)" }
    }
    try   { return @{ Text = $utf8Strict.GetString($b); Enc = "UTF-8" } }
    catch { return @{ Text = $ms949.GetString($b);      Enc = "MS949" } }
}

function San([string]$s, [string]$d) {
    if ($null -eq $s) { return "" }
    $s = $s -replace "`r?`n", "\n" -replace [regex]::Escape($d), " "
    return $s.Replace([string]$RECIPE_CH, '<\u0001>')   # 엑셀에서 보이도록 레시피 문자 표기
}

# ---------------------------------------------------------------------------
# 1단계: 소스 트리 스캔 — 패키지 키 인덱스 + 파일별 리터럴 집합 + 전역 리터럴 사전
#   키 = package 선언 기반 (pkg\path\FileName). 트리 레이아웃(src\main\java 등)과 무관.
# ---------------------------------------------------------------------------
Write-Host "소스 스캔: $SrcRoot"
# "문자열" | //주석 | /*주석*/ | '문자' 을 좌→우 교대 매칭 → 그룹1(문자열)만 취함
$tokRe = [regex]'("(?:[^"\\\r\n]|\\.)*")|//[^\r\n]*|/\*[\s\S]*?\*/|''(?:[^''\\\r\n]|\\.)*'''
$pkgRe = [regex]'(?m)^\s*package\s+([\w\.]+)\s*;'

$srcIndex  = @{}   # key(pkg\Name) → @{ Rel; Content; Enc; Lits(HashSet); Dup(List[string]) }
$globalLit = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]'
$srcCount = 0

Get-ChildItem -Path $SrcRoot -Recurse -Filter *.java -File | ForEach-Object {
    $srcCount++
    $rel = ($_.FullName.Substring($SrcRoot.Length).TrimStart('\').TrimStart('/') -replace '/', '\')
    $r = Read-SourceText $_.FullName
    $content = $r.Text

    $pm = $pkgRe.Match($content)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $key = if ($pm.Success) { ($pm.Groups[1].Value -replace '\.', '\') + '\' + $base } else { $base }

    $lits = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $tokRe.Matches($content)) {
        if ($m.Groups[1].Success) {
            $raw = $m.Groups[1].Value
            $val = Unescape-JavaLiteral ($raw.Substring(1, $raw.Length - 2))
            if ($val.Length -gt 0) { [void]$lits.Add($val) }
        }
    }

    $entry = @{ Rel = $rel; Content = $content; Enc = $r.Enc; Lits = $lits; Dup = (New-Object System.Collections.Generic.List[string]) }
    if ($srcIndex.ContainsKey($key)) { $srcIndex[$key].Dup.Add($rel) }   # 동일 클래스 소스 중복
    else { $srcIndex[$key] = $entry }

    foreach ($v in $lits) {
        if ($v.Length -lt $MinLiteralLen) { continue }
        if (-not $globalLit.ContainsKey($v)) { $globalLit[$v] = New-Object System.Collections.Generic.List[string] }
        if ($globalLit[$v].Count -lt 5) { $globalLit[$v].Add($key) }
    }
}
Write-Host "  소스 $srcCount 건, 키 $($srcIndex.Count) 건, 전역 리터럴 $($globalLit.Count) 종"

# ---------------------------------------------------------------------------
# 2단계: 클래스 파싱 — 태그8(String) 참조 Utf8만 리터럴로, 필드/메서드명 추출
# ---------------------------------------------------------------------------
Write-Host "클래스 스캔: $ClassRoot"

function Parse-ClassFile([byte[]]$bytes) {
    if ($bytes.Length -lt 10 -or $bytes[0] -ne 0xCA -or $bytes[1] -ne 0xFE) { return $null }
    $pos = 4
    $null  = Read-U2 $bytes ([ref]$pos)   # minor
    $major = Read-U2 $bytes ([ref]$pos)
    $cpCount = Read-U2 $bytes ([ref]$pos)

    $utf8 = @{}          # index → string
    $strRef  = New-Object System.Collections.Generic.List[int]   # 태그8 → utf8 인덱스
    $classRef = @{}      # 태그7 인덱스 → name utf8 인덱스 (this_class 검증용)
    $i = 1
    $parseErr = $null
    try {
        while ($i -lt $cpCount) {
            $tag = [int]$bytes[$pos]; $pos++
            switch ($tag) {
                1  { $len = Read-U2 $bytes ([ref]$pos)
                     $utf8[$i] = [System.Text.Encoding]::UTF8.GetString($bytes, $pos, $len)
                     $pos += $len }
                7  { $classRef[$i] = Read-U2 $bytes ([ref]$pos) }
                8  { $strRef.Add((Read-U2 $bytes ([ref]$pos))) }
                { $_ -in 3,4 }           { $pos += 4 }
                { $_ -in 5,6 }           { $pos += 8; $i++ }   # long/double은 2슬롯
                { $_ -in 16,19,20 }      { $pos += 2 }
                { $_ -in 9,10,11,12,17,18 } { $pos += 4 }
                15 { $pos += 3 }
                default { $parseErr = "알 수 없는 태그 $tag (엔트리 $i)"; $i = $cpCount }
            }
            $i++
        }
    } catch { $parseErr = "상수풀 파싱 예외: $($_.Exception.Message)" }
    if ($parseErr) { return @{ Error = $parseErr } }

    $classAcc = Read-U2 $bytes ([ref]$pos)
    $thisIdx  = Read-U2 $bytes ([ref]$pos)
    $null     = Read-U2 $bytes ([ref]$pos)               # super_class
    $thisName = $null
    if ($classRef.ContainsKey($thisIdx) -and $utf8.ContainsKey($classRef[$thisIdx])) {
        $thisName = $utf8[$classRef[$thisIdx]]           # 예: egovframework/com/cmm/web/EgovKind
    }
    $ifc = Read-U2 $bytes ([ref]$pos); $pos += 2 * $ifc

    $names = New-Object System.Collections.Generic.List[string]
    $enumConsts = New-Object 'System.Collections.Generic.HashSet[string]'
    $isEnum = (($classAcc -band 0x4000) -ne 0)
    $badNames = 0
    try {
        foreach ($section in 1..2) {                      # 1=fields 2=methods
            $cnt = Read-U2 $bytes ([ref]$pos)
            for ($m = 0; $m -lt $cnt; $m++) {
                $acc  = Read-U2 $bytes ([ref]$pos)
                $nIdx = Read-U2 $bytes ([ref]$pos)
                $pos += 2                                 # descriptor
                $aCnt = Read-U2 $bytes ([ref]$pos)
                for ($a = 0; $a -lt $aCnt; $a++) {
                    $pos += 2
                    $alen = Read-U4 $bytes ([ref]$pos)
                    $pos += $alen
                }
                $nm = $utf8[$nIdx]
                if (-not $nm) { continue }
                # 자기검증: 멤버명이 디스크립터/경로 형태면 파싱이 밀린 것 — 격리 신호
                if ($nm -match '[();/\[]') { $badNames++; continue }
                if ($isEnum -and $section -eq 1 -and (($acc -band 0x4000) -ne 0)) { [void]$enumConsts.Add($nm) }
                if (($acc -band 0x1000) -ne 0 -or ($acc -band 0x0040) -ne 0) { continue }  # synthetic/bridge
                if ($nm -match '[\$<]') { continue }                                        # 내부/생성자
                if ($isEnum -and ($nm -in @('values','valueOf','ordinal'))) { continue }
                $names.Add($nm)
            }
        }
    } catch { return @{ Error = "멤버 파싱 예외: $($_.Exception.Message)" } }

    $lits = New-Object System.Collections.Generic.List[string]
    foreach ($idx in $strRef) { if ($utf8.ContainsKey($idx)) { $lits.Add($utf8[$idx]) } }
    $allUtf8 = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($v in $utf8.Values) { [void]$allUtf8.Add($v) }   # 역방향 대조용 (애너테이션 값 포함)

    return @{ Major = $major; Lits = $lits; Names = $names; AllUtf8 = $allUtf8
              ThisName = $thisName; BadNames = $badNames; IsEnum = $isEnum; EnumConsts = $enumConsts }
}

# FFFD 골격 검색: 살아남은 조각들을 순서대로 포함하는 리터럴이 있는지
function Find-BySkeleton([string]$broken, $ownLits, $global) {
    $segs = @($broken -split "\uFFFD+" | Where-Object { $_.Length -gt 0 })
    $total = 0; foreach ($sg in $segs) { $total += $sg.Length }
    if ($total -lt 3) { return @{ Result = "SKELETON부족"; Where = "" } }
    $pat = ($segs | ForEach-Object { [regex]::Escape($_) }) -join '.*'
    foreach ($cand in $ownLits) { if ($cand -match $pat) { return @{ Result = "OWN"; Where = $cand } } }
    foreach ($cand in $global.Keys) {
        if ($cand -match $pat) { return @{ Result = "OTHER"; Where = "$cand @ $($global[$cand][0])" } }
    }
    return @{ Result = "NOTFOUND"; Where = $pat }
}

# 레시피/일반 조각 하나가 소스에서 확인되는가 (자기 소스 우선 → 전역 → 원문 포함)
function Test-FragmentInSource([string]$frag, $src, $global) {
    if ($src.Lits.Contains($frag)) { return $true }
    foreach ($cand in $src.Lits) { if ($cand.Length -gt $frag.Length -and $cand.Contains($frag)) { return $true } }
    if ($global.ContainsKey($frag)) { return $true }
    if ($src.Content.Contains($frag)) { return $true }   # "a"+"b" 접기로 갈라진 경계 대응
    return $false
}

# "a"+"b" 상수 접기 재구성: L을 자기 소스 리터럴들의 연접으로 만들 수 있는가 (DP)
function Test-ConstantFolding([string]$L, $src) {
    if ($L.Length -gt 400) { return $false }
    $n = $L.Length
    $reach = New-Object bool[] ($n + 1)
    $reach[0] = $true
    for ($p = 0; $p -lt $n; $p++) {
        if (-not $reach[$p]) { continue }
        foreach ($piece in $src.Lits) {
            $pl = $piece.Length
            if ($pl -eq 0 -or $p + $pl -gt $n) { continue }
            if ($pl -eq $n) { continue }                       # 전체 일치는 이미 위에서 검사됨
            if ([string]::CompareOrdinal($L, $p, $piece, 0, $pl) -eq 0) { $reach[$p + $pl] = $true }
        }
    }
    return $reach[$n]
}

$rows    = New-Object System.Collections.Generic.List[object]
$details = New-Object System.Collections.Generic.List[object]
$bySrc   = @{}   # srcKey → @{ Union(HashSet); Primary(row); OwnEntry }
$classCount = 0

Get-ChildItem -Path $ClassRoot -Recurse -Filter *.class -File | ForEach-Object {
    $classCount++
    $rel = ($_.FullName.Substring($ClassRoot.Length).TrimStart('\').TrimStart('/') -replace '/', '\')
    $pc = Parse-ClassFile ([System.IO.File]::ReadAllBytes($_.FullName))
    if ($null -eq $pc) { Write-Warning "클래스 파일 아님: $rel"; return }

    $baseNoExt = $rel.Substring(0, $rel.Length - 6)                 # ".class" 제거
    $fileName  = ($baseNoExt -split '\\')[-1]
    $outerName = ($fileName -split '\$')[0]                          # 내부클래스 → 외부 기준
    $dir = if ($baseNoExt.Contains('\')) { $baseNoExt.Substring(0, $baseNoExt.LastIndexOf('\')) } else { '' }
    $srcKey = if ($dir) { $dir + '\' + $outerName } else { $outerName }
    $isPrimary = ($fileName -eq $outerName)

    # --- 자기검증: 파싱 자체가 실패/이상이면 격리 (대조하지 않음) ---
    if ($pc.ContainsKey('Error')) {
        $rows.Add([PSCustomObject]@{
            ClassFile = $rel; SrcFile = ""; JDK = "?"; Status = "파싱검증실패"
            Lit=""; FoundOwn=""; Inline=""; Broken=""; NotFound=""; SrcOnly=""; NameMiss=""; Note=$pc.Error })
        $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="파싱검증실패"; Value=$pc.Error; Note="" })
        return
    }
    $jdk = if ($jdkMap.ContainsKey([int]$pc.Major)) { $jdkMap[[int]$pc.Major] } else { "?($($pc.Major))" }
    $expectName = ($baseNoExt -replace '\\', '/')
    if ($pc.ThisName -and ($pc.ThisName -ne $expectName)) {
        $rows.Add([PSCustomObject]@{
            ClassFile = $rel; SrcFile = ""; JDK = $jdk; Status = "파싱검증실패"
            Lit=""; FoundOwn=""; Inline=""; Broken=""; NotFound=""; SrcOnly=""; NameMiss=""
            Note = "this_class=$($pc.ThisName) ≠ 경로" })
        $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="파싱검증실패"; Value="this_class=$($pc.ThisName)"; Note="경로와 불일치" })
        return
    }
    if ($pc.BadNames -gt 0) {
        $rows.Add([PSCustomObject]@{
            ClassFile = $rel; SrcFile = ""; JDK = $jdk; Status = "파싱이상"
            Lit=""; FoundOwn=""; Inline=""; Broken=""; NotFound=""; SrcOnly=""; NameMiss=""
            Note = "디스크립터형 멤버명 $($pc.BadNames)건 — 판정 무효, 공유 바람" })
        $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="파싱이상"; Value="디스크립터형 멤버명 $($pc.BadNames)건"; Note="" })
        return
    }

    $src = $null
    if ($srcIndex.ContainsKey($srcKey)) { $src = $srcIndex[$srcKey] }

    $foundOwn = 0; $foundInline = 0; $notFound = 0
    $brokenTotal = 0; $brokenNotFound = 0
    $nameMiss = 0
    $note = ""

    if ($null -eq $src) {
        $status = "소스없음"
    }
    else {
        if ($src.Dup.Count -gt 0) {
            $note = "중복소스:" + ($src.Dup -join ",")
            $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="중복소스"; Value=$src.Rel; Note=($src.Dup -join ",") })
        }
        $litSeen = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($L in $pc.Lits) {
            if ($L.Length -lt $MinLiteralLen) { continue }
            if (-not $litSeen.Add($L)) { continue }

            # --- JDK9+ 문자열 연결 레시피: \u0001 조각 단위로 검증 ---
            if ($L.IndexOf($RECIPE_CH) -ge 0) {
                $frags = @(($L -split [string]$RECIPE_CH) | Where-Object { $_.Length -ge $MinLiteralLen })
                $missFrag = $null
                foreach ($fg in $frags) {
                    if (Test-FragmentInSource $fg $src $globalLit) { continue }
                    # 접힌 숫자 상수(long/double 등)가 레시피에 박힌 경우: 숫자를 떼고 남은 텍스트만 검사
                    $subs = @(($fg -split '[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?') | Where-Object { $_.Length -ge $MinLiteralLen })
                    $subOk = $true
                    foreach ($sb2 in $subs) {
                        if (-not (Test-FragmentInSource $sb2 $src $globalLit)) { $subOk = $false; break }
                    }
                    if (-not $subOk) { $missFrag = $fg; break }
                }
                if ($null -eq $missFrag) { $foundOwn++ }             # 조각 전부 확인(조각 없음 포함) → 통과
                else {
                    $notFound++
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="클래스만존재리터럴"; Value=$L; Note="레시피 조각 미발견: $missFrag" })
                }
                continue
            }

            if ($L -match "\uFFFD") {
                $brokenTotal++
                $r = Find-BySkeleton $L $src.Lits $globalLit
                if ($r.Result -in @("OWN","OTHER")) {
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-복구발견($($r.Result))"; Value=$L; Note=$r.Where })
                } else {
                    $brokenNotFound++
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-$($r.Result)"; Value=$L; Note=$r.Where })
                }
                continue
            }

            # [PATCH 2026-08-13] 판정을 ClassParser 모듈로 위임.
            #   구 로직은 이랬다:
            #       if ($L -match "[\u00A1-\u00FF]") { $restored = Restore-Latin1 $L }
            #       elseif ($L -match "[\uAC00-\uD7A3]") { ... }
            #   Latin-1 검사가 한글 검사보다 먼저라, 정상 한글에 '·'(U+00B7)가 섞이면
            #   한글인지 보기도 전에 깨짐으로 단정하고 역변환해 전부 '?'가 됐다.
            #   실제 오탐: "static final String 상수 변경 시 참조 클래스 전부 재컴파일·재배포 필요"
            #   Scan-ClassFiles에는 8/12에 적용된 수정이 이 파일엔 빠져 있었다.
            #
            #   모듈은 (1) 한글 검사 우선 (2) 역변환 성립 + 길이 감소 두 조건을 함께 본다.
            $verdict  = Test-Mojibake $L
            $restored = $null
            $restoredOrigin = ""
            if ($verdict.Type -eq "깨짐949이중" -or $verdict.Type -eq "깨짐Latin1") {
                $restored = $verdict.Restored
                $restoredOrigin = $verdict.Origin
            }
            if ($restored) {
                $brokenTotal++
                if ($src.Lits.Contains($restored)) {
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-복구발견(OWN)"; Value=$L; Note=$restored })
                }
                elseif ($globalLit.ContainsKey($restored)) {
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-복구발견(OTHER)"; Value=$L; Note="$restored @ $($globalLit[$restored][0])" })
                }
                elseif (Test-ConstantFolding $restored $src) {
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-복구발견(OWN·접기)"; Value=$L; Note=$restored })
                }
                else {
                    $brokenNotFound++
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="깨짐-NOTFOUND"; Value=$L; Note=$restored })
                }
                continue
            }

            if ($src.Lits.Contains($L)) { $foundOwn++ }
            elseif ($pc.IsEnum -and $pc.EnumConsts.Contains($L)) { $foundOwn++ }   # enum 상수명 합성 리터럴
            elseif ($globalLit.ContainsKey($L)) {
                $foundInline++
                $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="인라이닝"; Value=$L; Note=("정의: " + ($globalLit[$L] -join ",")) })
            }
            elseif (Test-ConstantFolding $L $src) {
                $foundOwn++
                $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="상수접기(자동통과)"; Value=$L; Note="소스 리터럴 조합으로 재구성됨" })
            }
            else {
                $notFound++
                $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="클래스만존재리터럴"; Value=$L; Note="" })
            }
        }

        if (-not $SkipNameCheck) {
            foreach ($nm in ($pc.Names | Select-Object -Unique)) {
                if (-not [regex]::IsMatch($src.Content, "\b" + [regex]::Escape($nm) + "\b")) {
                    $nameMiss++
                    $details.Add([PSCustomObject]@{ ClassFile=$rel; Kind="멤버명미발견"; Value=$nm; Note="" })
                }
            }
        }

        if     ($brokenNotFound -gt 0) { $status = "재컴파일(소스확인)" }
        elseif ($brokenTotal    -gt 0) { $status = "재컴파일(복구가능)" }
        elseif ($notFound       -gt 0) { $status = "리터럴불일치(클래스에만)" }
        elseif ($nameMiss       -gt 0) { $status = "시그니처불일치" }
        else                           { $status = "일치추정" }
    }

    $row = [PSCustomObject]@{
        ClassFile = $rel;  SrcFile = $(if ($src) { $src.Rel } else { "" })
        JDK = $jdk; Status = $status
        Lit = $foundOwn + $foundInline + $notFound + $brokenTotal
        FoundOwn = $foundOwn; Inline = $foundInline; Broken = $brokenTotal
        NotFound = $notFound; SrcOnly = ""; NameMiss = $nameMiss; Note = $note
    }
    $rows.Add($row)

    if ($src) {
        if (-not $bySrc.ContainsKey($srcKey)) {
            $bySrc[$srcKey] = @{ Union = (New-Object 'System.Collections.Generic.HashSet[string]'); Primary = $null; Src = $src }
        }
        $bySrc[$srcKey].Union.UnionWith($pc.AllUtf8)
        if ($isPrimary) { $bySrc[$srcKey].Primary = $row }
    }
}
Write-Host "  클래스 $classCount 건"

# ---------------------------------------------------------------------------
# 3단계: 역방향 (소스에만 있는 리터럴) + 클래스없음
# ---------------------------------------------------------------------------
foreach ($k in $bySrc.Keys) {
    $g = $bySrc[$k]
    # 이미 재컴파일 판정이면 역방향 생략 — 깨진 리터럴의 원문이 "소스에만 있다"고 중복 보고되는 노이즈 차단
    if ($g.Primary -and $g.Primary.Status -like "재컴파일*") { continue }
    $srcOnly = 0
    foreach ($v in $g.Src.Lits) {
        if ($v.Length -lt $MinLiteralLen) { continue }
        if ($g.Union.Contains($v)) { continue }
        # 레시피("prefix\u0001")나 상수 접기("ab")에 흡수된 경우: 클래스 Utf8 안에 부분 문자열로 존재
        $absorbed = $false
        foreach ($u in $g.Union) {
            if ($u.Length -gt $v.Length -and $u.Contains($v)) { $absorbed = $true; break }
        }
        if ($absorbed) { continue }
        $srcOnly++
        $cf = if ($g.Primary) { $g.Primary.ClassFile } else { "($k)" }
        $details.Add([PSCustomObject]@{ ClassFile=$cf; Kind="소스만존재리터럴"; Value=$v; Note="src=$($g.Src.Rel)" })
    }
    if ($g.Primary) {
        $g.Primary.SrcOnly = $srcOnly
        if ($srcOnly -gt 0 -and $g.Primary.Status -eq "일치추정") {
            $g.Primary.Status = "리터럴불일치(소스에만)"
        }
    }
}

$claimed = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in $bySrc.Keys) { [void]$claimed.Add($k) }
foreach ($k in $srcIndex.Keys) {
    if (-not $claimed.Contains($k)) {
        $rows.Add([PSCustomObject]@{
            ClassFile = "-"; SrcFile = $srcIndex[$k].Rel; JDK = "-"; Status = "클래스없음"
            Lit = ""; FoundOwn = ""; Inline = ""; Broken = ""; NotFound = ""; SrcOnly = ""; NameMiss = ""; Note = ""
        })
    }
}

# ---------------------------------------------------------------------------
# 저장 + 요약
# ---------------------------------------------------------------------------
$cols = @("ClassFile","SrcFile","JDK","Status","Lit","FoundOwn","Inline","Broken","NotFound","SrcOnly","NameMiss","Note")
if ($OutFile) {
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($cols -join $Delimiter)
    foreach ($r in $rows) {
        $lines.Add((($cols | ForEach-Object { San ([string]$r.$_) $Delimiter }) -join $Delimiter))
    }
    [System.IO.File]::WriteAllLines($OutFile, $lines, $utf8Bom)
    Write-Host ""
    Write-Host "프로젝트  : $ProjectName"
    Write-Host "저장 완료 : $OutFile ($($rows.Count) 건)"

    if ($details.Count -gt 0) {
        $detFile = [System.IO.Path]::Combine(
            [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutFile)),
            [System.IO.Path]::GetFileNameWithoutExtension($OutFile) + "-detail" + [System.IO.Path]::GetExtension($OutFile))
        $dl = New-Object System.Collections.Generic.List[string]
        $dl.Add(("ClassFile","Kind","Value","Note") -join $Delimiter)
        foreach ($d in $details) {
            $dl.Add((@($d.ClassFile, $d.Kind, (San $d.Value $Delimiter), (San $d.Note $Delimiter)) -join $Delimiter))
        }
        [System.IO.File]::WriteAllLines($detFile, $dl, $utf8Bom)
        Write-Host "상세      : $detFile ($($details.Count) 건)"
    }
}
else {
    $rows
}

Write-Host ""
Write-Host "총 클래스 $classCount / 소스 $srcCount"
$rows | Group-Object Status | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,-24} {1,6} 건" -f $_.Name, $_.Count)
}
