#!/usr/bin/env python3
"""Generate the project dashboard table in the root README.

Scans projects/*/handoffs/*.md (and archive/*/handoffs/*.md), reads the
frontmatter of the most recent handoff per project, and rewrites the table
between the INDEX markers in README.md.

Stdlib only — no dependencies, so CI stays trivial.

Frontmatter format expected at the top of each handoff file:

    ---
    project: ai-agent-proto
    date: 2026-07-19
    tags: [spring-ai, gemini, tool-calling]
    status: active        # active | paused | archived
    next: "다음 세션 첫 행동 한 줄"
    ---
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
START_MARK = "<!-- INDEX:START -->"
END_MARK = "<!-- INDEX:END -->"

STATUS_EMOJI = {"active": "🟢", "paused": "🟡", "archived": "⚫"}
STATUS_ORDER = {"active": 0, "paused": 1, "archived": 2}

FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(text: str) -> dict[str, str]:
    """Minimal YAML-ish frontmatter parser: `key: value` lines only."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    data: dict[str, str] = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def collect_projects() -> list[dict[str, str]]:
    rows = []
    for base in (ROOT / "projects", ROOT / "archive"):
        if not base.is_dir():
            continue
        for project_dir in sorted(p for p in base.iterdir() if p.is_dir()):
            handoffs = sorted((project_dir / "handoffs").glob("*.md"), reverse=True)
            if not handoffs:
                continue
            fm = parse_frontmatter(handoffs[0].read_text(encoding="utf-8"))
            status = fm.get("status", "archived" if base.name == "archive" else "active")
            rows.append(
                {
                    "name": fm.get("project", project_dir.name),
                    "path": f"{base.name}/{project_dir.name}",
                    "status": status,
                    "date": fm.get("date", handoffs[0].stem),
                    "next": fm.get("next", "—") or "—",
                    "handoff": f"{base.name}/{project_dir.name}/handoffs/{handoffs[0].name}",
                }
            )
    rows.sort(key=lambda r: (STATUS_ORDER.get(r["status"], 9), r["date"]), reverse=False)
    # 상태 우선순위(active 먼저), 같은 상태 내에서는 최근 날짜 우선
    rows.sort(key=lambda r: r["date"], reverse=True)
    rows.sort(key=lambda r: STATUS_ORDER.get(r["status"], 9))
    return rows


def render_table(rows: list[dict[str, str]]) -> str:
    if not rows:
        return "_아직 핸드오프가 없습니다. `templates/handoff-template.md`로 시작하세요._"
    lines = [
        "| 프로젝트 | 상태 | 최근 작업 | 다음 행동 |",
        "|---|---|---|---|",
    ]
    for r in rows:
        emoji = STATUS_EMOJI.get(r["status"], "❔")
        name_link = f"[{r['name']}]({r['path']})"
        date_link = f"[{r['date']}]({r['handoff']})"
        lines.append(f"| {name_link} | {emoji} {r['status']} | {date_link} | {r['next']} |")
    return "\n".join(lines)


def main() -> int:
    if not README.exists():
        print("README.md not found at repo root", file=sys.stderr)
        return 1
    content = README.read_text(encoding="utf-8")
    if START_MARK not in content or END_MARK not in content:
        print(f"Markers {START_MARK} / {END_MARK} missing in README.md", file=sys.stderr)
        return 1

    table = render_table(collect_projects())
    pattern = re.compile(
        re.escape(START_MARK) + r".*?" + re.escape(END_MARK), re.DOTALL
    )
    new_content = pattern.sub(f"{START_MARK}\n{table}\n{END_MARK}", content)

    if new_content != content:
        README.write_text(new_content, encoding="utf-8")
        print("README.md index updated.")
    else:
        print("README.md already up to date.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
