# ===========================================================================
# [표준 헤더] Find-AsisPath.ps1
#   계열 : A (경로/IP 치환)
#   단계 : A-1  전수조사
#   역할 : AS-IS 하드코딩 경로(로컬/NAS/UNC)·IP·포트·도메인을
#          텍스트·class·아카이브 전부에서 찾아 리포트
#   입력 : -Root 소스 폴더 (또는 -RootList 목록 파일)
#   출력 : report\<소스명>_asis_path_report.dat
#   선행 : 없음 — 소스 1건의 첫 작업
#   상태 : 현행 v9.5
#
#   공통 : 이 파일은 UTF-8 with BOM 으로 저장할 것 (PS 5.1은 BOM 없으면 MS949로 읽음)
#          실행:  powershell -ExecutionPolicy Bypass -File .\<파일>.ps1 ...
#          출력 확장자 .dat 유지 (회사 DRM의 csv/txt 자동 암호화 회피)
#   전체 순서는 ..\README.md 참조
# ===========================================================================
# Find-AsisPath.ps1 (v9.5)
#
# ── Kind (무엇을 찾을지) — 지정 안 하면 path,unc ─────────────────────
#   -Kind path    : 드라이브 경로  d:\eos, W:/data, Z:\\share (java 리터럴 포함)
#                   대상 드라이브는 -Drives 로 제한 (기본 * = A-Z 전부)
#   -Kind unc     : NAS/네트워크 경로  \\nas\share, \\192.168.1.50\data,
#                   \\\\nas\\share (java 리터럴), //nas/share
#   -Kind ip      : IPv4
#   -Kind port    : port=8080 / server.port: 9090 / <host|ip>:8080
#   -Kind domain  : xxx.co.kr, api.company.com 등 (-DomainSuffix 로 접미사 조정)
#   -Kind host    : 점 없는 서버명 (WDAAD11 등) — -Hosts 로 직접 지정해야 동작
#   -Kind all     : 위 전부
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind all
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind ip,port,domain
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind path -Drives "d,w,x,y,z,t"
#   예) .\Find-AsisPath.ps1 -Root "D:\src\portal" -Kind host -Hosts WDAAD11,WDDIM11
#
# ── Scope (어디를 뒤질지) — 지정 안 하면 all ─────────────────────────
#   -Scope all   : [기본값] 텍스트 + .class + jar/war/ear/zip 전부 (최초 전수조사)
#   -Scope src   : 텍스트 파일만, 빌드 산출물 폴더 제외 (치환 전후 소스 증적)
#   -Scope build : .class + 아카이브만 (재빌드 후 산출물 검증)
#
# ── 특정 폴더만 조사 ─────────────────────────────────────────────────
#   -Root 에는 아무 폴더나 지정 가능 (exploded 배포 폴더, WEB-INF 등)
#   [주의] WEB-INF만 조사할 때 -Scope src 금지 — classes 폴더가 제외되어
#          WEB-INF\classes 안의 properties/xml을 전부 놓친다. 기본값(all) 사용
#
# ── 버전 이력 ────────────────────────────────────────────────────────
# v7  : 레거시 이클립스/Ant 레이아웃 인식 (WebContent, build/classes, exploded WEB-INF)
# v8  : Out 기본 .dat / -RootList 일괄 / -ExcludeFiles / 백업폴더 제외 / 출력폴더 자동생성
# v8.1: Out 기본 report\ + 백업 폴더 자동제외 정규식 수정
# v8.2: 단일 모드 기본 리포트명에도 소스명 접두
# v9  : (1) [추가기능1] NAS/네트워크 폴더 탐지 — Kind=unc (\\nas, \\ip, //host,
#           java 리터럴 \\\\) + Kind=path 의 드라이브를 d 고정에서 -Drives 로 확장
#           (기본 A-Z 전부 → W:\ Z:\ X:\ T:\ Y:\ 등 매핑 드라이브가 자동으로 잡힘)
#       (2) [추가기능2] IP·포트·도메인·서버명 탐지 — Kind=ip,port,domain,host
#       (3) 리포트에 Kind / Target / Value 컬럼 추가
#           Value  = 매칭된 값 그 자체 (기존 Match는 '그 줄 전체'라 매핑표 재료로 쓰기 나빴음)
#           Target = 그 값의 뿌리 (d: / \\nas / 192.168.1.10 / xxx.co.kr / 8080)
#           → Extract-MappingDraft v2 가 이 두 컬럼을 바로 먹는다
#       (4) class/아카이브 매칭도 IgnoreCase — v8.2는 텍스트(Select-String)만
#           대소문자 무시라 W:\ 는 잡고 .class 안의 w:\ 는 놓치는 비대칭이 있었음
#       (5) -Pattern 을 지정하면 v8.2처럼 그 패턴 하나만 사용 (Kind=custom, 하위호환)
#
# v9.1: (1) 레거시 확장자 기본 추가 (jspf/jspx/tag/tld/vm/ftl/xsl/xsd/css/json/cfg/asp/php/
#            vbs/inc/.classpath/.project 등) — v9까지는 16종만 봐서 조용히 놓치던 파일이 있었다
#       (2) -AddExt "jspf,inc,frm" — 목록에 없는 확장자 추가
#       (3) -Inventory — 조사 전에 'Root 안에 어떤 확장자가 몇 개 있고, 그중 뭐가 조사 대상인지'만 출력
#
# v9.2: -ExcludeJars — 알려진 OSS/벤더 jar(spring/commons/log4j/ojdbc/poi...) 제외.
#       중첩 jar에도 적용되고, 무엇을 뺐는지는 콘솔 + <리포트명>_skipped_jars.dat 로 증적이 남는다.
#       전부 조사: -ExcludeJars @()   /  목록 직접 지정: -ExcludeJars "spring*,commons*"
#
# v9.3: -ExcludeDomains — DTD/XSD/xmlns 선언에서 나오는 표준 도메인(w3.org, mybatis.org,
#       apache.org, sun.com ...) 제외. 제외 증적은 <리포트명>_skipped.dat 에 jar와 함께 남는다.
#       전부 보려면 -ExcludeDomains ""
#
# v9.4: 실측 리포트(1390건) 오탐 제거 —
#       (1) 백슬래시 UNC는 '점 있는 호스트' 또는 '공유명 필수' (정규식 이스케이프 \\d \\s 오탐 203건 제거)
#       (2) //host/share 는 기본 OFF, -UncSlash 로만 켬 (DOCTYPE -//W3C//DTD 오탐 881건 제거)
#       (3) UNC 호스트에도 -ExcludeDomains 적용
#
# v9.5: 실측 2차 리포트(1918건, domain 1829건) 오탐 제거 —
#       (1) DomainSuffix에서 io/gov/info/biz/edu/mil/local 제거 (java.io, egovframework.gov, LOGGER.info)
#       (2) 도메인 뒤 lookahead에 * _ 추가 (import java.io.*; 차단)
#       (3) IP 옥텟 0-255 검증 (ibatis 버전 2.3.4.726 차단) + -ExcludeIps (127.0.0.1 등)
#       (4) *-javadoc.jar/*-sources.jar 및 javadoc 생성 HTML 기본 제외
#       (5) ExcludeDomains에 jquery/unicode/eclipse/webkit 등 실측 도메인 추가
#
# 사용법: .\Find-AsisPath.ps1 -Root "C:\src" [-Kind all] [-Scope src] [-Out report.dat]
#         .\Find-AsisPath.ps1 -Root "C:\src" -Inventory            # 먼저 이걸로 사각지대 확인
# ===========================================================================

