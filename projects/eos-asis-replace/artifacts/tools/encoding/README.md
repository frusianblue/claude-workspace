# encoding — 한글 인코딩 진단·변환 (B 계열)

| 파일 | 단계 | 역할 |
|---|---|---|
| `Phase0-Init-EncodingConsole.ps1` | B-0 | 콘솔·출력 인코딩·실행정책 고정 (**점 소싱**) |
| `Phase6-Invoke-ReproMatrix.ps1` | B-0 | 4조합 실제 빌드 → **검출기 자체 검증** |
| `Compare-SourceTrees.ps1` | B-3 | 두 소스 트리 전수 비교 (형상 vs WAS) |
| `Compare-SourceToClass-lev1.ps1` | B-3 | 소스↔class 세대 대조 (무컴파일 전수) |
| `Compare-SourceToClass-lev2.ps1` | B-3 | 재컴파일 후 javap 비교 (확정 판정) |
| `Phase2-Compare-Deployment.ps1` | B-3 | 배포본 해시 대조 + jar 중복 + work 캐시 |
| `Scan-JavaSources.ps1` | B-4 | `.java` 인코딩 판별 + 한글/FFFD 라인 |
| `Scan-ClassFiles.ps1` | B-4 | `.class` 상수풀 스캔 (**판정 1순위 근거**) |
| `Expand-ArchivesForScan.ps1` | B-4 | jar/war 내부 class 추출 → Scan-ClassFiles 투입 |
| `Match-SourceToClass.ps1` | B-4 | 위 두 스캔 **결과 dat**를 클래스 단위로 대조 |
| `Phase3-Invoke-Diagnosis.ps1` | B-4 | 가설 1/2/3 분기 판정 |
| `Phase1-Get-TargetFilenameBytes.ps1` | B-5 | 디스크 파일명 바이트 → **D-1 방침 결정** |
| `Phase1-Test-LegacyMangle.ps1` | B-5 | `getBytes("8859_1")` 파괴 로직 재현 |
| `Phase4-Convert-SourceEncoding.ps1` | B-6 | MS949→UTF-8 변환 (백업·검증·`-ExcludeDirs`) |

## lev1 vs Match- — 언제 무엇을 쓰나

입력이 다르다. **결론이 비슷해 보여도 용도가 갈린다.**

| 상황 | 도구 |
|---|---|
| 원본 폴더 2개(class root, src root)에서 바로 시작 | `Compare-SourceToClass-lev1.ps1` ← 30개 소스 표준 경로 |
| 이미 Scan 2종을 돌려놨다 → 산출물 재활용 | `Match-SourceToClass.ps1` |
| lev1이 낸 의심 대상을 확정 | `Compare-SourceToClass-lev2.ps1` |

## 판정값 (Scan-ClassFiles)

| Status | Encoding | 복원 |
|---|---|---|
| `한글정상` | `인코딩일치` | — |
| `깨짐(Latin1)` | `Latin1(UTF8소스)` / `Latin1(949소스)` | 가능 |
| `깨짐(949이중)` | `MS949오컴파일` | 가능 |
| `손실(FFFD)` | `UTF-8오컴파일` | **불가 — 원본 소스 재컴파일** |
| `파싱실패` | `파싱실패` | 판정 보류 |

판정은 문자 범위 추정이 아니라 **역변환 성립 여부**로 한다.
그래서 `·`(U+00B7) `é` `€` 같은 정상 특수문자를 깨짐으로 오판하지 않는다.

## 조용히 깨지는 유일한 경로

UTF-8 소스 + `-encoding ISO-8859-1` → **경고 없이 성공**하고 상수풀에 Latin-1 모지바케가 박힌다.
MS949 소스 + `-encoding UTF-8`은 JDK 12+에서 `unmappable character` 에러로 막히고
JDK 8은 경고 후 U+FFFD로 치환한다. Latin-1은 모든 바이트가 매핑되므로 아무도 막아주지 않는다.
