# _deprecated — 실행하지 말 것

삭제하지 않고 남긴다. **아직 이식되지 않은 기능이 있는지 확인할 근거**가 필요하기 때문이다.

| 파일 | 대체 | 남은 확인거리 |
|---|---|---|
| `Check-ClassEncoding.ps1` | `Scan-ClassFiles.ps1` | `-IncludeArchives`는 `Expand-ArchivesForScan.ps1`로 대체했다. 다른 미이식 기능이 없는지 확인 후 최종 폐기 |
| `Convert-ToUtf8.ps1` | `Phase4-Convert-SourceEncoding.ps1` | `-Extensions` 다중 확장자 처리는 아직 Phase4에 없다 — 이식 필요 |
| `Folder-Check.ps1` | `Extract-MappingDraft.ps1 -Mode Path` | 없음 |
| `Ip-Check.ps1` | `Extract-MappingDraft.ps1 -Mode Ip` | 없음 |

## 이 파일들의 결과를 근거로 쓰지 말 것

`Check-ClassEncoding.ps1`의 판정 로직은 `Scan-ClassFiles.ps1`보다 구세대다.
`Folder-Check` / `Ip-Check`는 입력 파일명이 하드코딩돼 있어 실제 리포트명과 맞지 않아,
그대로 실행하면 실패하거나 엉뚱한 파일을 읽는다.
