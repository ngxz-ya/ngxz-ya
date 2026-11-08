param([Parameter(Mandatory=$true)][string]$Log, [Parameter(Mandatory=$true)][string]$Session, [Parameter(Mandatory=$true)][string]$Task, [switch]$Follow, [ValidateSet('Codex','UsageJsonl','Antigravity')][string]$Format='Codex')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '连接上下文.ps1')
Assert-YaIsolatedPackage (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot '真实记录.ps1')
try {
  do { Import-YaRuntimeUsage (Split-Path $PSScriptRoot -Parent) $Log $Session $Task $Format | ConvertTo-Json -Depth 8
    if ($Follow) { Start-Sleep -Seconds 5 } } while ($Follow)
  Write-Output 'RESULT: OK'
} catch { Write-Output ('error: ' + $_.Exception.Message); Write-Output 'RESULT: FAIL'; exit 1 }
