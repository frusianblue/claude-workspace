# mar-eos-encoding

MAR/EOS 이관 중 한글 인코딩 이슈 대응. `FileNotFoundException`의 원인을 컴파일/배포/런타임 축으로 나눠 특정하는 작업 (PowerShell 진단 도구 기반, 폐쇄망/DRM 제약).

## 현재 상태 (2026-08-13 기준)

- **컴파일 단계 무혐의 — 11개 클래스 기준 재확인 완료**
  (8/12 판정은 8개/90리터럴 기준이었음. 현재 11개/152리터럴로 재측정: 깨짐·손실 0건, 소스 전부 UTF-8/ASCII)
- 빌드 시각 11개 전부 동일(`2026-08-12 22:53:12`) → **clean 전체 빌드 확인**, 부분 빌드 가설 배제
- **남은 원인은 런타임 경로.** 가설 3 결론 유효, 근거는 오히려 넓어짐
- `lev1`의 `InlineCheck` 깨짐은 **도구 오탐**으로 확정 — `·`(U+00B7) 때문에 정상 한글이 Latin-1 깨짐으로 오판됨. 수정 완료
- 도구 `tools/` 트리로 일괄 정리(35개). `common/ClassParser.psm1` 신설로 파서 4벌 중복 해소 착수
- **미실행**: `Phase2-Compare-Deployment`(가설 3의 배포 절반), 디스크 파일명 실측(D-1 방침), AS-IS jar/war 전수
- 제약: 회사 DRM(.dat 운용), bat 차단(ISE 붙여넣기), 스크립트·매핑 .dat 모두 UTF-8 BOM 필수

## 다음 세션 첫 행동

`Test-ClassParser.ps1` 18항목 PASS 확인 → `lev1` 재실행해 `재컴파일(소스확인)` 1건 소멸 확인

## 도구 구조

```
tools/
├── common/        ClassParser.psm1 (판정 단일 원본) + Test-ClassParser.ps1 (게이트)
├── encoding/      Phase0~6, Scan-*, Compare-*, Match-*, Expand-ArchivesForScan
├── asis-replace/  Find/Replace-AsisPath/Ip, Extract-MappingDraft
├── docs/          RUNBOOK / HANDOFF / eclipse-encoding-guide / encoding-detection-and-conversion
└── _deprecated/   실행 금지, 삭제도 금지 (미이식 기능 확인용)
```

소스 1건 처리 순서와 각 단계 명령은 `tools/README.md`.

## 알려진 함정 (누적)

| 함정 | 대응 |
|---|---|
| PowerShell `-shl`이 byte 타입 유지 | 바이트 조립 시 무조건 `[int]` 캐스팅 |
| **PS 위치 ≠ .NET 위치** | `[Environment]::CurrentDirectory = (Get-Location).ProviderPath` (2026-08-13 추가) |
| 판정 순서를 뒤집으면 `·` `é` `€` 오탐 | FFFD → 한글 → Latin-1 순서 고정 |
| PS 5.1은 BOM 없는 .ps1을 MS949로 읽음 | UTF-8 BOM 저장 |
| DRM이 csv/txt 자동 암호화 | 출력은 `.dat` |
| 부분 빌드는 가설 1 재발 | `static final String` 인라이닝 → clean 후 전체 빌드 |
| 정상 빌드만 스캔하면 검출기 고장을 못 봄 | `Phase6-Invoke-ReproMatrix.ps1` 대조군 |

## 최신 핸드오프

→ [2026-08-13](handoffs/2026-08-13.md)

<!--
운영 규칙: 이 README는 항상 최신 상태로 덮어쓴다.
레포는 Claude 프로젝트에 GitHub 연동됨 — push 후 프로젝트 지식에서 Sync now 필수.
새 세션은 붙여넣기 없이 "이어서 하자"로 시작.
-->
