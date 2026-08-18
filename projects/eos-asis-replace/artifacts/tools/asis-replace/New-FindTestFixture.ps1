# ===========================================================================
# [표준 헤더] New-FindTestFixture.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1t  Find 자체 검증 픽스처 생성
#   역할 : Find-AsisPath 의 탐지/오탐 케이스를 한 트리로 재현한다.
#          FILE(java/properties) + CLASS(상수풀 흉내) + JAR(우리 jar/벤더 jar) 전 경로를 덮는다
#   입력 : -Dest 생성 위치 (기본 .\fixtures\findtest)
#   출력 : 픽스처 트리 + 콘솔에 기대값 표
#   선행 : 없음
#   상태 : 신규 v1
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# New-FindTestFixture.ps1 (v1)
#
# 왜 필요한가
#   -Inventory 는 `if ($Inventory) { ... return }` 로 조기 반환하므로
#   정규식 조립부·Kind/Target/Value 컬럼 생성부가 한 줄도 실행되지 않는다.
#   배너가 떴다고 런타임 검증이 끝난 게 아니다. 이 픽스처가 그 나머지 절반을 덮는다.
#
# 한계 (2026-08-18 핸드오프의 교훈)
#   합성 픽스처는 '이미 아는 케이스'만 재현한다. DOCTYPE 공개식별자도, 상수풀 길이바이트
#   0x2F 도 실측 리포트에서 처음 나왔다. 이건 회귀 확인용이지 신규 오탐 발굴용이 아니다.
#
# 사용법
#   .\New-FindTestFixture.ps1
#   .\Find-AsisPath.ps1 -Root .\fixtures\findtest -Kind all -Drives "d,w,x,y,z,t" -Hosts "WDAAD11,WDDIM11"
#   -> 콘솔 요약이 아래 기대값 표와 일치하는지 눈으로 대조
# ===========================================================================

param(
    [string]$Dest = ".\fixtures\findtest",
    [switch]$Force
)
# .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

Write-Host "===== New-FindTestFixture v1.1 ====="

if (Test-Path $Dest) {
    if (-not $Force) { Write-Error "이미 있음: $Dest  (-Force 로 덮어쓰기)"; exit 1 }
    Remove-Item $Dest -Recurse -Force
}

$dirs = @(
    "src\main\java\com\eos\test",
    "src\main\resources",
    "build\classes\com\eos\test",
    "WebContent\WEB-INF\lib"
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $Dest $d) -Force | Out-Null }
$root = (Resolve-Path $Dest).Path

# 출력은 전부 UTF-8 BOM + CRLF 고정 (PS 5.1/7.x, Windows/Linux 무관하게 같은 바이트)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$ascii     = New-Object System.Text.ASCIIEncoding
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Fixture([string]$path, [string[]]$lines, $enc) {
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $enc)
}

# ---------------------------------------------------------------------------
# 1) FindTest.java — 케이스 ID를 주석으로 달아 리포트와 1:1 대조한다
#    P##=path  U##=unc  I##=ip  T##=port  D##=domain  H##=host  N##=0건 기대
#    한글 주석이 한 줄 있다 — 리포트 Match 컬럼의 한글 왕복까지 같이 본다
# ---------------------------------------------------------------------------
$java = @'
package com.eos.test;

import java.io.*;
import java.net.URL;
import javax.net.ssl.SSLSocketFactory;

public class FindTest {

    // ---------- PATH (검출 기대) ----------
    private String upload   = "d:\\eos\\upload";        // [P01] java 리터럴 이중 백슬래시 / 업로드 경로
    private String imgRoot  = "W:/data/img";            // [P02] 슬래시 표기
    private String Drive3   = "Z:";                     // [P03] 구분자 없는 드라이브 (v9.6)
    // [P04] 주석 안 경로도 잡힌다: d:/app/file
    private String antHome  = "D:\\app\\ant\\old";      // [P05]

    // ---------- UNC (검출 기대) ----------
    private String nas1     = "\\\\nas01\\share";       // [U01] java 리터럴 UNC
    private String nasIp    = "\\\\10.10.18.229\\image";// [U02] IP 직접 UNC
    private String Drive5   = "\\\\windbvs1";           // [U03] 서버명만 (v9.7)
    // [U04] 점 있는 호스트: \\nas01.company.co.kr\pub

