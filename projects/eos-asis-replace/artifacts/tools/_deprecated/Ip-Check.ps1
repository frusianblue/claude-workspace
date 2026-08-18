# ===========================================================================
# [폐기] Ip-Check.ps1
#   사유 : Extract-MappingDraft.ps1 -Mode Ip 로 대체됨
#   비고 : 입력 파일명이 report\portal_ip_all.dat 로 하드코딩돼 있어 실제 리포트명과 불일치했다.
#
#   이 폴더의 파일은 실행하지 말 것. 삭제하지 않고 남겨둔 이유는
#   '아직 이식되지 않은 기능이 있는지' 나중에 확인할 근거가 필요하기 때문이다.
# ===========================================================================
Import-Csv .\report\portal_ip_all.dat |
  Where-Object { $_.FoundIn -eq 'FILE' } |
  ForEach-Object { [regex]::Matches($_.Match, '(?:\d{1,3}\.){3}\d{1,3}') } |
  ForEach-Object { ($_.Value -replace '[\\/]+','/').ToLower() } |
  Sort-Object -Unique