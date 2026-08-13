# asis-replace — AS-IS 경로/IP 치환 (A 계열)

| 파일 | 단계 | 역할 |
|---|---|---|
| `Find-AsisPath.ps1` (v8.2) | A-1 | 경로 전수조사. `-Scope all/src/build`, `-RootList` 일괄, jar/war 중첩 내부까지 |
| `Extract-MappingDraft.ps1` (v1) | A-2 | Find 리포트에서 매핑표 초안 추출 (`-Mode Path|Ip`) |
| `Replace-AsisPath.ps1` (v3) | A-3 | 경로 치환. DryRun 기본, `-Apply` 시 자동 백업 |
| `Replace-AsisIp.ps1` (v5) | A-4 | IP 치환. `-UsePort`로 `IP:포트` 규칙 우선 |
| `RootList/roots.dat` | 입력 | Find·ReplaceIp 일괄 목록 (한 줄 = 소스 경로) |
| `RootList/replace_targets.dat` | 입력 | ReplacePath 일괄 목록 (`소스경로,매핑파일`) |
| `mapping/path_mapping_예시.dat` | 입력 | 경로 매핑표 양식 |
| `mapping/ip_mapping_예시.dat` | 입력 | IP 매핑표 양식 (내용은 예시 데이터) |

## 규칙

- **DryRun → 리포트 검토 → `-Apply` → 재DryRun 0건** 순서를 건너뛰지 않는다
- 치환 완료 증적은 **Replace 재DryRun 0건**으로 남긴다.
  치환 후 Find를 전체 패턴으로 다시 돌리면 새 경로(`d:/app/...`)도 `d:/`라 검출된다
- 조사는 전체(all), 치환은 텍스트만 — class/jar/war는 재빌드·재패키징으로 해소
- 매핑 `.dat`도 **UTF-8 BOM** 저장 (PS 5.1이 BOM 없는 UTF-8을 ANSI로 읽어 한글 비고가 깨짐)
- `-ExcludeDirs`를 직접 지정하면 기본값이 **대체**된다 (추가 아님)
- **[함정] WEB-INF 단독 조사 시 `-Scope src` 금지** — classes 폴더 제외 때문에 `WEB-INF\classes`를 놓친다

## 회사(폐쇄망, bat 차단)

스크립트를 텍스트로 반입 → ISE에 붙여넣기(**UTF-8 BOM 유지**) → `param()` 기본값 직접 수정 후 F5.
실행 첫 줄 배너(`===== Replace-AsisPath v3 =====`)로 버전을 확인한다 — 안 보이면 구버전이다.
