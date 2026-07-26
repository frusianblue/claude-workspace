Import-Csv .\report\portal_ip_all.dat |
  Where-Object { $_.FoundIn -eq 'FILE' } |
  ForEach-Object { [regex]::Matches($_.Match, '(?:\d{1,3}\.){3}\d{1,3}') } |
  ForEach-Object { ($_.Value -replace '[\\/]+','/').ToLower() } |
  Sort-Object -Unique