param(
    [string]$Root    = "C:\pgms",
    [string]$RootList = "",              # 소스 목록 파일 (한 줄에 경로 하나, # 주석). 지정 시 -Root 무시
    [string[]]$Kind  = @("path","unc"),  # v9 기본: 로컬 드라이브 + NAS/UNC
                                         # path|unc|ip|port|domain|host|all (콤마 나열 가능)
    [string]$Drives  = "*",              # Kind=path 대상 드라이브. "*"=A-Z 전부, "d,w,x,y,z" 처럼 제한 가능
    [string[]]$Hosts = @(),              # Kind=host / port 판정용 서버명 (점 없는 이름)
    # [v9.5] io/gov/info/biz/edu/mil/local 은 뺐다 — java 패키지·메서드와 충돌한다
    #   실측: java.io(630) egovframework.gov(282) LOGGER.info(13) <- 전부 도메인이 아니다
    #   필요하면 직접 지정: -DomainSuffix "co.kr,go.kr,kr,com,net,org,local"
    [string[]]$DomainSuffix = @("co.kr","go.kr","or.kr","re.kr","ne.kr","ac.kr","pe.kr",
                                "kr","com","net","org"),
    [string]$Pattern = "",               # 지정 시 -Kind 무시하고 이 정규식만 사용 (v8.2 호환)
    [string]$Out     = "report\asis_path_report.dat",
    [string[]]$ExcludeDirs = @(".git",".svn",".metadata","node_modules","bak","backup"),
    # v9.5: javadoc 생성물(package-tree/overview-tree/serialized-form 등)과 빌드 메타는 기본 제외
    [string[]]$ExcludeFiles = @("*.bak","*.back","*stale-data.txt",
                                "package-tree.html","overview-tree.html","overview-frame.html",
                                "serialized-form.html","allclasses*.html","constant-values.html",
                                "index-all.html","deprecated-list.html","help-doc.html"),   # 파일명 패턴 제외
    # v9.2: 널리 알려진 OSS/벤더 jar 제외 (파일명 와일드카드, 중첩 jar에도 적용)
    #   전부 조사하려면 -ExcludeJars @()  /  자체 jar가 걸러지면 -ExcludeJars 로 목록을 직접 지정
    [string[]]$ExcludeJars = @(
        "spring*","commons*","log4j*","slf4j*","logback*","jackson*","gson*","guava*",
        "junit*","hamcrest*","mockito*","ant-*","maven-*","asm*","cglib*","aopalliance*",
        "aspectj*","javassist*","servlet-api*","jsp-api*","jstl*","standard.jar","el-api*",
        "javax.*","jakarta.*","jta*","jms*","activation*","mail.jar","xerces*","xalan*",
        "xml-apis*","xmlbeans*","dom4j*","jdom*","jaxen*","jaxb*","saaj*","axis*","wsdl4j*",
        "stax*","poi*","itext*","pdfbox*","fontbox*","batik*","jfreechart*","jcommon*",
        "hibernate*","mybatis*","ibatis*","quartz*","velocity*","freemarker*","struts*",
        "tiles*","sitemesh*","ehcache*","ojdbc*","classes12*","classes111*","mysql-connector*",
        "mssql-jdbc*","jtds*","postgresql*","tibero*","cubrid*","altibase*","httpclient*",
        "httpcore*","httpmime*","oro-*","ognl*","antlr*","bcprov*","bcpkix*","jsch*","json-*",
        "joda-time*","egovframework-*","lucy-xss*","tomcat-*","catalina*","jasper*",
        # v9.5 실측 추가 — javadoc/sources jar 가 도메인 오탐 326건의 원인이었다
        "*-javadoc.jar","*-sources.jar","*-tests.jar","icu4j*","yasson*","protobuf-java*",
        "reactor-*","micrometer-*","jakarta*","parsson*","snakeyaml*","byte-buddy*","netty*"
    ),
    # v9.3: 표준 스키마/네임스페이스 도메인 제외 (DTD·XSD·xmlns 선언에서 나오는 값)
    #   판정: 값이 패턴과 같거나 '.패턴'으로 끝나면 제외 (mybatis.org, www.w3.org, xml.apache.org ...)
    #   전부 보려면 -ExcludeDomains ""
    [string[]]$ExcludeDomains = @(
        "w3.org","apache.org","mybatis.org","springframework.org","sun.com","oracle.com",
        "jcp.org","xmlsoap.org","xml.org","soapenv.org","jboss.org","hibernate.org","slf4j.org",
        "quartz-scheduler.org","opensymphony.com","sourceforge.net","mozilla.org","w3schools.com",
        "jquery.com","jsdelivr.net","cloudflare.com","googleapis.com","gstatic.com","google.com",
        "github.com","github.io","npmjs.com","bootstrapcdn.com","microsoft.com","purl.org",
        "dublincore.org","openoffice.org","egovframe.go.kr","egovframework.go.kr","example.com",
        # v9.5 실측 추가 — 벤더 JS·javadoc·라이브러리 주석에서 나온 것들
        "egovframework.gov","egovframework.com","jquery.com","jqueryui.com","jquery.org",
        "sizzlejs.com","jsperf.com","unicode.org","eclipse.org","webkit.org","chromium.org",
        "sonatype.org","jasypt.org","circleci.com","golang.org","fasterxml.com","vmware.com",
        "nodejs.org","npmjs.org","json.org","gnu.org","opensource.org","creativecommons.org",
        "ietf.org","rfc-editor.org","whatwg.org","ecma-international.org","stackoverflow.com",
        "datatables.net","highcharts.com","ckeditor.com","tinymce.com","momentjs.com",
        "getbootstrap.com","unpkg.com","cdnjs.com","gmail.com","hotmail.com","yahoo.com",
        "java.net","java.io","java.com","asp.net",
        # v9.5 실측 2차 — 벤더 JS 주석의 저자·참고 링크
        "jsfiddle.net","fluidproject.org","blindsignals.com","eae.net","nwbox.com",
        "robertpenner.com","jsguide.net","javascript.internet.com","archive.org","maven.org"
    ),
    # [v9.5] 치환 대상이 아닌 고정 IP (증적은 _skipped.dat)
    [string[]]$ExcludeIps = @("127.0.0.1","0.0.0.0","255.255.255.255"),
    [switch]$UncSlash,                   # //host/share 형태까지 탐지 (기본 OFF — DOCTYPE 공개식별자 오탐이 심하다)
    [string[]]$AddExt = @(),             # 조사할 확장자 추가. 예: -AddExt "jspf,inc,frm" / -AddExt "*.pc"
                                         #   -AddExt "*" = 확장자 없는 파일까지 전부 (class/jar도 텍스트로 한 번 더 스캔됨)
    [switch]$Inventory,                  # 조사 안 하고, Root 안의 확장자 분포 + 조사대상 여부만 출력
    [ValidateSet("all","src","build")]
    [string]$Scope = "all"
)
# [PATCH 2026-08-13] .NET 정적 메서드의 상대경로 기준을 PowerShell 현재 위치와 일치시킨다.
[Environment]::CurrentDirectory = (Get-Location).ProviderPath

