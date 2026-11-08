# 本包事件账本；独立事件原子发布，不把命中当复用。
function Assert-YaOperation([string]$Package) {
  $operationPath=Join-Path (Get-YaPackageHudHome $Package) 'operation.json'
  $op=$null
  if(Test-Path -LiteralPath $operationPath){$op=Get-Content -LiteralPath $operationPath -Raw -Encoding UTF8|ConvertFrom-Json}
  if($op.status -eq 'pending' -and $op.nonce -and $env:YALINK_OPERATION -ceq $op.nonce){
    $owner=Get-Process -Id $op.owner_pid -ErrorAction SilentlyContinue
    if($owner -and $owner.StartTime.ToUniversalTime().Ticks.ToString() -ceq $op.owner_start){return}
  }
  $guard=Join-Path (Get-YaPackageHudHome $Package) 'operation_request.json'
  if(Test-Path -LiteralPath $guard){
    $ref=Get-Content -LiteralPath $guard -Raw -Encoding UTF8|ConvertFrom-Json
    $state=Get-Content -LiteralPath $ref.state_file -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $ref.request -or $state.request -cne $ref.request -or $state.status -ne 'completed'){throw 'RECOVERY_REQUIRED: original request is incomplete; editing operation.json cannot resolve it.'}
  }
  if(-not $op -or $op.status -eq 'completed'){return}
  throw 'RECOVERY_REQUIRED: package operation is pending/blocked; inspect operation.json and software state before any write or retry.'
}
function Write-YaAtomic([string]$Path, $Value) {
  $dir = Split-Path $Path -Parent
  [IO.Directory]::CreateDirectory($dir) | Out-Null
  $tmp = Join-Path $dir ([guid]::NewGuid().ToString('N') + '.tmp')
  $backup = [IO.Path]::ChangeExtension($tmp, '.bak')
  try {
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Value -Depth 30), [Text.UTF8Encoding]::new($true))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, $backup); [IO.File]::Delete($backup) } else { [IO.File]::Move($tmp, $Path) }
  } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Add-YaActualEvent([string]$Package, [string]$Kind, $Data) {
  $actualHome = Get-YaPackageHudHome $Package
  $id = [guid]::NewGuid().ToString('N')
  $event = [ordered]@{schema=1; id=$id; time=[DateTime]::UtcNow.ToString('o'); kind=$Kind; data=$Data}
  Write-YaAtomic (Join-Path $actualHome ('events\' + $id + '.json')) $event
}
function Import-YaRuntimeUsage([string]$Package, [string]$Log, [string]$Session, [string]$Task, [ValidateSet('Codex','UsageJsonl','Antigravity')][string]$Format='Codex') {
  if (-not $Session -or -not $Task) { throw '用量必须绑定 session= 和 task=' }
  $model = ''; $provider='UNKNOWN'; $agent=$Format; $models=New-Object 'Collections.Generic.List[string]'; $usage = $null; $stamp = ''; $sessionMatched = $false
  # 只保留用量和来源摘要，不保存对话或工具内容。
  $stream = [IO.File]::Open($Log,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
  try { while ($null -ne ($line = $reader.ReadLine())) {
    try { $e = ConvertFrom-Json -InputObject $line } catch { if ($Format -eq 'UsageJsonl') { throw '通用用量 JSONL 损坏，等待完整记录后重试' }; continue }
    if ($Format -eq 'Antigravity') {
      # Native CLI terminal results are cumulative; step_update usage must not be added again.
      if ($e.event -eq 'init') {
        if ([string]$e.conversation_id -cne $Session) { throw 'Antigravity 会话不匹配' }
        if ($e.init.model) { $model=[string]$e.init.model }
        continue
      }
      $result=if($e.event -eq 'result'){$e.result}elseif($e.conversation_id -and $e.usage){$e}else{$null}
      if (-not $result) { continue }
      if ([string]$result.conversation_id -cne $Session) { throw 'Antigravity 会话不匹配' }
      if ($result.status -notin @('SUCCESS','ERROR','CANCELLED','CANCELED','INTERRUPTED')) { throw 'Antigravity 终态无法识别' }
      foreach($key in @('input_tokens','output_tokens','total_tokens')) { $n=0L; if(-not [long]::TryParse([string]$result.usage.$key,[ref]$n) -or $n -lt 0){throw 'Antigravity 用量数值无效'} }
      if([decimal]$result.usage.total_tokens -ne [decimal]$result.usage.input_tokens+[decimal]$result.usage.output_tokens){throw 'Antigravity 用量口径不符，拒绝猜算'}
      if($usage -and ([decimal]$result.usage.input_tokens -lt [decimal]$usage.input_tokens -or [decimal]$result.usage.output_tokens -lt [decimal]$usage.output_tokens)){throw 'Antigravity 累计用量倒退'}
      $usage=$result.usage;$sessionMatched=$true;$provider='Antigravity';$agent='Antigravity CLI'
      if(-not $model){$model='UNKNOWN (not exported)'}
      if(-not $models.Contains($model)){$models.Add($model)}
      $stamp=[IO.File]::GetLastWriteTimeUtc($Log).ToString('o')
      continue
    }
    if ($Format -eq 'UsageJsonl') {
      if ($e.type -ne 'usage_snapshot') { continue }
      if ([string]$e.session -cne $Session) { throw '用量源混入其他会话，拒绝导入' }
      $time=[DateTimeOffset]::MinValue
      if ($e.schema -ne 1 -or $e.scope -ne 'session_cumulative' -or -not $e.agent -or -not $e.provider -or -not $e.model -or -not [DateTimeOffset]::TryParse([string]$e.timestamp,[ref]$time)) { throw '通用用量记录缺少来源、累计范围或有效时间' }
      if ($sessionMatched -and ($provider -cne [string]$e.provider -or $agent -cne [string]$e.agent)) { throw '同一累计会话的来源发生变化' }
      foreach ($key in @('input_tokens','output_tokens','total_tokens')) { $n=0L; if (-not [long]::TryParse([string]$e.usage.$key,[ref]$n) -or $n -lt 0) { throw '无效 Token 数值' } }
      if ([decimal]$e.usage.total_tokens -ne [decimal]$e.usage.input_tokens + [decimal]$e.usage.output_tokens) { throw 'Token 总数不一致' }
      if ($usage -and ($time -lt [DateTimeOffset]::Parse($stamp) -or [decimal]$e.usage.input_tokens -lt [decimal]$usage.input_tokens -or [decimal]$e.usage.output_tokens -lt [decimal]$usage.output_tokens)) { throw '用量记录倒退' }
      $sessionMatched=$true; $provider=[string]$e.provider; $agent=[string]$e.agent; $model=[string]$e.model
      if (-not $models.Contains($model)) { $models.Add($model) }
      $usage=$e.usage; $stamp=[string]$e.timestamp
      continue
    }
    if ($e.type -eq 'session_meta') { if ([string]$e.payload.id -cne $Session) { throw 'Codex 用量源混入其他会话，拒绝导入' }; $sessionMatched = $true; if ($e.payload.model_provider) { $provider=[string]$e.payload.model_provider } }
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
    if ($old -and $old.session -ceq $Session) {
      if ($old.provider -cne $provider -or ($old.source_format -and $old.source_format -cne $Format)) { throw '用量来源变化，拒绝混合累计' }
      if ($numbers.input_tokens -lt $old.input_tokens -or $numbers.output_tokens -lt $old.output_tokens -or $numbers.total_tokens -lt $old.total_tokens) { throw '累计用量倒退，拒绝合并' }
    }
    if ($old -and $old.session -ceq $Session -and $old.task -ceq $Task) {
      $base=$old.baseline; $baseIn=$old.baseline_input; $baseOut=$old.baseline_output
    }
    $doc = [ordered]@{schema=1; source_kind='runtime_measured'; source=[IO.Path]::GetFullPath($Log); source_time=$stamp; provider=$provider; model=$model; session_models=@($models.ToArray()); session=$Session; task=$Task; input_tokens=$numbers.input_tokens; output_tokens=$numbers.output_tokens; total_tokens=$numbers.total_tokens; baseline=$base; baseline_input=$baseIn; baseline_output=$baseOut; task_tokens=($numbers.total_tokens-$base); task_input_tokens=($numbers.input_tokens-$baseIn); task_output_tokens=($numbers.output_tokens-$baseOut); scope='session cumulative; task measured since first attachment'; savings_status='待对照'; collected_utc=[DateTime]::UtcNow.ToString('o')}
    $doc['source_format']=$Format; $doc['agent']=$agent
    if($Format -eq 'Antigravity'){
      $doc['source_time_kind']='export_file_mtime';$doc['provider_scope']='agent platform; underlying model provider not exported'
      foreach($key in @('thinking_tokens','cache_read_tokens')){if($null -ne $usage.$key){$n=0L;if(-not [long]::TryParse([string]$usage.$key,[ref]$n) -or $n -lt 0){throw 'Antigravity 明细无效'};$doc[$key]=$n}}
    }
    Write-YaAtomic $path $doc
    if (-not $old -or $old.session -cne $Session -or $old.task -cne $Task -or $old.total_tokens -ne $numbers.total_tokens) { Add-YaActualEvent $Package 'usage_snapshot' $doc }
    return $doc
  } finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
function Import-YaCodexUsage([string]$Package, [string]$Log, [string]$Session, [string]$Task) {
  Import-YaRuntimeUsage $Package $Log $Session $Task 'Codex'
}
