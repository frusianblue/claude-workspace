Import-Csv .\report\portal_asis.dat |
  Where-Object { $_.FoundIn -eq 'FILE' } |
  ForEach-Object { [regex]::Matches($_.Match, '[dD]:[/\\]+[^/\\";''<>\s,)]*[/\\]?[^/\\";''<>\s,)]*') } |
  ForEach-Object { ($_.Value -replace '[\\/]+','/').ToLower() } |
  Sort-Object -Unique