# [v9] powershell -File 로 실행하면 배열 파라미터가 문자열 하나로 뭉개진다
#      ("-Kind ip,port,domain" -> @("ip,port,domain")). 콤마/세미콜론을 직접 쪼개
#      콘솔·ISE(배열)와 -File(문자열) 양쪽에서 같게 동작시킨다.
function Split-ListArg([string[]]$v) {
    $out = @()
    foreach ($e in $v) {
        if ($null -eq $e) { continue }
        foreach ($p in ($e -split '[,;]')) { $t = $p.Trim(); if ($t) { $out += $t } }
    }
    return ,$out
}
$Kind         = Split-ListArg $Kind
$Hosts        = Split-ListArg $Hosts
$DomainSuffix = Split-ListArg $DomainSuffix
$ExcludeDirs  = Split-ListArg $ExcludeDirs
$ExcludeFiles = Split-ListArg $ExcludeFiles
$AddExt       = Split-ListArg $AddExt
$ExcludeJars    = Split-ListArg $ExcludeJars
$ExcludeDomains = Split-ListArg $ExcludeDomains
$ExcludeIps     = Split-ListArg $ExcludeIps

$KindAllowed = @("path","unc","ip","port","domain","host","all")
foreach ($k in $Kind) {
    if ($KindAllowed -notcontains $k) {
        Write-Error "-Kind 값이 잘못됨: '$k' (가능: $($KindAllowed -join ', '))"; exit 1
    }
}

# 검색 범위 결정
switch ($Scope) {
    "src"   { $doText = $true;  $doClass = $false; $doArc = $false
              $ExcludeDirs += @("target","bin","build","classes","dist") }
    "build" { $doText = $false; $doClass = $true;  $doArc = $true }
    default { $doText = $true;  $doClass = $true;  $doArc = $true }
}

# v9.1: 레거시 소스 확장자 추가 (jspf/tld/vm/xsl/eclipse 메타 등)
#       여기 없는 확장자는 '조사 안 된다' — -Inventory 로 먼저 확인하고 -AddExt 로 붙일 것
$textExt = @("*.java","*.js","*.xml","*.properties","*.jsp","*.sql",
             "*.bat","*.cmd","*.sh","*.conf","*.ini","*.html","*.htm","*.txt","*.yml","*.yaml",
             "*.jspf","*.jspx","*.tag","*.tagx","*.tld","*.vm","*.ftl","*.tpl","*.inc",
             "*.xsl","*.xslt","*.xsd","*.dtd","*.css","*.json","*.cfg","*.config","*.policy",
             "*.asp","*.php","*.vbs","*.reg","*.mf","*.classpath","*.project","*.prefs")
