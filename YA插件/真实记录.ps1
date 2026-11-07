# 本包事件账本；独立事件原子发布，不把命中当复用。
function Assert-YaOperation([string]$Package) {
  $operationPath=Join-Path (Get-YaPackageHudHome $Package) 'operation.json'
  if(-not (Test-Path -LiteralPath $operationPath)){return}
  $op=Get-Content -LiteralPath $operationPath -Raw -Encoding UTF8|ConvertFrom-Json
  if($op.status -eq 'completed'){return}
  if($op.status -eq 'pending' -and $op.nonce -and $env:YALINK_OPERATION -ceq $op.nonce){
    $owner=Get-Process -Id $op.owner_pid -ErrorAction SilentlyContinue
    if($owner -and $owner.StartTime.ToUniversalTime().Ticks.ToString() -ceq $op.owner_start){return}
  }
  throw 'RECOVERY_REQUIRED: package operation is pending/blocked; inspect operation.json and software state before any write or retry.'
}
function Write-YaAtomic([string]$Path, $Value) {
  $dir = Split-Path $Path -Parent
  [IO.Directory]::CreateDirectory($dir) | Out-Null
  $tmp = Join-Path $dir ([guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Value -Depth 30), [Text.UTF8Encoding]::new($true))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, ($tmp + '.bak')); [IO.File]::Delete($tmp + '.bak') } else { [IO.File]::Move($tmp, $Path) }
  } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Add-YaActualEvent([string]$Package, [string]$Kind, $Data) {
  $actualHome = Get-YaPackageHudHome $Package
  $id = [guid]::NewGuid().ToString('N')
  $event = [ordered]@{schema=1; id=$id; time=[DateTime]::UtcNow.ToString('o'); kind=$Kind; data=$Data}
  Write-YaAtomic (Join-Path $actualHome ('events\' + $id + '.json')) $event
}
function Import-YaCodexUsage([string]$Package, [string]$Log, [string]$Session, [string]$Task) {
  if (-not $Session -or -not $Task) { throw '用量必须绑定 session= 和 task=' }
  $model = ''; $provider='UNKNOWN'; $models=New-Object 'Collections.Generic.List[string]'; $usage = $null; $stamp = ''; $sessionMatched = $false
  # 只保留用量和来源摘要，不保存对话或工具内容。
  $stream = [IO.File]::Open($Log,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
  try { while ($null -ne ($line = $reader.ReadLine())) {
    try { $e = ConvertFrom-Json -InputObject $line } catch { continue }
    if ($e.type -eq 'session_meta' -and [string]$e.payload.id -ceq $Session) { $sessionMatched = $true; if ($e.payload.model_provider) { $provider=[string]$e.payload.model_provider } }
    if ($e.type -eq 'turn_context' -and $e.payload.model) { $model = [string]$e.payload.model; if (-not $models.Contains($model)) { $models.Add($model) } }
    if ($e.type -eq 'event_msg' -and $e.payload.type -eq 'token_count' -and $e.payload.info.total_token_usage) {
      $usage = $e.payload.info.total_token_usage; $stamp = [string]$e.timestamp
    }
  } } finally { $reader.Dispose() }
  if (-not $sessionMatched -or -not $usage -or -not $model) { throw '日志未提供本会话可核对的模型与用量' }
  $numbers = @{}
  foreach ($key in @('input_tokens','output_tokens','total_tokens')) {
    $n = 0L
    if (-not [long]::TryParse([string]$usage.$key, [ref]$n) -or $n -lt 0) { throw '无效 Token 数值' }
    $numbers[$key] = $n
  }
  if ($numbers.total_tokens -ne $numbers.input_tokens + $numbers.output_tokens) { throw 'Token 总数不一致' }
  $actualHome = Get-YaPackageHudHome $Package
  $mutex = New-Object Threading.Mutex($false, ('Local\YAUsage-' + [YaEvidence]::Identity($Package)))
  $held = $false
  try {
    try { $held = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw '用量记录忙' }
    $path = Join-Path $actualHome 'io\actual_usage.json'
    $old = $null
    if (Test-Path -LiteralPath $path) { $old = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    $base = $numbers.total_tokens; $baseIn=$numbers.input_tokens; $baseOut=$numbers.output_tokens
    if ($old -and $old.session -ceq $Session -and $old.task -ceq $Task) {
      if ($numbers.total_tokens -lt $old.total_tokens) { throw '累计用量倒退，拒绝合并' }
      $base=$old.baseline; $baseIn=$old.baseline_input; $baseOut=$old.baseline_output
    }
    $doc = [ordered]@{schema=1; source_kind='runtime_measured'; source=[IO.Path]::GetFullPath($Log); source_time=$stamp; provider=$provider; model=$model; session_models=@($models.ToArray()); session=$Session; task=$Task; input_tokens=$numbers.input_tokens; output_tokens=$numbers.output_tokens; total_tokens=$numbers.total_tokens; baseline=$base; baseline_input=$baseIn; baseline_output=$baseOut; task_tokens=($numbers.total_tokens-$base); task_input_tokens=($numbers.input_tokens-$baseIn); task_output_tokens=($numbers.output_tokens-$baseOut); scope='session cumulative; task measured since first attachment'; savings_status='待对照'; collected_utc=[DateTime]::UtcNow.ToString('o')}
    Write-YaAtomic $path $doc
    if (-not $old -or $old.session -cne $Session -or $old.task -cne $Task -or $old.total_tokens -ne $numbers.total_tokens) { Add-YaActualEvent $Package 'usage_snapshot' $doc }
    return $doc
  } finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