    // ---------- IP / PORT / DOMAIN / HOST ----------
    private String dbIp     = "10.10.88.165";           // [I01]
    private String logIp    = "10.88.33.145";           // [I02]
    private String jdbcUrl  = "jdbc:oracle:thin:@dbsvr.company.co.kr:1521:ORCL";  // [D01][T01]
    private String apiHost  = "https://portal.nia.or.kr/api";                     // [D02]
    private String wasName  = "WDAAD11";                // [H01] -Hosts 지정 시에만

    // ---------- N: 0건이어야 한다 ----------
    private String rx1 = "\\d{1,3}";                    // [N01] 정규식 이스케이프
    private String rx2 = "\\s+";                        // [N02]
    private String rx3 = "[\\x20\\t\\r\\n\\f]";         // [N03]
    private String rx4 = "\\u00A0";                     // [N04]
    private String[] parts = "a|b".split("\\|");        // [N05]
    private String rx6 = "\\\\";                        // [N06] 백슬래시만
    private String view1 = "forward:/eos/list";         // [N07] 뷰 이름
    private String view2 = "redirect:/main.do";         // [N08]
    private String ver   = "2.3.4.726";                 // [N09] ibatis 버전번호
    private String time  = "12:30";                     // [N10] 시각
    private String json  = "{\"a\":\"b\"}";             // [N11]
    private String doctype = "-//W3C//DTD HTML 4.01//EN"; // [N12] 공개식별자
    private String w3   = "http://www.w3.org/1999/xhtml"; // [N13] ExcludeDomains 로 제외
    private String pkg  = "javax.net.ssl.SSLSocketFactory"; // [N14] 자바 패키지
    private String io   = "java.io.File";               // [N15]

    public void go() throws IOException {
        File f = new File(upload + File.separator + "a.txt");
        URL u = new URL(apiHost);
        SSLSocketFactory sf = null;
        System.out.println(f + u + sf + Drive3 + Drive5 + rx1 + rx2 + rx3 + rx4 + parts.length
                           + rx6 + view1 + view2 + ver + time + json + doctype + w3 + pkg + io
                           + imgRoot + antHome + nas1 + nasIp + dbIp + logIp + jdbcUrl + wasName);
    }
}
'@ -split "`r?`n"
Write-Fixture (Join-Path $root "src\main\java\com\eos\test\FindTest.java") $java $utf8Bom

# ---------------------------------------------------------------------------
# 2) findtest.properties — '= 뒤 줄끝' 분기(P/U)와 ExcludeIps 증적 전용
#    java 소스로는 drive=T: / nas=\\host 형태를 만들 수 없다
# ---------------------------------------------------------------------------
$props = @'
# Find-AsisPath fixture (properties)
drive=T:
nas=\\nas_mobiledb
Globals.Url=jdbc:Altibase://127.0.0.1:20300/mydb
server.port: 9090
tomcat.port=8080
upload.dir=Y:\\wormsdata15\\upload
backup.unc=\\\\10.10.17.239\\wormsdata15
mail.admin=admin@company.co.kr
'@ -split "`r?`n"
Write-Fixture (Join-Path $root "src\main\resources\findtest.properties") $props $ascii

# ---------------------------------------------------------------------------
# 3) Test.class — Find 는 .class 를 ASCII 디코드 후 정규식만 돌린다.
#    상수풀 UTF8 엔트리(태그 0x01 + 2바이트 길이 + 바이트열) 형태만 흉내내면 충분하다.
#    [C04] 는 길이바이트를 일부러 0x2F('/') 로 만들어 //uss/olp 가스를 재현한다
#          -> -UncSlash 없이는 0건이어야 한다 (v9.4 회귀 확인)
# ---------------------------------------------------------------------------
$bytes = New-Object System.Collections.Generic.List[byte]
foreach ($b in @(0xCA,0xFE,0xBA,0xBE,0x00,0x00,0x00,0x32)) { $bytes.Add([byte]$b) }   # magic + 50(JDK6)
function Add-CpUtf8([string]$s, [int]$forceLen = -1) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($s)
    $len = if ($forceLen -ge 0) { $forceLen } else { $b.Length }
    $bytes.Add([byte]0x01)
    $bytes.Add([byte](($len -shr 8) -band 0xFF))   # [int] 캐스팅 필수 — byte 를 -shl/-shr 하면 잘린다
    $bytes.Add([byte]($len -band 0xFF))
    foreach ($x in $b) { $bytes.Add($x) }
}
Add-CpUtf8 "com/eos/test/Test"
Add-CpUtf8 "d:\eos\upload"              # [C01] path 기대
Add-CpUtf8 "10.10.88.134"               # [C02] ip 기대
Add-CpUtf8 "\\nas01\share"              # [C03] unc 기대
Add-CpUtf8 "uss/olp/list.do" 0x2F       # [C04] 길이바이트를 '/' 로 -> //uss 가스. 0건 기대
Add-CpUtf8 "Mypath"
Add-CpUtf8 "MyIp"
[System.IO.File]::WriteAllBytes((Join-Path $root "build\classes\com\eos\test\Test.class"), $bytes.ToArray())