if ($AddExt.Count -gt 0) {
    $textExt += ($AddExt | ForEach-Object {
        $e = $_.Trim()
        if ($e -eq "*") { "*" }                                   # 모든 파일 (확장자 없는 파일 포함)
        elseif ($e -notlike "*.*") { "*." + $e.TrimStart('*','.') }
        elseif ($e.StartsWith(".")) { "*" + $e }
        else { $e }
    })
    $textExt = $textExt | Select-Object -Unique
}
$binExt  = @("*.class")
$arcExt  = @("*.jar","*.war","*.ear","*.zip")
$arcRegex = '\.(jar|war|ear|zip)$'

# ===========================================================================
# 탐지 패턴 조립 (v9)
#   SEG = 경로 세그먼트 한 글자 (따옴표·공백·괄호·콤마에서 끊는다)
#   SEP = 경로 구분자 — \ 또는 \\(java 리터럴) 또는 /
# ===========================================================================
# 제어문자(\x00-\x1F,\x7F)를 반드시 뺀다 — .class 상수풀은 길이바이트가 구분자라
# 이걸 허용하면 한 매치가 다음 상수까지 통째로 삼켜 UNC 항목을 놓친다 (v9 개발 중 실측)
# = ( [ { 도 뺀다 (properties의 key=value, 코드의 괄호에서 끊기게)
$SEG = '[^\s"''<>|*?:,;=(){}\[\]\\/\x00-\x1F\x7F]'
$SEP = '(?:\\{1,2}|/)'
$KindNames = @("unc","path","ip","domain","host","port")

function Get-DriveClass([string]$drives) {
    if (-not $drives -or $drives.Trim() -eq "*") { return "A-Za-z" }
    $letters = @()
    foreach ($d in ($drives -split '[,\s;]+')) {
        $t = $d.Trim().TrimEnd(':')
        if ($t) { $letters += $t.Substring(0,1).ToLower() }
    }
    $letters = $letters | Select-Object -Unique
    if (-not $letters) { return "A-Za-z" }
    return (($letters | ForEach-Object { $_ + $_.ToUpper() }) -join '')
}

