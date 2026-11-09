# YA 插件 · 连接态登记。软件前台窗口可见、并且 Agent 已从软件读回真实状态之后调用；随后自动弹出 YA 白底卡。
# 软件无关：soft= 写你实际连上的那款软件的名字（卡上显示「连接成功 · 名字」）。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\YA插件\ya_link.ps1" soft=软件名 pid=软件主窗口进程号 slot=经验槽 [prepare=1] [log=Agent输出日志] [agent=Agent名] [agent_pid=Agent进程号]
# 经 WMI 等系统进程转调时（父进程是 WmiPrvSE），Agent 的环境变量和父子链都断了：要显式传 log= / agent= / agent_pid=（快连.ps1 会自动传）。
# 状态卡按包路径和 HUD Home 互斥去重，不终止其它进程。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\YA插件\ya_link.ps1" off=1      标成未连接
# pid 必填，且该进程主窗口必须前台可见；后台进程、隐藏窗口、批处理/命令行无界面运行都会 RESULT: FAIL。
# TOKEN：log= 仅记录来源指针；真实统计需按说明显式运行采集真实用量.ps1，没有有效用量显示「未统计」。
# 只写本包隔离的 %LOCALAPPDATA%\YAHud\instances\<包标识>\io\link.json（或环境变量 YALINK_HUD_HOME），不改安装目录、不碰软件。
# 连接钩子（2026-11-05 掌门定规，所有软件同一套）：登记成功前自动确保这款软件的专属经验夹存在（连接教练\连接经验\经验分存.ps1 ensure）：
#   经验库\槽\<槽>\（招式库/坑库/零件方案库/_草稿/索引.json）+ 连接教练\连接经验\<槽>\。证据协议必填 slot=；不再落到 generic。正式包、测试包都自动建，人不手建。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try {
  $map = @{}
  foreach ($kv in @($Rest)) {
    if (-not $kv) { continue }
    $i = $kv.IndexOf('=')
    if ($i -lt 1) { throw ('参数要写成 名字=值 ：' + $kv) }
    $map[$kv.Substring(0, $i)] = $kv.Substring($i + 1)
  }
  function A([string]$n) { if ($map.ContainsKey($n)) { return [string]$map[$n] } return '' }

  $pkg = Split-Path $PSScriptRoot -Parent
  $runtime = Join-Path $pkg '安装卸载\运行时'
  . (Join-Path $runtime 'ya_slots.ps1')
  . (Join-Path $runtime 'ya_flow.ps1')   # Format-YaShownId 等报错用的函数在这里
  $lib = Initialize-YaLibrary $pkg

  . (Join-Path $PSScriptRoot '连接上下文.ps1')
  $hudHome = Get-YaPackageHudHome $pkg
  $io = Join-Path $hudHome 'io'
  if (-not (Test-Path -LiteralPath $io)) { New-Item -ItemType Directory -Path $io -Force | Out-Null }
  $linkPath = Join-Path $io 'link.json'
  $hud = Join-Path $PSScriptRoot 'ya_hud.ps1'


  function Show-YaHud {
    if (Test-Path -LiteralPath (Join-Path $hudHome 'hud.off')) {
      Write-Host 'hud: 有 hud.off，未交付面板';return $false
    } else {
      $output=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'show_ya.ps1') -WithSoftware)
      $code=$LASTEXITCODE
      $output|ForEach-Object {Write-Host ('hud: '+$_)}
      return ($code -eq 0)
    }
  }

  if ((A 'off') -eq '1') {
    $softOff = ''
    if (Test-Path -LiteralPath $linkPath) { try { $softOff = [string](Get-YaTextProp (Read-YaJsonFile $linkPath) 'soft') } catch { } }
    Write-YaJsonFile $linkPath ([ordered]@{ version = 1; state = 'off'; soft = $softOff; slot = ''; pid = 0; agent = ''; agent_pid = 0; log = ''; time = (Get-Date).ToString('s') })
    # 清本次 TOKEN/调用指针，避免卡上吞旧 Temp\ya_draw_*.log
    foreach ($n in @('agent_log.txt','usage_log.txt','hud_cost_debug.txt')) {
      $p = Join-Path $io $n
      try { if (Test-Path -LiteralPath $p) { [IO.File]::WriteAllText($p, '', (New-Object Text.UTF8Encoding $false)) } } catch { }
    }
    try {
      $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      [IO.File]::WriteAllText((Join-Path $io 'agent.json'), '{"pid":0,"agent":"","time":0}', (New-Object Text.UTF8Encoding $false))
      [IO.File]::WriteAllText((Join-Path $io 'exp_stats.json'), ('{"nx_pid":0,"uses":0,"task_start":' + $now + ',"agent":"","agent_switch":"","soft":"","slot":"generic"}'), (New-Object Text.UTF8Encoding $false))
    } catch { }
    Write-Output 'state: 未连接'
    Write-Output 'cleared: agent_log/usage_log/exp_stats 本次指针'
    Write-Output 'RESULT: OK'
    exit 0
  }

  $soft = A 'soft'
  if (-not $soft) { throw '要写 soft=软件名（你实际连上的那款）。没连上就不要调用。' }
  $pidText = A 'pid'
  if (-not $pidText) { throw '要写 pid=软件主窗口进程号。软件前台窗口可见才算连接成功；后台、批处理、看不见的进程都不算。' }
  if ($pidText -notmatch '^\d+$') { throw 'pid= 要写数字。' }
  $softPid = [int]$pidText
  try { $proc = Get-Process -Id $softPid -ErrorAction Stop } catch { throw ('进程 ' + $softPid + ' 不在，不能标连接成功。') }
  if (-not ('YaHudLink.Win' -as [type])) { Add-Type -Namespace YaHudLink -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);' }
  $mw = [YaWindow]::Find($softPid)
  if ($mw -eq [IntPtr]::Zero -or -not [YaWindow]::Ready($softPid)) { throw ('进程 ' + $softPid + ' 主窗口不可见（后台/批处理/还没出界面）。软件前台窗口可见才算连接成功。') }
  $resp = $false; try { $resp = [YaWindow]::Ready($softPid) } catch { }
  if (-not $resp) { throw ('进程 ' + $softPid + ' 主窗口未响应，不能标连接成功。') }

  $slotId = (A 'slot').ToLowerInvariant()
  $work = [YaEvidence]::Work($pkg, $slotId)
  $packageId = [YaEvidence]::Identity($pkg)
  $pending = [ordered]@{state='opened'; soft=$soft; package_id=$packageId; slot=$slotId; pid=$softPid; process_start=$proc.StartTime.ToUniversalTime().Ticks.ToString()}
  try {
    $prior = [YaEvidence]::Read($linkPath)
    if ($prior['package_id'] -ceq $packageId -and $prior['slot'] -ceq $slotId -and
        [string]$prior['pid'] -eq [string]$softPid -and [string]$prior['process_start'] -eq $pending.process_start) {
      $pending['command_work'] = $prior['command_work']
      $pending['session'] = $prior['session']
    }
  } catch { }
  if ((A 'prepare') -eq '1') {
    $session = [guid]::NewGuid().ToString('N')
    $sessionDir = Join-Path $work $session
    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    $challenge = [ordered]@{ package_id=$packageId; slot=$slotId; session=$session; nonce=[guid]::NewGuid().ToString('N'); pid=$softPid; process_start=$proc.StartTime.ToUniversalTime().Ticks.ToString(); issued_utc=[DateTime]::UtcNow.ToString('o') }
    Write-YaJsonFile (Join-Path $io 'challenge.json') $challenge
    Write-YaJsonFile (Join-Path $sessionDir 'challenge.json') $challenge
    Write-YaJsonFile $linkPath $pending
    Write-Output ('challenge: ' + (Join-Path $sessionDir 'challenge.json'))
    Write-Output ('readback: ' + (Join-Path $sessionDir 'readback.json'))
    Write-Output ('package: ' + $pkg)
    Write-Output 'state: 已打开 · 待读回（未连接）'
    Write-Output 'RESULT: PENDING'
    exit 2
  }
  $proof = $null
  try {
    $proof = [YaEvidence]::Read((Join-Path $io 'challenge.json'))
    if ([string]$proof['session'] -notmatch '^[a-f0-9]{32}$') { throw '会话号不合规。' }
    $proof['readback_sha256'] = [YaEvidence]::Hash((Join-Path (Join-Path $work ([string]$proof['session'])) 'readback.json'))
    $reason = [YaEvidence]::Check($pkg, $io, $proof)
    if ([string]$proof['pid'] -ne [string]$softPid -or [string]$proof['slot'] -ne $slotId) { $reason = 'wrong-target' }
  } catch { $reason = 'missing-or-invalid-evidence' }
  if ($reason) {
    $pending['evidence_error'] = $reason
    Write-YaJsonFile $linkPath $pending
    throw ('已打开 · 待读回（未连接）：' + $reason + '；先 prepare=1，再由软件合法通道写 readback.json。')
  }

  $foregroundPid = [uint32]0
  [void][YaHudLink.Win]::GetWindowThreadProcessId([YaHudLink.Win]::GetForegroundWindow(), [ref]$foregroundPid)
  if ($foregroundPid -ne $softPid) { throw '读回已匹配，但目标主窗口尚未置前；不登记成功。' }
  # 连接钩子：自动确保专属经验夹（经验库\槽\<槽>\ + 连接教练\连接经验\<槽>\）。失败就不登记，不再悄悄落到 generic。
  $slotNote = ''
  $ensurePs = Join-Path $pkg '连接教练\连接经验\经验分存.ps1'
  if (-not (Test-Path -LiteralPath $ensurePs)) { throw ('缺少 ' + $ensurePs + '：连上软件要自动建专属经验夹。') }
  $ensureOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $ensurePs ensure ('soft=' + $soft) ('slot=' + (A 'slot')) 2>&1 | Out-String)
  if ($ensureOut -notmatch 'RESULT: OK') { throw ('自动建专属经验夹失败：' + (($ensureOut -split "`r?`n") | Where-Object { $_ -match '^ERROR' }) ) }
  $slotId = ([regex]::Match($ensureOut, '(?m)^slot:\s*(\S+)')).Groups[1].Value
  if ($slotId -ne [string]$proof['slot']) { throw '软件名与证据槽冲突；使用正确槽重新 prepare。' }
  $resolved = Resolve-YaSlot $lib $slotId
  $expDirLine = (($ensureOut -split "`r?`n") | Where-Object { $_ -match '^(exp_dir|conn_dir|count|note):' }) -join '; '
  if ($ensureOut -match '新建：连接时自动建') { $slotNote = '专属经验夹已自动新建' } else { $slotNote = '专属经验夹已有' }
  # 首连即存（2026-11-05）：开源包不预置任何软件连接卡。这款软件本地还没有连接卡时，登记成功就自动在它的专属连接夹落一份「首连记录」草稿（v=0，本机本人用，不随开源包分发），
  # 记下这次真实连上的进程/路径/窗口/Agent；连法步骤由 Agent 按自己刚走通的合法办法补成连接卡：连接经验.ps1 add slot=<槽> file=卡.json，以后再连 find 命中、快连可复用。
  $firstNote = ''
  try {
    $connSlotDir = Join-Path $pkg ('连接教练\连接经验\' + $slotId)
    if (-not (Test-Path -LiteralPath $connSlotDir)) { New-Item -ItemType Directory -Path $connSlotDir -Force | Out-Null }
    $hasCard = @(Get-ChildItem -LiteralPath $connSlotDir -Filter '连接卡-*.json' -File -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasCard) {
      $dDir = Join-Path $connSlotDir '_草稿'
      if (-not (Test-Path -LiteralPath $dDir)) { New-Item -ItemType Directory -Path $dDir -Force | Out-Null }
      $exe = ''; try { $exe = [string]$proc.Path } catch { }
      $rec = [ordered]@{ evidence_session=$proof['session']; readback_sha256=$proof['readback_sha256']; 适用前提='待补版本、合法通道及环境'; 参数='待补';  类型 = '首连记录'; v = 0; 状态 = '草稿：待 Agent 补连法后 add 成连接卡'; soft = $soft; slot = $slotId; time = (Get-Date).ToString('s'); 进程名 = [string]$proc.ProcessName; 程序路径 = $exe; 窗口标题 = [YaWindow]::Title($mw); agent = (A 'agent'); 来源 = 'ya_link.ps1 首连即存（本机本人，开源包不带）'; 待补 = '连法步骤（合法开源/官方接口）、读回方式、核验办法' }
      $rf = Join-Path $dDir ('首连记录-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.json')
      [IO.File]::WriteAllText($rf, ($rec | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
      $firstNote = '首连记录已存 ' + $rf.Substring($pkg.Length + 1) + '；请把刚走通的连法写成卡：连接经验.ps1 add slot=' + $slotId + ' file=卡.json'
    }
  } catch { $firstNote = '首连记录没存上：' + $_.Exception.Message }
  if ($firstNote) { Write-Output ('first_link: ' + $firstNote) }

  # 只接收本次 log= 或当前进程环境变量；不读取持久设置或旧指针。
  $log = A 'log'
  $logFrom = 'log='
  if (-not $log) { $log = [string]$env:YALINK_USAGE_LOG; $logFrom = 'env' }
  $ptr = Join-Path $io 'agent_log.txt'
  if ($log) { $log = $log.Split(';')[0].Trim().Trim('"') }
  if ($log -and -not (Test-Path -LiteralPath $log -PathType Leaf)) { $log = '' }
  if (-not $log) { $logFrom = '' }
  $agent = A 'agent'
  $agentPid = 0
  $ap = A 'agent_pid'
  if ($ap -match '^\d+$' -and [int]$ap -gt 0) { $agentPid = [int]$ap }
  if ($agentPid -eq 0) {
    $cur = $PID
    for ($k = 0; $k -lt 12; $k++) {
      $row = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $cur) -ErrorAction SilentlyContinue
      if (-not $row -or -not $row.ParentProcessId) { break }
      $pp = [int]$row.ParentProcessId
      $pr = Get-Process -Id $pp -ErrorAction SilentlyContinue
      if (-not $pr) { break }
      # 系统进程（WMI 转调、服务、资源管理器）不是 Agent：到这里就断了链，Agent 记「未知」，不记 WmiPrvSE
      if ($pr.ProcessName -match '^(WmiPrvSE|svchost|services|wininit|winlogon|explorer|taskeng|taskhostw|smss|csrss|System)$') { break }
      if ($pr.ProcessName -notmatch '^(powershell|pwsh|cmd|bash|sh|conhost|OpenConsole|WindowsTerminal|python|pythonw|node)$') {
        $agentPid = $pp
        if (-not $agent) { $agent = $pr.ProcessName }
        break
      }
      $cur = $pp
    }
  }
  if ($agentPid -gt 0 -and -not $agent) { try { $agent = (Get-Process -Id $agentPid -ErrorAction Stop).ProcessName } catch { } }
  if (-not $agent) { $agent = '未知' }
  if ($log) { try { [IO.File]::WriteAllText($ptr, $log, (New-Object Text.UTF8Encoding $false)) } catch { } }

  # 同实例去重交给 ya_hud 的互斥量。

  if ([YaEvidence]::Check($pkg, $io, $proof)) { throw '登记前证据已变化或过期；重新挑战。' }
  Write-YaJsonFile $linkPath ([ordered]@{
      version   = 1
      state     = 'ok'
      registered_utc = [DateTime]::UtcNow.ToString('o')
      package_id = $packageId
      session = $proof['session']
      nonce = $proof['nonce']
      process_start = $proof['process_start']
      readback_sha256 = $proof['readback_sha256']
      command_work = $(if (A 'command_work') { A 'command_work' } else { $pending['command_work'] })
      soft      = $soft
      slot      = $resolved.id
      pid       = $softPid
      window    = [YaWindow]::Title($mw)
      agent     = $agent
      agent_pid = $agentPid
      log       = $log
      time      = (Get-Date).ToString('s')
    })

  $hudShown=Show-YaHud
  if(-not $hudShown){Write-Output 'state: 软件通道已核验，YA前台交付未完成；修复显示后无需重新操作软件';Write-Output 'RESULT: FAIL';exit 1}
  Write-Output ('state: 前台通道就绪 · 待任务验收 · ' + $soft)
  Write-Output 'next: 用 连接软件.ps1 -Action Connect -TaskFile 完成实际修改、独立读回及 YA 验收。'
  Write-Output ('soft_window: ' + $proc.MainWindowTitle)
  Write-Output ('slot: ' + $resolved.id + $(if ($slotNote) { '  （' + $slotNote + '）' } else { '' }))
  Write-Output ('exp_folder: ' + $expDirLine)
  Write-Output ('soft_pid: ' + $softPid)
  Write-Output ('agent: ' + $agent + ' pid=' + $agentPid)
  Write-Output ('usage_log: ' + $(if ($log) { $log + '  来源=' + $logFrom } else { '(未统计；需按说明接入真实用量采集器)' }))
  Write-Output 'single_card: 按包路径和 HUD Home 互斥去重'
  Write-Output ('package: ' + $pkg + ' [' + $packageId + ']')
  Write-Output ('link: ' + $linkPath)
  Write-Output 'RESULT: OK'
  exit 0
}
catch {
  Write-Output ('ERROR: ' + $_.Exception.Message)
  Write-Output 'RESULT: FAIL'
  exit 1
}
