# 发命令（跨软件通用）：往已连上会话的命令通道写一条命令并等读回。通道由连接卡「快通道.命令通道」定义（命令文件/结果文件，在 WORK 下）。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\发命令.ps1" slot=nx task=实际任务编号 cmd="CREATE_BLOCK 20 20 20"
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\发命令.ps1" slot=nx task=实际任务编号 cmd="CHAMFER 1"
# 只写 WORK 下的命令文件，不按键、不点鼠标、不写包内文件。会话必须是 快连.ps1 起的（读回库带命令通道）。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$commandLock = $null; $lockHeld = $false; $runtimeLock=$null; $runtimeHeld=$false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$a = @{}; foreach ($x in @($Rest)) { if ($x -match '^([^=]+)=(.*)$') { $a[$matches[1].Trim()] = $matches[2].Trim().Trim('"') } }
try {
  $here = $PSScriptRoot; $pkg = Split-Path (Split-Path $here -Parent) -Parent
  . (Join-Path $pkg 'YA插件\连接上下文.ps1') -PathsOnly
  Assert-YaIsolatedPackage $pkg
  $slot = ([string]$a['slot']).ToLower(); $cmd = [string]$a['cmd']
  if (-not $slot -or -not $cmd) { throw '要写 slot= 和 cmd=' }
  $idx = [IO.File]::ReadAllText((Join-Path $here '索引.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
  $row = @($idx.entries | Where-Object { ([string]$_.slot).ToLower() -eq $slot } | Sort-Object { -[int]$_.v })[0]
  if (-not $row) { throw ('槽 ' + $slot + ' 没有连接卡') }
  $card = [IO.File]::ReadAllText((Join-Path $pkg ([string]$row.f)), [Text.Encoding]::UTF8) | ConvertFrom-Json
  $ch = $card.快通道.命令通道
  if (-not $ch) { throw ('卡 ' + $card.id + ' 没有命令通道') }
  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  $actualModule = Join-Path $pkg 'YA插件\真实记录.ps1'
  if (Test-Path -LiteralPath $actualModule) { . $actualModule }
  $io = Join-Path (Get-YaPackageHudHome $pkg) 'io'
  $link = [YaEvidence]::Read((Join-Path $io 'link.json'))
  if ([string]$link['state'] -ne 'ok' -or [string]$link['slot'] -ne $slot -or [YaEvidence]::CheckCommandChannel($pkg, $io, $link)) { throw '本包会话证据缺失或过期；先重新挑战、读回并登记。' }
  $work = [string]$link['command_work']
  $expected = [YaEvidence]::Work($pkg, $slot) + '\'
  if (-not $work -or -not [IO.Path]::GetFullPath($work).StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { throw '命令工作目录不属于本包；请按连接卡复核。' }
  $commandLock = New-Object Threading.Mutex($false, ('Local\YALinkCommand-' + [YaEvidence]::Identity($pkg) + '-' + $slot))
  try { $lockHeld = $commandLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $lockHeld = $true }
  if (-not $lockHeld) { throw '当前软件会话正在处理另一条命令，请等结果后再发。' }
  $runtimeLock=New-Object Threading.Mutex($false, ('Local\YARuntime-' + [YaEvidence]::Identity($pkg)))
  try { $runtimeHeld=$runtimeLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $runtimeHeld=$true }
  if (-not $runtimeHeld) { throw '任务正在更新，未发送软件命令。' }
  Assert-YaOperation $pkg
  . (Join-Path $pkg '安装卸载\运行时\ya_slots.ps1')
  . (Join-Path $pkg '安装卸载\运行时\ya_flow.ps1')
  $flow=Read-YaFlow (Join-Path $pkg '经验库')
  if (-not $a['task'] -or -not $flow.current -or $flow.current.id -cne $a['task'] -or $flow.current.slot -cne $slot -or $flow.current.status -ne '进行中') { throw 'TASK_REQUIRED: 先 task_open 并传 task=当前任务编号；不能沿用已完成任务执行新操作。' }
  if (-not (Test-YaFlag $flow.current.retrieved)) { throw 'SEARCH_REQUIRED: 先按当前任务检索经验，再发送软件命令。' }
  $cf = Join-Path $work ([string]$ch.命令文件); $rf = Join-Path $work ([string]$ch.结果文件)
  foreach ($path in @($cf,$rf)) { if (-not [IO.Path]::GetFullPath($path).StartsWith(([IO.Path]::GetFullPath($work).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw '命令或回执路径越过会话目录' } }
  $executionFile = Join-Path $work 'execution.json'
  $registryFile=Join-Path $work 'requests.json'
  $requestLedger=New-Object 'Collections.Generic.Dictionary[string,object]'
  if (Test-Path -LiteralPath $registryFile) { $requestLedger=[YaEvidence]::Read($registryFile) }
  if ($a['request']) {
    if ($a['request'] -notmatch '^[a-f0-9]{32}$') { throw 'request 必须是32位小写十六进制' }
    if ($requestLedger.ContainsKey([string]$a['request'])) { throw '重复请求拒绝重发；请读取已保存的执行状态' }
  }
  if ((Get-Command Write-YaAtomic -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $executionFile)) {
    $previous = Get-Content -LiteralPath $executionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($previous.state -eq 'pending') { throw '前次执行结果未知；保留命令与迟到回执，核对软件状态后重新握手，禁止自动重发。' }
    if ($a['request'] -and $previous.request -ceq $a['request']) { throw '重复请求拒绝重发；请读取已保存的执行状态' }
  }
  $wait = 30; if ([string]$a['wait'] -match '^\d+$') { $wait = [int]$a['wait'] }
  if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
  $t0 = Get-Date
  $request = [guid]::NewGuid().ToString('N')
  if ($a['request']) { $request=$a['request'] }
  $correlated = [string]$ch.经验协议 -eq '1'
  $payload = $cmd
  if ($correlated) {
    $payload = ConvertTo-Json -InputObject @{ request = $request; command = $cmd } -Compress
  }
  if (Get-Command Write-YaAtomic -ErrorAction SilentlyContinue) {
    Write-YaAtomic $executionFile ([ordered]@{request=$request; task=$a['task']; command=$cmd; session=$link['session']; state='pending'; time=[DateTime]::UtcNow.ToString('o')})
    if ($request) { $requestLedger[$request]=[ordered]@{command=$cmd;session=$link['session'];state='dispatched_once'}; Write-YaAtomic $registryFile $requestLedger }
  }
  [IO.File]::WriteAllText($cf, $payload, (New-Object Text.UTF8Encoding $false))
  $op = ($cmd -split '\s+')[0].ToUpper(); $txt = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $wait) {
    Start-Sleep -Milliseconds 400
    if (Test-Path -LiteralPath $rf) { try { $txt = [IO.File]::ReadAllText($rf, [Text.Encoding]::UTF8) } catch { $txt = '' }; if ($txt -match '(?m)^DONE' -or $txt -match 'STATUS (FAIL|ERROR)') { break } }
  }
  if (-not $txt) { throw ('等 ' + $wait + ' 秒没结果：会话不是 快连.ps1 起的（没加载命令通道），或软件忙/弹窗。') }
  Write-Output $txt.Trim()
  Write-Output ('seconds: ' + [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1))
  if ($correlated) {
    $receipts = [regex]::Matches($txt, '(?m)^YA_REQUEST ([a-f0-9]{32})\r?$')
    if ($receipts.Count -ne 1 -or $receipts[0].Groups[1].Value -cne $request) { throw '软件响应未确认本次请求。' }
    if ($txt -notmatch '(?m)^DONE\s*$') { throw '缺少完整 DONE，执行结果未知' }
  } elseif ($txt -notmatch '(?m)^DONE(?:[^\S\r\n][^\r\n]*)?\r?$') { throw '缺少完整 DONE，执行结果未知' }
  $current=[YaEvidence]::Read((Join-Path $io 'link.json'))
  if ($current['session'] -cne $link['session'] -or [YaEvidence]::CheckCommandChannel($pkg,$io,$current)) { throw '命令期间软件会话变化，保留 pending' }
  $ok=$txt -match '(?m)^STATUS OK[^\S\r\n]*\r?$'
  $receiptFile=Join-Path $work ($request+'.receipt.json')
  $receipt=[ordered]@{request=$request;task=$a['task'];command=$cmd;session=$link['session'];state='executed';correlated=$correlated;verification='pending';command_ok=$ok;result=$txt;elapsed_ms=((Get-Date)-$t0).TotalMilliseconds;time=[DateTime]::UtcNow.ToString('o')}
  Write-YaAtomic $receiptFile $receipt
  Write-YaAtomic $executionFile $receipt
  Add-YaActualEvent $pkg 'command_result' $receipt
  if (-not $ok) { Write-Output 'engineering_result: NOT_VERIFIED'; Write-Output 'RESULT: FAIL'; exit 1 }
  if (-not $correlated) { Write-Output 'engineering_result: NOT_VERIFIED_LEGACY_CHANNEL'; Write-Output 'note: 回执未携带请求号，仅记录命令返回，不自动入库或标任务完成。' }
  if ($correlated) {
    try {
      $matchesFound = [regex]::Matches($txt, '(?m)^YA_EXPERIENCE ([^\r\n]+)')
      if ($txt -notmatch '(?m)^DONE\s*$' -or $matchesFound.Count -ne 1) { throw '缺少本次完整核验读回' }
      $record = ConvertFrom-Json -InputObject $matchesFound[0].Groups[1].Value
      if ($record.request -cne $request) { throw '读回与本次命令不匹配' }
      if ($record.task -and $record.task -cne $a['task']) { throw '读回任务不匹配' }
      $current = [YaEvidence]::Read((Join-Path $io 'link.json'))
      if ($current['session'] -cne $link['session'] -or [YaEvidence]::CheckCommandChannel($pkg, $io, $current)) { throw '连接会话已变化' }
      $checks = @($record.checks)
      if ($checks.Count -lt 1 -or $checks.Count -gt 12) { throw '需要 1 至 12 个软件读回检查项' }
      $proof = foreach ($check in $checks) {
        if (-not ([string]$check.name).Trim()) { throw '检查项缺少名称' }
        $expectedValue = 0d; $actual = 0d; $tolerance = 0d
        $style = [Globalization.NumberStyles]::Float
        $culture = [Globalization.CultureInfo]::InvariantCulture
        if (-not [double]::TryParse([string]$check.expected, $style, $culture, [ref]$expectedValue) -or
            -not [double]::TryParse([string]$check.actual, $style, $culture, [ref]$actual) -or
            -not [double]::TryParse([string]$check.tolerance, $style, $culture, [ref]$tolerance) -or
            [double]::IsNaN($expectedValue) -or [double]::IsNaN($actual) -or [double]::IsNaN($tolerance) -or
            [double]::IsInfinity($expectedValue) -or [double]::IsInfinity($actual) -or [double]::IsInfinity($tolerance) -or
            $tolerance -lt 0 -or [Math]::Abs($expectedValue - $actual) -gt $tolerance) { throw '实测结果未通过容差核对' }
        [ordered]@{ name = [string]$check.name; expected = $expectedValue; actual = $actual; tolerance = $tolerance; unit = [string]$check.unit }
      }
      $title = ([string]$record.title).Trim()
      $method = ([string]$record.method).Trim()
      if (-not $title -or -not $method -or $method.Length -gt 2000) { throw '缺少可复用方法，或方法超过 2000 字' }
      . (Join-Path $pkg '安装卸载\运行时\ya_slots.ps1')
      Assert-YaClean $method
      foreach ($item in $proof) { Assert-YaClean $item.name; Assert-YaClean $item.unit }
      $lib = Join-Path $pkg '经验库'
      $resolved = Resolve-YaSlot $lib $slot
      if ($resolved.id -cne $slot) { throw '经验槽与会话不一致' }
      $title = Repair-YaLine $title
      $index = Read-YaIndex $resolved.dir
      $existing = foreach ($entry in (Get-YaItems $index.entries)) {
        if ($entry.t -cne $title) { continue }
        $savedFile = Get-YaFormalFile $resolved.dir $entry.id
        if ($savedFile -and (Get-YaTextProp (Read-YaJsonFile $savedFile) 'method') -ceq $method) { $entry; break }
      }
      if ($existing) {
        Write-Output ('experience: existing ' + $existing.id)
      } else {
        $draft = New-YaDraft $resolved.dir $slot '招式' $title ([string]$record.keywords) '' ''
        $context = [ordered]@{software=$link['soft']; software_version=$record.software_version; interface_version=$record.interface_version; parameters=$record.parameters; task=$a['task']; model_input=$record.model_input; steps=$record.steps; outcome=$record.outcome; recovery=$record.recovery; applicability=$record.applicability; request=$request; session=$link['session']; command=$cmd; raw_result=$txt; evidence_file=$receiptFile}
        $saved = Publish-YaDraft $resolved.dir $slot $draft.id $method @($proof) $context
        Write-Output ('experience: saved ' + $saved.id)
      }
      Write-Output 'engineering_result: CHECKS_PASSED_ADAPTER_REPORTED'
      if (Get-Command Add-YaActualEvent -ErrorAction SilentlyContinue) {
        Add-YaActualEvent $pkg 'execution' ([ordered]@{request=$request; slot=$slot; session=$link['session']; command=$cmd; record=$record; result=$txt; verification='adapter_reported'; elapsed_ms=((Get-Date)-$t0).TotalMilliseconds})
      }
    } catch { Write-Output ('experience: 未自动入库 · ' + $_.Exception.Message); Write-Output 'engineering_result: FAIL'; Write-Output 'RESULT: FAIL'; exit 1 }
  }
  Write-Output 'RESULT: OK'; exit 0
 } catch { Write-Output ('error: ' + $_.Exception.Message); Write-Output 'RESULT: FAIL'; exit 1 }
finally {
  if ($runtimeHeld) { $runtimeLock.ReleaseMutex() }; if ($runtimeLock) { $runtimeLock.Dispose() }
  if ($lockHeld) { $commandLock.ReleaseMutex() }
  if ($commandLock) { $commandLock.Dispose() }
}
