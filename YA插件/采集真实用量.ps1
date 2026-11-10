param([Parameter(Mandatory=$true)][string]$Log, [string]$Session, [string]$Task, [switch]$Follow, [switch]$AutoFromLog, [ValidateSet('Auto','Grok','Codex','UsageJsonl','Antigravity')][string]$Format='Auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '连接上下文.ps1')
Assert-YaIsolatedPackage (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot '真实记录.ps1')
try {
  $pkgRoot = Split-Path $PSScriptRoot -Parent
  if ($AutoFromLog -or $Format -eq 'Auto') { $Format = Resolve-YaUsageFormat $Log $Format }
  if (($AutoFromLog -or -not $Session) -and -not $Session) { $Session = Get-YaUsageSessionFromLog $Log $Format }
  if ($AutoFromLog -or -not $Task) {
    $flowFile = Join-Path $pkgRoot '经验库\流程.json'
    if (Test-Path -LiteralPath $flowFile) {
      try { $flow = Get-Content -LiteralPath $flowFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($flow.current.id) { $Task = [string]$flow.current.id } } catch { }
    }
    if (-not $Task) { $Task = 'hud-auto' }
  }
  if (-not $Session -or -not $Task) { throw '用量必须绑定 session= 和 task=（或使用 -AutoFromLog）' }
  do { Import-YaRuntimeUsage $pkgRoot $Log $Session $Task $Format | ConvertTo-Json -Depth 8
    if ($Follow) { Start-Sleep -Seconds 5 } } while ($Follow)
  Write-Output 'RESULT: OK'
} catch { Write-Output ('error: ' + $_.Exception.Message); Write-Output 'RESULT: FAIL'; exit 1 }
