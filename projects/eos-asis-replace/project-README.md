# mar-eos-encoding

MAR/EOS 레거시 Java 애플리케이션 이관 — 한글 인코딩 진단(B 계열)과 AS-IS 경로/IP 치환(A 계열).

## 현재 상태 (2026-08-18)

| 축 | 상태 |
|---|---|
| 컴파일 (B) | **무혐의 확정** — 11개 클래스 / 리터럴 152개, 깨짐·손실 0건, clean 전체 빌드 확인 |
| 런타임 (B) | 원인 후보. `CommExcelView` 파일 조회 + `web.xml`의 `CharacterEncodingFilter` ↔ `LucyXSSFilter` 순서. **미착수** |
| 치환 (A) | 도구 완성 단계. Find v9.7 / Replace v4.2 / Extract v2.1 / Get-MappedDrives v1. **PS 5.1 검증 대기** |

## 다음 행동

1. 회사 PS 5.1에서 `Find-AsisPath.ps1 -Inventory` 실행 → 배너 `v9.7` 확인 (구문 검증)
2. `Get-MappedDrives.ps1 -Tag <시스템> -EmitMapping` 으로 드라이브↔UNC 실측 (시스템별)
3. `_skipped.dat` 역검토 — 자체 jar/도메인이 잘못 제외됐는지
4. (인코딩 축) `Test-ClassParser.ps1` 18항목 PASS → `lev1` 재실행

## 도구 (A 계열, `artifacts/tools/asis-replace/`)

| 파일 | 단계 | 역할 |
|---|---|---|
| `Get-MappedDrives.ps1` v1 | A-0 | 네트워크 드라이브 ↔ 실제 UNC 수집, 매핑표 초안 생성 |
| `Find-AsisPath.ps1` v9.7 | A-1 | 경로(로컬/NAS/UNC)·IP·포트·도메인 전수조사. `-Inventory`로 확장자 사각지대 확인 |
| `Extract-MappingDraft.ps1` v2.1 | A-2 | 리포트 → 매핑표 초안 (`-Mode Path\|Ip\|Domain\|Port`) |
| `Replace-AsisPath.ps1` v4.2 | A-3 | 경로 치환. DryRun 기본, `-Apply` 시 자동 백업 |
| `Replace-AsisIp.ps1` v5 | A-4 | IP 치환 |

상세 사용법·오탐 제거 이력·한계는 `artifacts/tools/asis-replace/README.md`.

## 반드시 지키는 규칙

- **DryRun → 리포트 검토 → `-Apply` → 재DryRun 0건** 을 건너뛰지 않는다
- 스크립트·매핑표는 **UTF-8 BOM**, 출력은 **`.dat`** (DRM 자동 암호화 회피)
- **매핑표는 소스별로 분리** — 같은 `Z:`가 시스템마다 다른 서버를 가리킨다 (실측 확인)
- 제외(`-ExcludeJars`/`-ExcludeDomains`/`-ExcludeIps`)는 항상 `_skipped.dat` 증적을 남긴다
- 새 탐지 규칙을 넣으면 **실소스 1회 돌려 상위 Target을 눈으로 확인**한다 (합성 픽스처로는 안 보인다)

## 진행 이력

- 2026-08-18 — A 계열 도구에 NAS/UNC·IP/포트/도메인 탐지 추가, 실측 리포트 2회로 오탐 8종 제거
- 2026-08-13 — `tools/` 트리 정리, `common/ClassParser.psm1` 단일 원본화, `lev1` 오탐 원인 확정
- 2026-08-12 — 컴파일 축 무혐의 판정 (상수풀 깨짐 0건)
