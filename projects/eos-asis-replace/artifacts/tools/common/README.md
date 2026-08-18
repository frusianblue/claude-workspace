# common — 공용 모듈 (예정)

## ClassParser.psm1 (미작성)

지금 `.class` 상수풀 파서가 **4벌로 복제**돼 있다.

| 파일 | 파서 보유 |
|---|---|
| `encoding/Scan-ClassFiles.ps1` | ✅ |
| `encoding/Compare-SourceToClass-lev1.ps1` | ✅ |
| `encoding/Compare-SourceToClass-lev2.ps1` | ✅ |
| `_deprecated/Check-ClassEncoding.ps1` | ✅ |

2026-08-12에 잡은 `-shl` 버그(PowerShell이 `-shl` 결과 타입을 왼쪽 피연산자로 유지해
`[byte]`를 8비트 밀면 0으로 잘리는 문제)를 세 곳에서 고쳤는데, **lev2 한 곳이 누락됐다**.
2026-08-13에 발견해 패치했지만, 구조가 그대로면 다음 버그도 똑같이 샌다.

## 이식할 함수

```
Read-U2 / Read-U4        big-endian 정수 읽기 ([int]/[long] 캐스팅 강제)
Get-ConstantPool         상수풀 순회 (태그별 슬롯 크기, long/double 2슬롯 처리)
Get-StringLiterals       CONSTANT_String이 참조하는 Utf8만 추출
Test-Mojibake            역변환 검증 기반 깨짐 판정 + 원문 복원
```

`Import-Module .\common\ClassParser.psm1`로 네 스크립트가 공유하면
파서 버그 수정이 한 곳에서 끝난다.

---

## 현재 상태 (2026-08-13)

`ClassParser.psm1` 작성 완료. 도입 현황:

| 스크립트 | 도입 범위 | 비고 |
|---|---|---|
| `Compare-SourceToClass-lev2.ps1` | `Get-ClassMajor` | 자체 구현 제거 완료 |
| `Compare-SourceToClass-lev1.ps1` | `Test-Mojibake` (깨짐 판정) | **오탐 수정.** 로컬 `Read-U2`/`Restore-*`는 반환 형식이 달라 잔존 — A/B 대조 후 제거 |
| `Scan-ClassFiles.ps1` | **미도입** | 판정 1순위 근거 도구. 아래 절차대로 A/B 통과 후 도입 |
| `_deprecated/Check-ClassEncoding.ps1` | 도입 안 함 | 폐기 예정 |

## 도입 전 게이트

```powershell
.\common\Test-ClassParser.ps1
```

전 항목 PASS여야 한다. 특히 2번 항목(`정상 한글 + 중점(U+00B7)`)이 이번에 발견된 오탐 재현 케이스다.

## Scan-ClassFiles 도입 절차 (A/B 대조)

이 파일은 판정 1순위 근거라 **결과가 한 건도 달라지면 안 된다.** 반드시 대조 후 교체한다.

```powershell
# 1) 현행으로 측정 (기준선)
.\encoding\Scan-ClassFiles.ps1 -Root <classes> -SourceRoot <src>

# 2) 모듈판으로 측정
.\encoding\Scan-ClassFiles.ps1 -Root <classes> -SourceRoot <src>

# 3) 두 리포트 비교 — 차이 0이어야 통과
Compare-Object (Get-Content <기준선.dat>) (Get-Content <모듈판.dat>)
```

가능하면 클래스 수가 많은 실소스(운영 jar 추출본 등)로 돌릴 것.
`lena-encoding-test`는 11개뿐이라 desync 계열 차이가 드러나지 않는다.