# ---------------------------------------------------------------------------
# 4) jar 2개 — 우리 jar(조사 대상) / 벤더 jar(-ExcludeJars 제외 + 증적)
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-JarFixture([string]$jarPath, [string]$entryName, [string]$content) {
    if (Test-Path $jarPath) { Remove-Item $jarPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($jarPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $e  = $zip.CreateEntry($entryName)
        $sw = New-Object System.IO.StreamWriter($e.Open(), $utf8NoBom)
        $sw.Write($content)
        $sw.Flush(); $sw.Dispose()
    } finally { $zip.Dispose() }
}

$libDir = Join-Path $root "WebContent\WEB-INF\lib"
New-JarFixture (Join-Path $libDir "eos-common-1.0.jar") "config/db.properties" `
    ("# [J01] jar 내부 / [J02] 이 한글은 리포트 Match 에 ? 로 나오는 게 정상`r`ndb.host=10.10.88.165`r`ndb.port=1521`r`nnas.path=\\nas01\share\eos`r`n")
New-JarFixture (Join-Path $libDir "commons-lang-2.6.jar") "vendor.properties" `
    ("host=d:\vendor\junk`r`nip=192.168.99.99`r`n")

# ---------------------------------------------------------------------------
# 기대값 (컨테이너 PS 7.4 / Find-AsisPath v9.8 실측)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "-> $root"
Write-Host ""
Write-Host "다음 명령으로 조사할 것:"
Write-Host "  .\Find-AsisPath.ps1 -Root `"$Dest`" -Kind all -Drives `"d,w,x,y,z,t`" -Hosts `"WDAAD11,WDDIM11`""
Write-Host ""
Write-Host "===== 기대값 (총 29건) ====="
Write-Host "  Kind별    : path 8 / unc 8 / port 5 / ip 4 / domain 3 / host 1"
Write-Host "  FoundIn별 : FILE 23 / CLASS 3 / JAR 3"
Write-Host "  Container : eos-common-1.0.jar 3"
Write-Host "  Category  : src/main/java 15 / src/main/resources 8 / build/classes 3 / WEB-INF/lib 3"
Write-Host "  제외 증적 (_skipped.dat 3행):"
Write-Host "     jar    commons-lang-2.6.jar  1  -ExcludeJars"
Write-Host "     domain www.w3.org            1  -ExcludeDomains"
Write-Host "     ip     127.0.0.1             1  -ExcludeIps"
Write-Host ""
Write-Host "  [J02] JAR/CLASS 행의 Match 컬럼 한글이 '?' 인 것은 정상이다 —"
Write-Host "        Find 는 아카이브(566행)와 .class(588행)를 Encoding::ASCII 로 디코드한다."
Write-Host "        탐지 패턴은 전부 ASCII 라 검출에는 영향이 없지만, 아카이브 안 한글은 눈으로 못 본다."
Write-Host ""
Write-Host "  [주의] 콘솔 '제외' 요약에는 jar/도메인만 찍힌다 — ip 는 _skipped.dat 에만 있다 (v9.5 누락)"
Write-Host ""
Write-Host "  0건이어야 하는 것: N01~N15 (정규식 이스케이프 / forward:/ / 2.3.4.726 / 12:30 /"
Write-Host "                     JSON `"a`":`"b`" / -//W3C//DTD / javax.net.ssl / java.io) + [C04] //uss"
