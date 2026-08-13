# ===========================================================================
# [표준 헤더] Scan-ClassFiles.ps1
#   계열 : B (인코딩 진단)
#   단계 : B-4  현황 조사 (class측) ★핵심
#   역할 : .class 상수풀 스캔 — 깨짐 판정 + JDK major + 소스 인코딩 연계
#   입력 : -Root classes 폴더, -SourceRoot .java 루트(선택)
#   출력 : Scan-ClassFiles\<프로젝트>_<일시>.dat (+ -literals)
#   선행 : jar/war 내부를 보려면 Expand-ArchivesForScan.ps1 로 먼저 추출
#   상태 : 현행 (판정 1순위 근거. javap은 대조용 참고)
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# ===========================================================================
# Scan-ClassFiles.ps1
#   .class 파일 일괄 스캔: 컴파일 JDK 버전 + 한글 리터럴 깨짐 여부 + 인코딩 추정
#   (-SourceRoot 지정 시 원본 소스 인코딩과 리터럴 소스 라인번호까지 표시)
# ===========================================================================
#
# ---------------------------------------------------------------------------
# [실행 전 준비] PowerShell 에서 스크립트 돌릴 때 매번 걸리는 것들
# ---------------------------------------------------------------------------
#
# 1) 실행 정책 (UnauthorizedAccess / "디지털 서명되지 않았습니다" 오류)
#    가장 간단 - 별도 프로세스로 우회 (관리자 권한 불필요, 시스템 설정 안 건드림):
#        powershell -ExecutionPolicy Bypass -File .\Scan-ClassFiles.ps1 -Root "D:\..."
#    또는 현재 창에서만 허용 (창 닫으면 원복):
#        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#    현재 정책 확인:
#        Get-ExecutionPolicy -List
#    RemoteSigned 인데 막히면 인터넷 출처 마크 때문이므로:
#        Unblock-File .\Scan-ClassFiles.ps1
#    MachinePolicy 에 값이 박혀 있으면 GPO 강제라 Bypass 도 무시될 수 있음
#    -> 그때는 스크립트 내용을 콘솔에 붙여넣어 실행 (붙여넣기는 정책 대상 아님)
#
# 2) 이 파일은 반드시 UTF-8 with BOM 으로 저장할 것  ★중요★
#    Windows PowerShell 5.1 은 BOM 없는 파일을 시스템 ANSI(MS949)로 읽는다.
#    그러면 주석/문자열의 한글이 깨지고, 깨진 바이트가 따옴표를 삼켜서
#    "예기치 않은 토큰" 같은 엉뚱한 구문 오류가 무더기로 발생한다.
#    확인:  [System.IO.File]::ReadAllBytes(".\Scan-ClassFiles.ps1")[0..2]
#           -> 239 187 191 이면 정상
#    복구:  $p = ".\Scan-ClassFiles.ps1"
#           $t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
#           [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))
#    (PowerShell 7 은 BOM 없어도 UTF-8 로 읽으므로 이 문제 없음)
#
# 3) 콘솔 한글 출력 (-DumpLiterals 로 리터럴 원문 볼 때만 필요)
#        chcp 65001
#        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#    콘솔 코드페이지와 PowerShell 출력 인코딩 둘 다 맞춰야 한다.
#    한쪽만 바꾸면 여전히 깨진다.
#    ※ 판정 결과 자체는 콘솔 설정과 무관하다. 파일 저장은 항상 UTF-8 BOM.
#
# 4) 회사 PC DRM
#    csv / txt 는 자동 암호화 대상이므로 출력 확장자는 .dat 를 쓴다 (기본값).
#
# ---------------------------------------------------------------------------
# [사용법]
# ---------------------------------------------------------------------------
#   .\Scan-ClassFiles.ps1 -Root "D:\...\WEB-INF\classes"
#       -> 현재 위치에 .\Scan-ClassFiles\ 폴더 자동 생성
#       -> <프로젝트명>_<yyyyMMdd_HHmmss>.dat / -literals.dat 자동 저장
#         (프로젝트명은 Root 경로에서 자동 추출: classes/WEB-INF/target 등은 건너뜀)
#
#   .\Scan-ClassFiles.ps1 -Root ... -SourceRoot "D:\...\src\main\java"
#                                                   # 소스 인코딩 + 라인번호 표시
#   .\Scan-ClassFiles.ps1 -Root ... -ProjectName MAR             # 프로젝트명 직접 지정
#   .\Scan-ClassFiles.ps1 -Root ... -OutFile D:\scan.dat         # 출력 경로 직접 지정
#   .\Scan-ClassFiles.ps1 -Root ... -ConsoleOnly                 # 파일 저장 없이 콘솔만
#   .\Scan-ClassFiles.ps1 -Root ... -DumpLiterals                # 콘솔에 리터럴 원문 출력
#
# ---------------------------------------------------------------------------
# [엑셀에서 열기]  Power Query / 웹 가져오기 쓰지 말 것 (HTML 로 오판함)
# ---------------------------------------------------------------------------
#   엑셀 -> 파일 -> 열기 -> 찾아보기 -> 파일 형식 "모든 파일" -> .dat 선택
#   -> 텍스트 마법사 자동 실행 -> 구분 기호 "기타"에 | 입력 -> 마침
#
# ---------------------------------------------------------------------------
# [컬럼 설명]
# ---------------------------------------------------------------------------
# 요약 파일 (<프로젝트명>_<일시>.dat)
#   File     : classes 루트 기준 상대경로
#   JDK/Major: class 파일 major version 과 대응 JDK (50=1.6, 51=1.7, 52=1.8 ...)
#   Status   : 한글정상 / 깨짐(Latin1) / 깨짐(949이중) / 손실(FFFD) / ASCII만 / 파싱실패
#   Encoding : 추정 컴파일 인코딩 (아래 표)
#   SrcEnc   : .java 원본 파일의 실제 인코딩 (-SourceRoot 지정 시에만)
#   Broken   : 깨진 리터럴 개수 / Hangul : 정상 한글 리터럴 개수
#
# 상세 파일 (<프로젝트명>_<일시>-literals.dat)
#   Line     : 해당 리터럴이 나오는 소스 라인번호 (-SourceRoot 지정 시, 최대 5개)
#   Literal  : class 에 저장된 현재 문자열 / Restored : 복원된 원문
#
# Encoding 값
#   인코딩일치       : 소스 인코딩과 javac -encoding 이 일치해 한글이 온전함
#                      ※ 이 경우 원본이 UTF-8 이었는지 MS949 였는지는 class 파일만으로
#                         알 수 없다. class 는 항상 modified UTF-8 로 저장되기 때문.
#                         원본 인코딩을 알려면 -SourceRoot 를 지정해 SrcEnc 를 볼 것.
#   Latin1(UTF8소스) : UTF-8 소스를 -encoding ISO-8859-1 로 컴파일 -> 복원 가능
#   Latin1(949소스)  : MS949 소스를 -encoding ISO-8859-1 로 컴파일 -> 복원 가능
#   MS949오컴파일    : UTF-8 문자열을 MS949 로 재해석 -> 복원 가능
#   UTF-8오컴파일    : MS949 소스를 UTF-8 로 컴파일 -> U+FFFD 치환, 원본 손실 (복원 불가)
#   파싱실패         : 상수풀 구조가 예상과 달라 중단 (조용히 빠지지 않도록 별도 표기)
#   -               : ASCII 만 있어 판별 불가
#
# ---------------------------------------------------------------------------
# [판정 방식]
# ---------------------------------------------------------------------------
#   문자 범위로 추정하지 않고 "역변환이 성립하는가" 로 판정한다.
#   깨진 문자열만 원래 바이트로 되돌렸을 때 유효한 시퀀스로 복원되며 길이가 줄어든다.
#   덕분에 ·(U+00B7) é € 같은 정상 특수문자를 깨짐으로 오판하지 않는다.
#
#   class 파일 자체에는 리터럴의 소스 라인번호가 없다.
#   (LineNumberTable 은 바이트코드 오프셋 매핑이라 상수풀과 연결되지 않음)
#   따라서 Line 컬럼은 .java 파일에서 문자열을 직접 찾아 채운다.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$SourceRoot,           # .java 소스 루트. 지정 시 소스 인코딩 + 라인번호 컬럼 채움
    [string]$ProjectName,          # 미지정 시 Root 경로에서 자동 추출
    [string]$OutFile,              # 미지정 시 .\Scan-ClassFiles\<프로젝트명>_<일시>.dat 자동 생성
    [string]$Delimiter = "|",
    [switch]$DumpLiterals,
    [switch]$ConsoleOnly           # 파일 저장 없이 콘솔 객체 출력만 (파이프 필터링용)
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
#   PS의 Get-Location 과 .NET의 [Environment]::CurrentDirectory 는 별개다.
#   powershell.exe 를 다른 폴더에서 켠 뒤 cd 로 옮겨오면 후자는 시작 폴더(보통 C:\Users\<계정>)에
#   그대로 남아 있어, New-Item 으로 만든 폴더와 [System.IO.File]::Write* 가 쓰는 폴더가 달라진다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

