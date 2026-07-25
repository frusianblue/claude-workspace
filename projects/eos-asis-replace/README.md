# eos-asis-replace

레거시 EOS 소스 이관 중 AS-IS 하드코딩 경로(d:/)·IP를 TO-BE로 치환하는 작업 (PowerShell 스크립트 기반, 폐쇄망/DRM 제약).

## 현재 상태 (2026-07-25 기준)

- 검색(`Find-AsisPath.ps1` v7)·치환(`Replace-AsisIp.ps1` v4) 스크립트 완성, DryRun까지 검증 완료
- **막힌 곳 없음, 미검증 1건**: `-Apply` 실제 치환은 아직 테스트 안 함
- 대상 소스 약 30개, 실전 투입 전 단계
- 핵심 제약: 회사 DRM(csv/txt 암호화 → `.dat` 운용), bat 차단(ps1 텍스트 반입 → ISE 실행), 스크립트 UTF-8 BOM 필수

## 다음 세션 첫 행동

집 테스트 환경에서 `Replace-AsisIp -Apply` 실행 → 백업 생성·치환·재DryRun 0건 확인

## 최신 핸드오프

→ [2026-07-25](handoffs/2026-07-25.md)

<!--
운영 규칙: 이 README는 항상 최신 상태로 덮어쓴다.
새 Claude 세션 시작 시 이 파일 내용을 붙여넣으면 컨텍스트가 잡히도록 유지.
Claude 프로젝트의 Project Knowledge에도 이 파일을 올려두고 갱신 시 교체.
-->
