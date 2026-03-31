$e1 = $null; $e2 = $null
[System.Management.Automation.Language.Parser]::ParseFile('C:\repos\agentic-workflow\setup.ps1', [ref]$null, [ref]$e1) | Out-Null
[System.Management.Automation.Language.Parser]::ParseFile('C:\repos\agentic-workflow\scripts\serena-docker.ps1', [ref]$null, [ref]$e2) | Out-Null
if ($e1.Count -eq 0) { Write-Host "setup.ps1: OK" } else { $e1 | ForEach-Object { Write-Host "setup.ps1 ERROR: $_" } }
if ($e2.Count -eq 0) { Write-Host "serena-docker.ps1: OK" } else { $e2 | ForEach-Object { Write-Host "serena-docker.ps1 ERROR: $_" } }