if (-not (Test-Path $Root)) { Write-Error "경로 없음: $Root"; exit 1 }
$Root = (Resolve-Path $Root).Path.TrimEnd('\')

# ---------------------------------------------------------------------------
# 출력 경로 자동 결정: .\Scan-ClassFiles\<프로젝트명>_<일시>.dat
# ---------------------------------------------------------------------------
$scanName = "Scan-ClassFiles"
if (-not $ProjectName) {
    # 경로 끝에서부터 올라가며, 범용 폴더명(빌드 산출물/구조 폴더)은 건너뛰고
    # 처음 만나는 의미 있는 폴더명을 프로젝트명으로 사용
    $generic = @('classes','class','web-inf','lib','target','build','bin','out','dist',
                 'src','main','java','resources','webapp','webcontent','deploy','app','work')
    $parts = $Root -split '\\'
    for ($k = $parts.Count - 1; $k -ge 0; $k--) {
        $p = $parts[$k]
        if ($p -and ($generic -notcontains $p.ToLower())) { $ProjectName = $p; break }
    }
    if (-not $ProjectName) { $ProjectName = "scan" }
}
$ProjectName = ($ProjectName -replace '[\\/:*?"<>|]', '_')   # 파일명 금지 문자 제거

if ($ConsoleOnly) {
    $OutFile = $null
}
elseif (-not $OutFile) {
    $outDir = Join-Path (Get-Location).Path $scanName
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $OutFile = Join-Path $outDir ("{0}_{1}.dat" -f $ProjectName, (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$jdkMap = @{ 45="1.1"; 46="1.2"; 47="1.3"; 48="1.4"; 49="5"; 50="6"; 51="7"; 52="8";
             53="9"; 54="10"; 55="11"; 56="12"; 57="13"; 58="14"; 59="15"; 60="16";
             61="17"; 62="18"; 63="19"; 64="20"; 65="21"; 66="22"; 67="23"; 68="24" }

# 치환 대신 예외를 던지는 엄격 인코더/디코더 (역변환 판정의 전제 조건)
$encFail    = New-Object System.Text.EncoderExceptionFallback
$decFail    = New-Object System.Text.DecoderExceptionFallback
$ms949      = [System.Text.Encoding]::GetEncoding(949,   $encFail, $decFail)
$latin1Enc  = [System.Text.Encoding]::GetEncoding(28591, $encFail, $decFail)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$rxHangul   = [regex] "[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]"
$rxHighLat  = [regex] "[\u0080-\u00FF]"

# 주의: PowerShell 은 -shl 의 결과 타입을 왼쪽 피연산자 타입으로 유지한다.
#       [byte] 를 -shl 8 하면 byte 범위를 넘어 0 으로 잘리므로 반드시 [int] 로 캐스팅할 것.
#       (이 캐스팅이 없으면 상수풀 256개 이상 / 256바이트 이상 문자열에서 desync 발생)
function Read-U2($b, [ref]$p) { $v = ((([int]$b[$p.Value]) -shl 8) -bor ([int]$b[$p.Value+1])); $p.Value += 2; return $v }

# Latin-1 모지바케 판정/복원
#   문자를 Latin-1 바이트로 되돌린 뒤 UTF-8 / MS949 두 경로로 재해석한다.
#   깨진 문자열은 원래 1글자가 2~3문자로 부풀어 있으므로 복원되면 반드시 짧아진다.
#   정상 특수문자(· é €)는 되돌려도 유효한 시퀀스가 안 나와 예외로 걸러진다.
function Restore-Latin1($s) {
    try { $raw = $latin1Enc.GetBytes($s) } catch { return $null }

    # (a) UTF-8 소스를 Latin-1로 컴파일한 경우
    try {
        # UTF-8 경로는 엄격 디코더가 통과한 것 자체가 강한 증거라 한글 조건을 걸지 않는다.
        # (한글이 아닌 é ü 같은 문자가 깨진 경우도 정확히 복원됨)
        $u = $utf8Strict.GetString($raw)
        if ($u.Length -lt $s.Length) {
            return [PSCustomObject]@{ Restored = $u; Origin = "UTF8소스" }
        }
    } catch { }

    # (b) MS949 소스를 Latin-1로 컴파일한 경우
    try {
        $k = $ms949.GetString($raw)
        if ($k.Length -lt $s.Length -and $rxHangul.IsMatch($k)) {
            return [PSCustomObject]@{ Restored = $k; Origin = "949소스" }
        }
    } catch { }

    return $null
}

# MS949 이중해석 판정: 문자를 949 바이트로 되돌린 뒤 UTF-8 strict로 읽음
#   겉보기엔 한글이지만 실제로는 UTF-8 바이트를 MS949로 읽은 결과인 경우를 잡는다.
function Restore-949Double($s) {
    try { $raw = $ms949.GetBytes($s) } catch { return $null }
    try {
        $u = $utf8Strict.GetString($raw)
        if ($u.Length -lt $s.Length -and $rxHangul.IsMatch($u)) { return $u }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
# 소스 파일 연계 (-SourceRoot 지정 시에만 동작)
#   class 파일만으로는 (1) 정상 컴파일된 원본 인코딩 (2) 리터럴의 소스 라인번호
#   두 가지를 알 수 없다. class 는 항상 modified UTF-8 로 저장되고,
#   LineNumberTable 은 바이트코드 오프셋만 담기 때문이다.
#   따라서 .java 파일을 직접 읽어서 두 정보를 보충한다.
# ---------------------------------------------------------------------------
$javaIndex = $null
$srcCache  = @{}

function Init-JavaIndex {
    if (-not $SourceRoot) { return }
    if (-not (Test-Path $SourceRoot)) { Write-Warning "SourceRoot 없음: $SourceRoot"; $script:SourceRoot = $null; return }
    $script:SourceRoot = (Resolve-Path $SourceRoot).Path.TrimEnd('\')
    $idx = @{}
    Get-ChildItem -Path $script:SourceRoot -Recurse -Filter *.java -File | ForEach-Object {
        $k = $_.Name.ToLower()
        if (-not $idx.ContainsKey($k)) { $idx[$k] = New-Object System.Collections.Generic.List[string] }
        $idx[$k].Add($_.FullName)
    }
    $script:javaIndex = $idx
    Write-Host "소스 인덱스: $($idx.Count) 개 .java 파일"
}

function Get-JavaPath([string]$relClass) {
    if (-not $javaIndex) { return $null }
    $rel = $relClass -replace '\.class$', ''
    $rel = $rel -replace '\$[^\\]*$', ''            # 내부 클래스(Foo$Bar) -> 바깥 클래스
    $direct = Join-Path $SourceRoot ($rel + '.java')
    if (Test-Path -LiteralPath $direct) { return $direct }

    $leaf = ([System.IO.Path]::GetFileName($rel) + '.java').ToLower()
    if ($javaIndex.ContainsKey($leaf)) {
        $cand = $javaIndex[$leaf]
        if ($cand.Count -eq 1) { return $cand[0] }
        $tail = ($rel -replace '\\', '/')            # 패키지 경로가 일치하는 것을 우선
        foreach ($c in $cand) { if (($c -replace '\\', '/') -like "*$tail.java") { return $c } }
        return $cand[0]
    }
    return $null
}

# .java 파일의 실제 인코딩 판별 + 라인 배열 반환
#   BOM -> UTF-8(BOM) / ASCII만 -> ASCII / 엄격 UTF-8 통과 -> UTF-8 / 그 외 MS949
function Get-SourceInfo([string]$javaPath) {
    if (-not $javaPath) { return $null }
    if ($srcCache.ContainsKey($javaPath)) { return $srcCache[$javaPath] }

    $b = [System.IO.File]::ReadAllBytes($javaPath)
    $enc = "미확인"
    $text = $null

    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        $enc = "UTF-8(BOM)"
        try { $text = $utf8Strict.GetString($b, 3, $b.Length - 3) } catch { $text = $null }
    }
    else {
        $ascii = $true
        foreach ($x in $b) { if ($x -ge 0x80) { $ascii = $false; break } }
        if ($ascii) {
            $enc = "ASCII"
            $text = [System.Text.Encoding]::ASCII.GetString($b)
        }
        else {
            try { $text = $utf8Strict.GetString($b); $enc = "UTF-8" }
            catch {
                try { $text = $ms949.GetString($b); $enc = "MS949" } catch { $text = $null; $enc = "미확인" }
            }
        }
    }

    $lines = @()
    if ($text) { $lines = $text -split "`r?`n" }
    $info = [PSCustomObject]@{ Enc = $enc; Lines = $lines }
    $srcCache[$javaPath] = $info
    return $info
}

# 리터럴이 등장하는 소스 라인번호 (최대 5개)
function Find-Lines($info, [string]$needle) {
    if (-not $info) { return "" }
    if (-not $needle -or $needle.Length -lt 2) { return "" }
    $hits = New-Object System.Collections.Generic.List[int]
    for ($n = 0; $n -lt $info.Lines.Count; $n++) {
        if ($info.Lines[$n].IndexOf($needle) -ge 0) {
            $hits.Add($n + 1)
            if ($hits.Count -ge 5) { break }
        }
    }
    return ($hits -join ',')
}

# U+FFFD 로 손실된 문자열은 온전한 구간이라도 잡아 검색에 쓴다
function Get-LongestClean([string]$s) {
    $best = ""
    foreach ($part in ($s -split [string][char]0xFFFD)) {
        if ($part.Length -gt $best.Length) { $best = $part }
    }
    return $best
}

Init-JavaIndex

$results  = New-Object System.Collections.Generic.List[object]
$literals = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $Root -Recurse -Filter *.class -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -lt 10 -or $bytes[0] -ne 0xCA -or $bytes[1] -ne 0xFE) { return }

    $pos = 4
    $minor = Read-U2 $bytes ([ref]$pos)
    $major = Read-U2 $bytes ([ref]$pos)
    $cpCount = Read-U2 $bytes ([ref]$pos)

    $utf8Literals = New-Object System.Collections.Generic.List[object]
    $parseError = $null
    $i = 1
    while ($i -lt $cpCount) {
        $tag = $bytes[$pos]; $pos++
        switch ($tag) {
            1  { $len = Read-U2 $bytes ([ref]$pos)
                 $s = [System.Text.Encoding]::UTF8.GetString($bytes, $pos, $len)
                 # 컴파일러가 실제로 심은 U+FFFD 인지, 우리 디코더가 만든 것인지 구분한다.
                 # (class 파일은 modified UTF-8 이라 C0 80 등에서 디코더가 FFFD 를 낼 수 있음)
                 $realFFFD = $false
                 for ($q = $pos; $q -le $pos + $len - 3; $q++) {
                     if ($bytes[$q] -eq 0xEF -and $bytes[$q+1] -eq 0xBF -and $bytes[$q+2] -eq 0xBD) { $realFFFD = $true; break }
                 }
                 $utf8Literals.Add([PSCustomObject]@{ Text = $s; RealFFFD = $realFFFD }); $pos += $len }
            { $_ -in 3,4 }              { $pos += 4 }
            { $_ -in 5,6 }              { $pos += 8; $i++ }   # long/double은 슬롯 2개
            { $_ -in 7,8,16,19,20 }     { $pos += 2 }
            { $_ -in 9,10,11,12,17,18 } { $pos += 4 }
            15 { $pos += 3 }
            default { $parseError = "알 수 없는 상수풀 태그 $tag (offset $pos)"; break }
        }
        if ($parseError) { break }
        $i++
    }

    $relFile = $_.FullName.Substring($Root.Length).TrimStart('\')

    if ($parseError) {
        Write-Warning "$relFile : $parseError"
        $row = [PSCustomObject]@{
            File = $relFile; JDK = "?"; Major = $major
            Status = "파싱실패"; Encoding = "파싱실패"; SrcEnc = "-"; Broken = 0; Hangul = 0
        }
        $results.Add($row)
        if (-not $OutFile) { $row }
        return
    }

    # 소스 파일 연결 (-SourceRoot 지정 시)
    $javaPath = Get-JavaPath $relFile
    $srcInfo  = Get-SourceInfo $javaPath
    $srcEnc   = "-"
    if ($srcInfo) { $srcEnc = $srcInfo.Enc }

    # 리터럴별 판정 및 복원
    #   판정 순서: FFFD(손실) → 한글 있음(949 이중해석 여부) → Latin-1 역변환
    #   한글 검사를 Latin-1 검사보다 먼저 두어야 '재컴파일·재배포' 같은
    #   정상 문자열이 · (U+00B7) 때문에 깨짐으로 오판되지 않는다.
    $cntFFFD = 0; $cntLatin1 = 0; $cnt949 = 0; $cntOK = 0
    $latin1Origin = ""
    foreach ($lit in $utf8Literals) {
        $s = $lit.Text
        if (-not $s) { continue }

        if ($lit.RealFFFD) {
            $cntFFFD++
            $needle = Get-LongestClean $s
            $literals.Add([PSCustomObject]@{ File=$relFile; SrcEnc=$srcEnc; Line=(Find-Lines $srcInfo $needle); Type="손실FFFD"; Literal=$s; Restored="(복원불가 - 원본 소스에서 재컴파일 필요)" })
            continue
        }

        if ($rxHangul.IsMatch($s)) {
            $restored = Restore-949Double $s
            if ($restored) {
                $cnt949++
                $literals.Add([PSCustomObject]@{ File=$relFile; SrcEnc=$srcEnc; Line=(Find-Lines $srcInfo $restored); Type="깨짐949이중"; Literal=$s; Restored=$restored })
            } else {
                $cntOK++
                $literals.Add([PSCustomObject]@{ File=$relFile; SrcEnc=$srcEnc; Line=(Find-Lines $srcInfo $s); Type="한글정상"; Literal=$s; Restored="" })
            }
            continue
        }

        if ($rxHighLat.IsMatch($s)) {
            $r = Restore-Latin1 $s
            if ($r) {
                $cntLatin1++
                if (-not $latin1Origin) { $latin1Origin = $r.Origin }
                $literals.Add([PSCustomObject]@{ File=$relFile; SrcEnc=$srcEnc; Line=(Find-Lines $srcInfo $r.Restored); Type="깨짐Latin1($($r.Origin))"; Literal=$s; Restored=$r.Restored })
            }
            # 역변환이 성립하지 않으면 정상 특수문자이므로 기록하지 않는다
        }
    }

    # 파일 단위 상태/인코딩 추정 (우선순위: FFFD > Latin1 > 949이중 > 정상)
    if     ($cntFFFD   -gt 0) { $status = "손실(FFFD)";   $encGuess = "UTF-8오컴파일" }
    elseif ($cntLatin1 -gt 0) { $status = "깨짐(Latin1)"; $encGuess = "Latin1($latin1Origin)" }
    elseif ($cnt949    -gt 0) { $status = "깨짐(949이중)"; $encGuess = "MS949오컴파일" }
    elseif ($cntOK     -gt 0) { $status = "한글정상";     $encGuess = "인코딩일치" }
    else                      { $status = "ASCII만";      $encGuess = "-" }

    $jdk = if ($jdkMap.ContainsKey([int]$major)) { $jdkMap[[int]$major] } else { "?($major)" }

    $row = [PSCustomObject]@{
        File     = $relFile
        JDK      = $jdk
        Major    = $major
        Status   = $status
        Encoding = $encGuess
        SrcEnc   = $srcEnc
        Broken   = $cntFFFD + $cntLatin1 + $cnt949
        Hangul   = $cntOK
    }
    $results.Add($row)

    if (-not $OutFile) { $row }

    if ($DumpLiterals -and ($cntFFFD + $cntLatin1 + $cnt949 + $cntOK) -gt 0) {
        foreach ($l in ($literals | Where-Object File -eq $relFile)) {
            $lineTag = ""
            if ($l.Line) { $lineTag = " (L$($l.Line))" }
            Write-Host "    [$($l.Type)]$lineTag $($l.Literal)  ==> $($l.Restored)"
        }
    }
}

if ($OutFile) {
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)   # BOM 포함: 엑셀 자동 인식
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("File","JDK","Major","Status","Encoding","SrcEnc","Broken","Hangul") -join $Delimiter)
    foreach ($r in $results) {
        $lines.Add(($r.File,$r.JDK,$r.Major,$r.Status,$r.Encoding,$r.SrcEnc,$r.Broken,$r.Hangul) -join $Delimiter)
    }
    [System.IO.File]::WriteAllLines($OutFile, $lines, $utf8Bom)
    Write-Host ""
    Write-Host "프로젝트  : $ProjectName  (Root: $Root)"
    Write-Host "저장 완료 : $OutFile ($($results.Count) 건)"

    if ($literals.Count -gt 0) {
        $litFile = [System.IO.Path]::Combine(
            [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutFile)),
            [System.IO.Path]::GetFileNameWithoutExtension($OutFile) + "-literals" + [System.IO.Path]::GetExtension($OutFile))
        $litLines = New-Object System.Collections.Generic.List[string]
        $litLines.Add(("File","Line","SrcEnc","Type","Literal","Restored") -join $Delimiter)
        foreach ($l in $literals) {
            $safeL = $l.Literal  -replace "`r?`n", "\n" -replace [regex]::Escape($Delimiter), " "
            $safeR = $l.Restored -replace "`r?`n", "\n" -replace [regex]::Escape($Delimiter), " "
            $litLines.Add(($l.File, $l.Line, $l.SrcEnc, $l.Type, $safeL, $safeR) -join $Delimiter)
        }
        [System.IO.File]::WriteAllLines($litFile, $litLines, $utf8Bom)
        Write-Host "리터럴 상세: $litFile ($($literals.Count) 건)"
    }
}

# 요약
$sum = $results | Group-Object Encoding | Sort-Object Count -Descending
Write-Host "총 $($results.Count) 건 스캔"
foreach ($g in $sum) { Write-Host ("  {0,-18} {1,6} 건" -f $g.Name, $g.Count) }
