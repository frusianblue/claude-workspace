# ai-agent-proto

Spring AI + Gemini 기반 AI Agent 프로토타입 (tool calling으로 예약 시스템 연동).

## 현재 상태 (2026-07-19 기준)

- tool calling 2회 호출 구조(선택 → 실행 → 생성) 개념 이해 완료
- **막힌 곳**: 브레이크포인트가 안 멈춤 — 잔여 프로세스의 포트 점유 의심
- 표준 문서 초안 완성, 팀 리뷰 대기

## 다음 세션 첫 행동

Debug 탭에서 두 앱 프로세스 생존 확인 → `Port already in use` 로그 확인

## 최신 핸드오프

→ [2026-07-19](handoffs/2026-07-19.md)

<!--
운영 규칙: 이 README는 항상 최신 상태로 덮어쓴다.
새 Claude 세션 시작 시 이 파일 내용을 붙여넣으면 컨텍스트가 잡히도록 유지.
Claude 프로젝트의 Project Knowledge에도 이 파일을 올려두고 갱신 시 교체.
-->
