# eos-asis-replace

레거시 EOS 소스 이관 중 AS-IS 하드코딩 경로(d:/)·IP를 TO-BE로 치환하는 작업 (PowerShell 스크립트 기반, 폐쇄망/DRM 제약).

## 현재 상태 (2026-07-25 기준)

- 도구 세트 완성: 조사 `Find-AsisPath v8`(RootList 일괄, 소스별 증적) + 경로 치환 `Replace-AsisPath v1`(매핑표, DryRun/Apply, 스타일·인코딩 보존) + 실행 가이드. 모두 PS 7.4에서 실행 검증 완료
- 회사 실전 첫 조사 완료: portal 45건 (실 치환 대상 src 6건 추정, CLASS 6건 java 대응 확인 필요)
- 확정 흐름: Find all → 경로 매핑표 → 경로 치환 → IP 치환 → 재빌드 → Find build 0건 → 파일 외
- **미검증 2건**: 스크립트들 PS 5.1 실행 / Replace-AsisIp -Apply
- 제약: 회사 DRM(.dat 운용), bat 차단(ISE 붙여넣기+param 기본값 수정), UTF-8 BOM 필수

## 다음 세션 첫 행동

집 PS 5.1에서 실소스 1건 풀사이클: Find v8(all) → 매핑표 → Replace-AsisPath DryRun→Apply→재DryRun 0건

## 최신 핸드오프

→ [2026-07-25](handoffs/2026-07-25.md)

<!--
운영 규칙: 이 README는 항상 최신 상태로 덮어쓴다.
새 Claude 세션 시작 시 이 파일 내용을 붙여넣으면 컨텍스트가 잡히도록 유지.
Claude 프로젝트의 Project Knowledge에도 이 파일을 올려두고 갱신 시 교체.
-->