function New-KindPattern([string[]]$kinds) {
    $alts = New-Object System.Collections.Generic.List[string]

    $hostAlt = ""
    if ($Hosts.Count -gt 0) {
        $hostAlt = (($Hosts | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|')
    }

    # 1) UNC / NAS  — \\nas\share, \\192.168.1.50\data, \\\\nas\\share(java), //nas/share
    if ($kinds -contains "unc") {
        # [v9.4] 백슬래시 UNC는 둘 중 하나여야 인정한다:
        #   (1) 호스트에 점이 있거나 (\\nas01.company.co.kr\share)
        #   (2) 2글자 이상 호스트 + 2글자 이상 공유명 (\\nas01\share)
        # 이유: 실측 리포트에서 정규식 이스케이프가 UNC로 둔갑했다 —
        #       \\d{1,3} \\s+ \\w- \\da-f (203건), jQuery의 \\x20\\t\\r\\n\\f 는
        #       '호스트+공유명' 구조와 완전히 같아서 길이·이스케이프 형태로만 구분된다.
        # 포기하는 것: 서버명만 있는 \\nas01, 공유명이 1글자인 \\nas01\a (이스케이프와 구분 불가)
        $escGuard = '(?!(?:x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4})(?![\w\-]))'   # \\x20\\t, \\u00A0 차단
        $hostDot  = '[A-Za-z0-9][\w\-]*(?:\.[\w\-]+)+'                    # nas01.company.co.kr
        $hostPlain= '[A-Za-z0-9][\w\-]*[A-Za-z0-9]'                        # 2글자 이상, 하이픈으로 안 끝남
        $alts.Add('(?<unc>(?<![\w:])\\{2,4}(?![\\/])' + $escGuard + '(?:' +
                  $hostDot + '(?:' + $SEP + $SEG + '*)*' +
                  '|' + $hostPlain + $SEP + $SEG + '{2,}(?:' + $SEP + $SEG + '*)*))')
        # [v9.4] //host/share 형태는 기본 OFF (-UncSlash 로 켠다).
        #   실측: DOCTYPE 공개식별자 -//W3C//DTD, -//mybatis.org//DTD 가 881건,
        #         .class 상수풀 길이바이트(0x2F='/')가 만든 //uss/olp/... 가스가 20건.
        if ($UncSlash) {
            $alts.Add('(?<unc>(?<![\w:/\-])//(?![/])[A-Za-z0-9][\w.\-]*(?:/' + $SEG + '+)+)')
        }
    }
    # 2) 드라이브 경로 — d:\eos, W:/data, Z:\\share
    if ($kinds -contains "path") {
        $dc = Get-DriveClass $Drives
        $alts.Add('(?<path>(?<![A-Za-z0-9])[' + $dc + ']:(?=' + $SEP + ')(?:' + $SEP + $SEG + '*)+)')
    }
    # 3) IPv4
    if ($kinds -contains "ip") {
        # 옥텟 0-255 검증 — 실측에서 ibatis 버전 2.3.4.726 이 IP로 잡혔다
        $oct = '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
        $alts.Add('(?<ip>(?<![\w.])(?:' + $oct + '\.){3}' + $oct + '(?![\d.]))')
    }
    # 4) 도메인 — 접미사가 끝에 와야 매칭 (java 패키지 com.foo.Bar 오탐 방지)
    if ($kinds -contains "domain") {
        $sfx = (($DomainSuffix | Where-Object { $_ } | Sort-Object { $_.Length } -Descending |
                 ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|')
        # 앞 경계에 / \ @ 를 넣지 않는다 — http://host, \\nas\host,
        # jdbc:oracle:thin:@dbsvr.company.co.kr:1521 의 호스트까지 잡아야 한다
        # (@ 를 막으면 jdbc thin URL의 DB 호스트를 통째로 놓친다. 대신 메일주소의 도메인도 같이 잡힌다)
        # (path/unc Kind가 켜져 있으면 경로 토큰이 먼저 통째로 소비되므로 파일명 오탐은 나지 않는다)
        $alts.Add('(?<domain>(?<![\w.\-])(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+(?:' +
                  $sfx + ')(?!\.?[A-Za-z0-9*_]))')
    }
    # 5) 서버명 직접 지정
    if ($kinds -contains "host") {
        if ($hostAlt) { $alts.Add('(?<host>(?<![\w.\-])(?:' + $hostAlt + ')(?![\w\-]))') }
        elseif ($script:HostExplicit) {
            Write-Warning "-Kind host 는 -Hosts 로 서버명을 줘야 동작한다 (예: -Hosts WDAAD11,WDDIM11)" }
    }
    # 6) 포트 — ①키워드형 port=8080 / server.port: 9090  ②호스트뒤 :8080
    if ($kinds -contains "port") {
        $alts.Add('(?<port>[A-Za-z0-9_.\-]{0,20}port\s*[=:]\s*\d{1,5}(?!\d))')
        $lb = '(?:\d{1,3}\.){3}\d{1,3}|localhost|[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)+'
        if ($hostAlt) { $lb = $lb + '|' + $hostAlt }
        # 가변길이 lookbehind — .NET 정규식만 됨(PS 5.1/7 모두 OK). 시각 12:30 등은 걸리지 않는다
        $alts.Add('(?<port>(?<=' + $lb + '):\d{2,5}(?!\d))')
    }

    if ($alts.Count -eq 0) { Write-Error "탐지할 Kind가 없다"; exit 1 }
    return ($alts -join '|')
}

if ($Pattern) {
    $kinds = @("custom")
    $detectPattern = $Pattern
} else {
    $script:HostExplicit = ($Kind -contains "host")   # -Kind all 일 땐 경고 안 냄
    $kinds = if ($Kind -contains "all") { $KindNames } else { $Kind }
    $detectPattern = New-KindPattern $kinds
}
$rxDetect = New-Object System.Text.RegularExpressions.Regex(
    $detectPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-MatchKind([System.Text.RegularExpressions.Match]$m) {
    foreach ($k in $KindNames) { if ($m.Groups[$k].Success) { return $k } }
    return "custom"
}

# Target = 값의 뿌리. 요약·매핑표 초안에서 이 단위로 묶는다
function Get-Target([string]$kind, [string]$value) {
    switch ($kind) {
        "path"   { if ($value.Length -ge 2) { return $value.Substring(0,2).ToLower() } else { return $value } }
        "unc"    { $h = [regex]::Match($value, '^[\\/]+([A-Za-z0-9][\w.\-]*)')
                   if ($h.Success) { return '\\' + $h.Groups[1].Value.ToLower() } else { return $value } }
        "ip"     { return $value }
        "domain" { return $value.ToLower() }
        "host"   { return $value }
        "port"   { $d = [regex]::Match($value, '(\d{1,5})\s*$')
                   if ($d.Success) { return $d.Groups[1].Value } else { return $value } }
        default  { return "" }
    }
}

$excludeRegex = if ($ExcludeDirs.Count -gt 0) {
    ($ExcludeDirs | ForEach-Object { "[\\/]" + [regex]::Escape($_) + "[\\/]" }) -join "|"
} else { "(?!)" }

function Test-Excluded([string]$path) {
    if ($path -match $excludeRegex) { return $true }
    if ($path -match '[\\/][^\\/]*_backup_(path|ip)_') { return $true }   # <이름>_backup_path_* 자동 제외
    $leaf = Split-Path $path -Leaf
    foreach ($pat in $ExcludeFiles) { if ($leaf -like $pat) { return $true } }
    return $false
}

# v9.2/9.3: 제외 증적 — 무엇을 걸렀는지 항상 남긴다 (<리포트명>_skipped.dat)
$script:SkippedArc = @{}
$script:SkippedDom = @{}
$script:SkippedIp  = @{}

# v9.5: 치환 대상이 아닌 고정 IP
function Test-ExcludedIp([string]$value) {
    if ($ExcludeIps -contains $value) {
        if ($script:SkippedIp.ContainsKey($value)) { $script:SkippedIp[$value]++ } else { $script:SkippedIp[$value] = 1 }
        return $true
    }
    return $false
}

# v9.3: 표준 스키마/네임스페이스 도메인인가 (w3.org, mybatis.org, xml.apache.org ...)
function Test-ExcludedDomain([string]$value) {
    if ($ExcludeDomains.Count -eq 0) { return $false }
    $v = $value.ToLower().TrimEnd('.')
    foreach ($pat in $ExcludeDomains) {
        $p = $pat.ToLower()
        $hit = if ($p.Contains("*")) { $v -like $p } else { ($v -eq $p) -or $v.EndsWith("." + $p) }
        if ($hit) {
            if ($script:SkippedDom.ContainsKey($v)) { $script:SkippedDom[$v]++ } else { $script:SkippedDom[$v] = 1 }
            return $true
        }
    }
    return $false
}

function Test-ExcludedArchive([string]$nameOrPath) {
    if ($ExcludeJars.Count -eq 0) { return $false }
    $leaf = ($nameOrPath -split '[\\/]')[-1]
    foreach ($pat in $ExcludeJars) {
        if ($leaf -like $pat) {
            if ($script:SkippedArc.ContainsKey($leaf)) { $script:SkippedArc[$leaf]++ }
            else { $script:SkippedArc[$leaf] = 1 }
            return $true
        }
    }
    return $false
}

function Get-RelPath([string]$path) {
    if ($path.StartsWith($script:RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($script:RootFull.Length).TrimStart('\')
    }
    return $path
}

function Get-Category([string]$relPath, [string]$entry) {
    # 파일경로 + 아카이브 엔트리를 합쳐 판별 (exploded 배포의 WEB-INF도 잡힘)
    $p = ($relPath + "/" + $entry) -replace '\\','/'
    if ($p -match 'WEB-INF/lib')           { return "WEB-INF/lib" }
    if ($p -match 'WEB-INF/classes')       { return "WEB-INF/classes" }
    if ($p -match '(^|/)src/main/resources(/|$)') { return "src/main/resources" }
    if ($p -match '(^|/)src/main/java(/|$)')      { return "src/main/java" }
    if ($p -match '(^|/)src/main/webapp(/|$)')    { return "src/main/webapp" }
    if ($p -match '(^|/)(WebContent|WebRoot|webRoot|webapp|web)(/|$)') { return "WebContent" }
    if ($p -match '(^|/)src(/|$)')         { return "src" }
    if ($p -match '(^|/)resources?(/|$)')  { return "resources" }
    if ($p -match '(^|/)(conf|config|properties)(/|$)') { return "config" }
    if ($p -match '(^|/)sql(/|$)')         { return "sql" }
    if ($p -match '(^|/)target/classes(/|$)') { return "target/classes" }
    if ($p -match '(^|/)target(/|$)')      { return "target" }
    if ($p -match '(^|/)build/classes(/|$)') { return "build/classes" }
    if ($p -match '(^|/)build(/|$)')       { return "build" }
    if ($p -match '(^|/)bin(/|$)')         { return "bin" }
    if ($p -match '(^|/)classes(/|$)')     { return "classes" }
    if ($p -match '(^|/)lib(/|$)')         { return "lib" }
    if ($p -match '(^|/)WEB-INF(/|$)')     { return "WEB-INF" }
    $first = ($relPath -split '[\\/]')[0]
    if ($first -and $first -notmatch '\.') { return $first }
    return "(root)"
}

function Get-Ext([string]$file, [string]$entry) {
    $name = if ($entry) { $entry } else { $file }
    $ext = [System.IO.Path]::GetExtension($name)
    if ($ext) { return $ext.TrimStart('.').ToLower() } else { return "" }
}

function Get-Context([string]$text, [int]$idx) {
    $s = [Math]::Max(0, $idx - 40)
    $len = [Math]::Min(160, $text.Length - $s)
    return ($text.Substring($s, $len) -replace '[^\x20-\x7E]', '.')
}

function Get-Action([string]$foundIn) {
    switch ($foundIn) {
        "FILE"  { return "직접수정" }
        "CLASS" { return "재빌드(소스수정 후)" }
        default { return "재패키징(재배포)" }
    }
}

function Add-Result([string]$foundIn, [string]$container, [string]$file, [string]$entry,
                    [string]$line, [string]$kind, [string]$value, [string]$match) {
    # 표준 스키마 도메인(w3.org, mybatis.org 등)은 리포트에 넣지 않는다 — 집계만 한다
    if ($kind -eq "domain" -and (Test-ExcludedDomain $value)) { return }
    if ($kind -eq "ip" -and (Test-ExcludedIp $value)) { return }
    if ($kind -eq "unc") {
        $uh = [regex]::Match($value, '^[\\/]+([A-Za-z0-9][\w.\-]*)')
        if ($uh.Success -and $uh.Groups[1].Value.Contains(".") -and (Test-ExcludedDomain $uh.Groups[1].Value)) { return }
    }
    $rel = Get-RelPath $file
    $relDir = Split-Path $rel -Parent
    $script:results.Add([pscustomobject]@{
        FoundIn   = $foundIn
        Kind      = $kind
        Action    = Get-Action $foundIn
        Container = $container
        Category  = Get-Category $rel $entry
        Ext       = Get-Ext $file $entry
        RelPath   = $relDir
        File      = $file
        Entry     = $entry
        Line      = $line
        Target    = (Get-Target $kind $value)
        Value     = $value
        Match     = $match
    })
}

# 중첩 아카이브 재귀 검색
function Search-Archive([System.IO.Stream]$stream, [string]$file, [string]$containerChain) {
    $inner = ($containerChain -split ' > ')[-1]
    $typeLabel = ([System.IO.Path]::GetExtension($inner)).TrimStart('.').ToUpper()
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
        foreach ($e in $zip.Entries) {
            if ($e.Length -eq 0 -or $e.Length -gt 50MB) { continue }
            if ($e.FullName -match $arcRegex) {
                if (Test-ExcludedArchive $e.FullName) { continue }   # 벤더 jar는 안 파고든다
                $ms = New-Object System.IO.MemoryStream
                $es = $e.Open(); $es.CopyTo($ms); $es.Close()
                $ms.Position = 0
                Search-Archive $ms $file ($containerChain + " > " + $e.FullName)
                $ms.Dispose()
            }
            elseif ($e.FullName -match '\.(class|properties|xml|txt|conf|ini|sql|js|jsp|html|htm|yml|yaml|MF)$') {
                $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::ASCII)
                $content = $sr.ReadToEnd(); $sr.Close()
                foreach ($m in $rxDetect.Matches($content)) {
                    Add-Result $typeLabel $containerChain $file $e.FullName "" `
                               (Get-MatchKind $m) $m.Value (Get-Context $content $m.Index)
                }
            }
        }
        $zip.Dispose()
    } catch { Write-Warning ("아카이브 처리 실패: {0} ({1})" -f $file, $containerChain) }
}

# ---------- 소스 1건 조사 ----------
function Invoke-Scan([string]$scanRoot, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $script:results = New-Object System.Collections.Generic.List[object]
    $script:SkippedArc = @{}
    $script:SkippedDom = @{}
    $script:SkippedIp  = @{}

    # 1) 텍스트 파일 — Select-String 이 인코딩 판정과 줄번호를 처리한다
    if ($doText) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $textExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      Select-String -Pattern $detectPattern -AllMatches -ErrorAction SilentlyContinue |
      ForEach-Object {
        $line = ($_.Line.Trim() -replace '\s+', ' ')
        $line = $line.Substring(0, [Math]::Min(200, $line.Length))
        $path = $_.Path; $ln = $_.LineNumber
        foreach ($m in $_.Matches) {
            Add-Result "FILE" "" $path "" $ln (Get-MatchKind $m) $m.Value $line
        }
      }
    }

    # 2) .class
    if ($doClass) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $binExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) } |
      ForEach-Object {
        $raw = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($_.FullName))
        foreach ($m in $rxDetect.Matches($raw)) {
            Add-Result "CLASS" "" $_.FullName "" "" (Get-MatchKind $m) $m.Value (Get-Context $raw $m.Index)
        }
      }
    }

    # 3) jar/war/ear/zip (중첩 포함)
    if ($doArc) {
    Get-ChildItem -Path $scanRoot -Recurse -File -Include $arcExt -ErrorAction SilentlyContinue |
      Where-Object { -not (Test-Excluded $_.FullName) -and -not (Test-ExcludedArchive $_.Name) } |
      ForEach-Object {
        $fs = [System.IO.File]::OpenRead($_.FullName)
        Search-Archive $fs $_.FullName $_.Name
        $fs.Dispose()
      }
    }

    # 출력 폴더 자동 생성
    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $script:results | Sort-Object Kind, FoundIn, Container, Category, Ext, File |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot]"
    Write-Host "  총 $($script:results.Count)건 검출 -> $outFile"
    Write-Host "  == Kind별 (무엇이) =="
    $script:results | Group-Object Kind | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    Write-Host "  == Target별 (뿌리: 드라이브/서버/IP/도메인/포트) =="
    $script:results | Where-Object { $_.Target } | Group-Object Target | Sort-Object Count -Descending |
      Select-Object -First 30 |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    Write-Host "  == FoundIn별 (발견 위치) =="
    $script:results | Group-Object FoundIn | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    $inArc = $script:results | Where-Object { $_.Container }
    if ($inArc) {
        Write-Host "  == Container별 (아카이브 내부 매칭) =="
        $inArc | Group-Object Container | Sort-Object Count -Descending |
          ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }
    }
    # 제외 증적 — jar/도메인을 뭘 걸렀는지 한 파일로
    $skipRows = New-Object System.Collections.Generic.List[object]
    foreach ($k in ($script:SkippedArc.Keys | Sort-Object)) {
        $skipRows.Add([pscustomobject]@{ Type="jar"; Name=$k; Hits=$script:SkippedArc[$k]; Why="-ExcludeJars" }) }
    foreach ($k in ($script:SkippedDom.Keys | Sort-Object)) {
        $skipRows.Add([pscustomobject]@{ Type="domain"; Name=$k; Hits=$script:SkippedDom[$k]; Why="-ExcludeDomains" }) }
    foreach ($k in ($script:SkippedIp.Keys | Sort-Object)) {
        $skipRows.Add([pscustomobject]@{ Type="ip"; Name=$k; Hits=$script:SkippedIp[$k]; Why="-ExcludeIps" }) }
    if ($skipRows.Count -gt 0) {
        $skFile = $outFile -replace '\.dat$','_skipped.dat'
        $skipRows | Export-Csv -Path $skFile -NoTypeInformation -Encoding UTF8
        $arcN = @($skipRows | Where-Object { $_.Type -eq "jar" })
        $domN = @($skipRows | Where-Object { $_.Type -eq "domain" })
        Write-Host "  == 제외 (증적: $skFile) =="
        if ($arcN.Count -gt 0) {
            Write-Host ("    벤더 jar {0}종: {1}" -f $arcN.Count, (($arcN.Name | Select-Object -First 10) -join ", ")) }
        if ($domN.Count -gt 0) {
            Write-Host ("    표준 도메인 {0}종: {1}" -f $domN.Count, (($domN.Name | Select-Object -First 10) -join ", ")) }
    }
    Write-Host "  == 위치(Category)별 =="
    $script:results | Group-Object Category | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("    {0,6}건  {1}" -f $_.Count, $_.Name) }

    return $script:results.Count
}

# ---------- 확장자 인벤토리 (v9.1) ----------
# "레거시 소스에 뭐가 들어 있는데, 그중 뭐가 조사 대상인가"를 먼저 보는 모드.
# 조사는 하지 않는다. 미조사 확장자가 나오면 -AddExt 로 붙여서 다시 돌린다.
function Invoke-Inventory([string]$scanRoot, [string]$outFile) {
    $script:RootFull = (Resolve-Path $scanRoot).Path.TrimEnd('\')
    $cov = @{}
    foreach ($e in $textExt) { $cov[$e.TrimStart('*','.').ToLower()] = "텍스트" }
    foreach ($e in $binExt)  { $cov[$e.TrimStart('*','.').ToLower()] = "class" }
    foreach ($e in $arcExt)  { $cov[$e.TrimStart('*','.').ToLower()] = "아카이브" }

    $files = Get-ChildItem -Path $scanRoot -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { -not (Test-Excluded $_.FullName) }
    $rows = New-Object System.Collections.Generic.List[object]
    $files | Group-Object { $x = $_.Extension.TrimStart('.').ToLower(); if ($x) { $x } else { "(확장자없음)" } } |
      ForEach-Object {
        $ext = $_.Name
        $hit = $cov[$ext]
        $rows.Add([pscustomobject]@{
            Ext      = $ext
            Count    = $_.Count
            SizeKB   = [int](($_.Group | Measure-Object Length -Sum).Sum / 1KB)
            Scanned  = if ($hit) { "O" } else { "X" }
            How      = if ($hit) { $hit } else { "미조사 — 필요하면 -AddExt $ext" }
            Sample   = (Get-RelPath $_.Group[0].FullName)
        })
      }

    $outParent = Split-Path $outFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }
    $rows | Sort-Object Scanned, @{Expression="Count";Descending=$true} |
      Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "`n[$scanRoot] 파일 $($files.Count)개 / 확장자 $($rows.Count)종 -> $outFile"
    Write-Host "  == 미조사 확장자 (필요하면 -AddExt 로 추가) =="
    $miss = $rows | Where-Object { $_.Scanned -eq "X" } | Sort-Object Count -Descending
    if ($miss) { $miss | Select-Object -First 25 |
        ForEach-Object { Write-Host ("    {0,6}개  .{1,-12} 예: {2}" -f $_.Count, $_.Ext, $_.Sample) } }
    else { Write-Host "    없음 — 전부 조사 대상" }
    # 아카이브는 따로 — 어떤 jar가 제외되는지 미리 본다
    $arcs = $files | Where-Object { $_.Name -match $arcRegex }
    if ($arcs) {
        $arcIn  = @($arcs | Where-Object { -not (Test-ExcludedArchive $_.Name) })
        $arcOut = @($arcs | Where-Object { Test-ExcludedArchive $_.Name })
        Write-Host "  == 아카이브 $($arcs.Count)개 — 조사 $($arcIn.Count) / 제외 $($arcOut.Count) (-ExcludeJars) =="
        $arcIn | Select-Object -First 20 | ForEach-Object { Write-Host ("    [조사] " + $_.Name) }
        if ($arcIn.Count -gt 20) { Write-Host "    ... 외 $($arcIn.Count - 20)개" }
        if ($arcOut.Count -gt 0) { Write-Host ("    [제외] " + (($arcOut.Name | Select-Object -Unique | Select-Object -First 20) -join ", ")) }
    }
    Write-Host "  == 조사 대상 확장자 =="
    $rows | Where-Object { $_.Scanned -eq "O" } | Sort-Object Count -Descending | Select-Object -First 25 |
      ForEach-Object { Write-Host ("    {0,6}개  .{1,-12} ({2})" -f $_.Count, $_.Ext, $_.How) }
    return $rows.Count
}

# ---------- 실행 ----------
if ($doArc) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

$scopeDesc = @{
    all   = "텍스트 + CLASS + 아카이브 전부 (최초 전수조사)"
    src   = "텍스트만, 빌드산출물 폴더 제외 (소스 증적)"
    build = "CLASS + 아카이브만 (재빌드 후 검증)"
}
Write-Host "===== Find-AsisPath v9.5 (Scope=$Scope) ====="
Write-Host "검색 범위: $($scopeDesc[$Scope])"
$kindDesc = ($kinds -join ', ')
if ($kinds -contains 'path') { $kindDesc = $kindDesc + '  (Drives=' + $Drives + ')' }
Write-Host "탐지 종류: $kindDesc"
if ($Hosts.Count -gt 0) { Write-Host "서버명    : $($Hosts -join ', ')" }
Write-Host "제외 폴더: $($ExcludeDirs -join ', ')"
Write-Host "제외 파일: $($ExcludeFiles -join ', ')"

if ($Inventory) {
    Write-Host "[Inventory 모드] 조사는 하지 않는다 — 확장자 분포와 조사대상 여부만 본다"
    $invRoots = @()
    if ($RootList) {
        if (-not (Test-Path $RootList)) { Write-Error "소스 목록 파일 없음: $RootList"; exit 1 }
        $invRoots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -and -not $_.StartsWith("#") }
    } else { $invRoots = @($Root) }
    foreach ($r in $invRoots) {
        if (-not (Test-Path $r)) { Write-Warning "소스 없음, 건너뜀: $r"; continue }
        $leaf = Split-Path ((Resolve-Path $r).Path.TrimEnd('\')) -Leaf
        $outDir = Split-Path $Out -Parent
        $invOut = if ($outDir) { Join-Path $outDir ($leaf + "_ext_inventory.dat") } else { $leaf + "_ext_inventory.dat" }
        [void](Invoke-Inventory $r $invOut)
    }
    return
}

if ($RootList) {
    if (-not (Test-Path $RootList)) { Write-Error "소스 목록 파일 없음: $RootList"; exit 1 }
    $roots = Get-Content $RootList | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -and -not $_.StartsWith("#") }
    if (-not $roots) { Write-Error "소스 목록이 비어 있음: $RootList"; exit 1 }

    $outDir  = Split-Path $Out -Parent
    $outName = Split-Path $Out -Leaf
    $summary = New-Object System.Collections.Generic.List[object]
    $usedNames = @{}

    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { Write-Warning "소스 없음, 건너뜀: $r"; continue }
        $leaf = Split-Path ((Resolve-Path $r).Path.TrimEnd('\')) -Leaf
        if ($usedNames.ContainsKey($leaf)) {
            $usedNames[$leaf]++
            $tag = "$leaf`_$($usedNames[$leaf])"
            Write-Warning "소스 폴더명 중복: '$leaf' -> 증적은 '$tag'로 저장 ($r)"
            $leaf = $tag
        } else { $usedNames[$leaf] = 1 }
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
        $cnt = Invoke-Scan $r $outFile
        $summary.Add([pscustomobject]@{ Source = $leaf; Count = $cnt; Report = $outFile })
    }

    Write-Host "`n===== 일괄 조사 요약 ($($summary.Count)개 소스) ====="
    $summary | Sort-Object Count -Descending |
      ForEach-Object { Write-Host ("  {0,6}건  {1,-30}  -> {2}" -f $_.Count, $_.Source, $_.Report) }
}
else {
    if (-not (Test-Path $Root)) { Write-Error "Root 없음: $Root"; exit 1 }
    $outFile = $Out
    if (-not $PSBoundParameters.ContainsKey('Out')) {
        $leaf = Split-Path ((Resolve-Path $Root).Path.TrimEnd('\')) -Leaf
        $outDir  = Split-Path $Out -Parent
        $outName = Split-Path $Out -Leaf
        $outFile = if ($outDir) { Join-Path $outDir ($leaf + "_" + $outName) } else { $leaf + "_" + $outName }
    }
    [void](Invoke-Scan $Root $outFile)
}
