# 兼容入口：冻结运行时不变；子进程只使用本包及本包 HUD 状态。
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$pkg = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '连接上下文.ps1')
$actual = Join-Path $PSScriptRoot '真实记录.ps1'
if (Test-Path -LiteralPath $actual) { . $actual }
$runtimeLock = New-Object Threading.Mutex($false, ('Local\YARuntime-' + [YaEvidence]::Identity($pkg)))
$runtimeHeld = $false
$names = @('YALINK_PACKAGE','YALINK_HUD_HOME')
$old = @{}; foreach ($n in $names) { $old[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
try {
  try { $runtimeHeld = $runtimeLock.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $runtimeHeld = $true }
  if (-not $runtimeHeld) { throw '本包任务或经验正在更新，请稍后再试' }
  if(Get-Command Assert-YaOperation -ErrorAction SilentlyContinue){Assert-YaOperation $pkg}
  $env:YALINK_PACKAGE = $pkg
  $env:YALINK_HUD_HOME = Get-YaPackageHudHome $pkg
  $io = Join-Path $env:YALINK_HUD_HOME 'io'
  $file = Join-Path $io 'link.json'
  if (Test-Path -LiteralPath $file) {
    try {
      $link = [YaEvidence]::Read($file)
      if ($link['state'] -eq 'ok' -and [YaEvidence]::CheckRegistered($pkg, $io, $link)) {
        $link['state'] = 'opened'
        [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $link -Depth 8), [Text.UTF8Encoding]::new($true))
      }
    } catch { throw '本包连接状态不可读；先重新准备连接，不沿用旧状态。' }
  }
  $started = [DateTime]::UtcNow
  $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '安装卸载\运行时\ya.ps1') @Rest)
  $result = $LASTEXITCODE
  $lines | Write-Output
  if (Get-Command Add-YaActualEvent -ErrorAction SilentlyContinue) {
    $flow = Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-YaActualEvent $pkg 'runtime' ([ordered]@{command=@($Rest); task=$flow.current; exit_code=$result; elapsed_ms=([DateTime]::UtcNow-$started).TotalMilliseconds; output=$lines; verification='caller_declared'})
  }
} finally {
  foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $old[$n], 'Process') }
  if ($runtimeHeld) { $runtimeLock.ReleaseMutex() }; $runtimeLock.Dispose()
}
exit $result
