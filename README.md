# claude-workspace

프로젝트별 핸드오프 문서와 학습 기록을 관리하는 개인 지식 레포.

## 📊 대시보드

<!-- INDEX:START -->
| 프로젝트 | 상태 | 최근 작업 | 다음 행동 |
|---|---|---|---|
| [eos-asis-replace](projects/eos-asis-replace) | 🟢 active | [2026-07-25](projects/eos-asis-replace/handoffs/2026-07-25.md) | Replace-AsisIp -Apply 실제 치환 테스트 (집 환경: 백업 생성 → 치환 → 재DryRun 0건 확인) |
| [ai-agent-proto](projects/ai-agent-proto) | 🟢 active | [2026-07-19](projects/ai-agent-proto/handoffs/2026-07-19.md) | Debug 탭에서 두 앱 프로세스 생존 확인 (포트 점유 의심, Port already in use 로그) |
<!-- INDEX:END -->

> 이 표는 `scripts/generate_index.py`가 각 프로젝트의 최신 핸드오프 frontmatter를 읽어 자동 생성합니다. 손으로 고치지 마세요 — push 시 GitHub Actions가 덮어씁니다.

## 구조

```
projects/<이름>/
├── README.md        # 현재 상태 요약 (항상 최신, 덮어쓰기) — Claude 세션 시작용
├── handoffs/        # 날짜별 스냅샷 (YYYY-MM-DD.md, append-only)
├── concepts/        # 시간이 지나도 유효한 개념 정리
└── artifacts/       # 산출물 (문서 초안 등)
archive/             # 종료된 프로젝트를 폴더째 이동
concepts/            # 프로젝트를 넘나드는 공용 개념 (주제별: spring-ai/, k8s/ ...)
templates/           # handoff-template.md
scripts/             # 인덱스 자동 생성
```

## 운영 규칙

1. **핸드오프는 append-only** — 매 세션 종료 시 `templates/handoff-template.md`를 복사해 새 날짜 파일 생성. 어제 파일을 수정하지 않는다.
2. **frontmatter는 필수** — 특히 `next`(다음 행동)와 `status`. 대시보드가 여기서 나온다.
3. **프로젝트 README는 덮어쓰기** — 새 Claude 세션 시작 시 이 파일 하나만 붙여넣으면 되도록 유지.
4. **개념은 증류** — 핸드오프의 "이해한 것"이 안정화되면 `concepts/`로 옮기고 핸드오프엔 링크만.
5. **주제 검색은 태그로** — `grep -r "spring-ai" --include="*.md" .`

## 코드 레포와의 연결

핸드오프에서 코드 특정 시점을 가리킬 땐 커밋 해시/태그로 링크:
`https://github.com/<user>/ai-agent-proto/blob/<commit-hash>/...`

## 로컬에서 인덱스 갱신

```bash
python scripts/generate_index.py
```
