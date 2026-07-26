# eos-asis-replace

레거시 EOS 소스 이관 중 AS-IS 하드코딩 경로(d:/)·IP를 TO-BE로 치환하는 작업 (PowerShell 스크립트 기반, 폐쇄망/DRM 제약).

## 현재 상태 (2026-07-27 기준)

- **PS 5.1 실기기 풀사이클 검증 완료**: Find v8(all) → 매핑표 → Replace DryRun→Apply→재DryRun 0건 (portal 실소스)
- 검증 과정에서 버그 4건 수정: ① v1 delegate 치환이 5.1에서 무동작(치환 0·백업 없음) ② 출력 폴더 미생성 시 리포트 유실 ③ 백업 폴더 자동제외 정규식 불발(Find·Replace 공통) ④ 단일/일괄 리포트명 불일치
- 도구 최신: `Find-AsisPath v8.2` + `Replace-AsisPath v3`(**RootList 일괄 모드** 신설 — `소스경로,매핑파일` 2컬럼, Apply 전 사전 전체 검증) + `도구_실행가이드.md`(통합)
- 기본 출력 통일: `-Out` 생략 시 `report\<소스명>_<기본파일명>` (영어 폴더, 자동 생성)
- portal 잔여: UNMAPPED 1건 판정 대기 / CLASS 6건 java 대응 확인 대기
- **미검증**: Replace-AsisIp -Apply (v3와 같은 delegate·제외 버그 보유 가능성 — 커밋 시 동일 수정 필요)
- 제약: 회사 DRM(.dat 운용), bat 차단(ISE 붙여넣기+param 기본값 수정), 스크립트·매핑 .dat 모두 UTF-8 BOM 필수

## 다음 세션 첫 행동

portal UNMAPPED 1건 판정 → v8.2/v3 회사 반입 → 회사 portal 실치환 + CLASS 6건 확인

## 최신 핸드오프

→ [2026-07-27](handoffs/2026-07-27.md)

<!--
운영 규칙: 이 README는 항상 최신 상태로 덮어쓴다.
레포는 Claude 프로젝트에 GitHub 연동됨 — push 후 프로젝트 지식에서 Sync now 필수.
새 세션은 붙여넣기 없이 "이어서 하자"로 시작 (Claude가 README와 최신 핸드오프를 자동으로 읽음).
-->
