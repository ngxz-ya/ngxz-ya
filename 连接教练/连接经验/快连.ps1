# 第一步先读 AGENTS.md「第 0 步」。首连一条命令（包根）：.\一键连接.ps1 -Software "<软件名>" -StartDir "<本会话起点目录>"
# 快连（跨软件通用快通道）：按连接卡一条命令做完「脱离 Agent 启动 → 软件进程内读回本次随机数 → 前台 → ya_link 登记 → 再把软件拉回前台复核」，并打出各段耗时。
# 在本包根目录：
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\快连.ps1" slot=nx
#   自检不启动、不探测：加上 check=1。只核对卡和适配脚本在不在，不跑适配，不发起 WMI。
#   可选：card=连接卡-<槽>-001  wait=180（等读回秒数；默认约100，大型软件冷启动可加大，不削弱读回核验）  log=Agent输出日志  existing=stop|new  键=值（覆盖卡里「参数」，如 NX_UGII=D:\...\UGII）
# 软件相关的只有「适配脚本」（卡里 快通道.适配，如 <槽>\快通道.ps1，开源包不预置，由本人连通后自写）：它准备启动命令行、工作目录、读回文件和合法实时 Probe。其余全部通用。
# 硬规矩：不按键、不点鼠标；不按进程名杀任何进程（失败也只报本次新起的进程号，由人决定）；已有使用者的软件窗口开着 → 默认不另起（existing=stop）。
# 不写包内任何文件：运行文件在 %LOCALAPPDATA%\YALink\work\<槽>\，连接记录在 %LOCALAPPDATA%\YALink\连接记录\，卡命中计数在 YAHud\io\card_hits.json。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$t0 = Get-Date
$marks = [ordered]@{}
function Mark([string]$k) { $s = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1); $marks[$k] = $s; Write-Output ('[' + ('{0,6:N1}' -f $s) + 's] ' + $k) }
$here = $PSScriptRoot
$pkg = Split-Path (Split-Path $here -Parent) -Parent
. (Join-Path $pkg 'YA插件\连接上下文.ps1') -PathsOnly
Assert-YaIsolatedPackage $pkg
$a = @{}
foreach ($x in @($Rest)) { if ($x -match '^([^=]+)=(.*)$') { $a[$matches[1].Trim()] = $matches[2].Trim().Trim('"') } }
function A([string]$n) { if ($a.ContainsKey($n)) { return [string]$a[$n] } return '' }
function Show-Id([string]$Id) {
  $t = [string]$Id
  if ($t -match '(?i)破解|注册机|盗版|keygen|\bcrack\b') { return '没有列出来' }
  return $t
}
$stage = '查卡'
$newPid = 0
try {
  $slot = (A 'slot').ToLower()
  if (-not $slot) { throw '要写 slot=<槽>（先跑 连接经验.ps1 find task="原话" 看命中哪个槽）' }
  $idx = [IO.File]::ReadAllText((Join-Path $here '索引.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
  $rows = @($idx.entries | Where-Object { ([string]$_.slot).ToLower() -eq $slot })
  if ((A 'card')) { $rows = @($rows | Where-Object { [string]$_.id -eq (A 'card') }) }
  if ($rows.Count -eq 0) { throw ('槽 ' + (Show-Id $slot) + ' 没有连接卡：这是首连，按 说明.md「首连五步」做，连上后写卡 add。') }
  $row = @($rows | Sort-Object { -[int]$_.v })[0]
  $cardPath = Join-Path $pkg ([string]$row.f)
  $card = [IO.File]::ReadAllText($cardPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  if ((A 'check') -eq '1') {
    Write-Output 'check: yes'
    Write-Output ('card: ' + (Show-Id ([string]$card.id)) + ' v=' + $card.v + ' slot=' + (Show-Id $slot))
    $fastNow = $card.快通道
    if ($fastNow -and [string]$fastNow.适配) {
      $adapterNow = Join-Path (Split-Path $cardPath -Parent) ([string]$fastNow.适配)
      $adapterName = [IO.Path]::GetFileName([string]$fastNow.适配)
      if (-not (Test-Path -LiteralPath $adapterNow)) { throw ('缺适配脚本: ' + (Show-Id $adapterName)) }
      Write-Output ('adapter: ' + $adapterName)
    } else {
      Write-Output 'adapter: none'
    }
    Write-Output 'launch: no'
    Write-Output 'note: 这只是快通道自检，没有启动软件，也没有探测它在不在。'
    Write-Output 'RESULT: OK'
    exit 0
  }
  $fast = $card.快通道
  if (-not $fast -or -not $fast.适配) { throw ('卡 ' + $card.id + ' 没有「快通道」：只读这张卡照「步骤」手做。') }
  $adapter = Join-Path (Split-Path $cardPath -Parent) ([string]$fast.适配)
  if (-not (Test-Path -LiteralPath $adapter)) { throw ('缺适配脚本: ' + $adapter) }
  $procName = [string]$fast.进程名
  $soft = [string]$fast.soft; if (-not $soft) { $soft = $slot }
  $titleRx = [string]$fast.窗口标题; if (-not $titleRx) { $titleRx = '.' }
  $errRx = [string]$fast.错误标题; if (-not $errRx) { $errRx = '^(Error|错误|错误信息)' }
  $need = @($fast.读回含); if ($need.Count -eq 0) { $need = @('SESSION_OK') }
  $wait = 100; if ((A 'wait') -match '^\d+$') { $wait = [int](A 'wait') } elseif ([string]$fast.等待秒 -match '^\d+$') { $wait = [int]$fast.等待秒 }
  if($wait -lt 1 -or $wait -gt 1800){throw 'wait must be between 1 and 1800 seconds'}
  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  . (Join-Path $pkg 'YA插件\真实记录.ps1')
  . (Join-Path $pkg '适配器\受控连接.ps1')
  Assert-YaPowerShellFile $adapter
  if(A '_worker'){Initialize-YaQuickWorker (A '_worker')}else{
    $workerExit=Invoke-YaQuickWorker -Script $PSCommandPath -Arguments $Rest -WaitSeconds $wait
    exit $workerExit
  }
  Write-Output ('card: ' + $card.id + ' v=' + $card.v + ' slot=' + $slot + ' soft=' + $soft)

  # 卡命中计数（包外）
  try { & (Join-Path $here '连接经验.ps1') hit id=$($card.id) how=快连 | Out-Null } catch { }

  # Agent 和 TOKEN 日志：在 Agent 自己的进程链里取（后面经 WMI 转调时会断链，所以这里先取好显式传下去）
  $agentPid = 0; $agent = ''
  $cur = $PID
  for ($k = 0; $k -lt 12; $k++) {
    $r = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $cur) -ErrorAction SilentlyContinue
    if (-not $r -or -not $r.ParentProcessId) { break }
    $pp = [int]$r.ParentProcessId; $pr = Get-Process -Id $pp -ErrorAction SilentlyContinue
    if (-not $pr) { break }
    if ($pr.ProcessName -match '^(WmiPrvSE|svchost|services|wininit|winlogon|explorer|taskeng|taskhostw)$') { break }
    if ($pr.ProcessName -notmatch '^(powershell|pwsh|cmd|bash|sh|conhost|OpenConsole|WindowsTerminal|python|pythonw|node)$') { $agentPid = $pp; $agent = $pr.ProcessName; break }
    $cur = $pp
  }
  if ((A 'agent')) { $agent = A 'agent' }
  $log = A 'log'; if (-not $log) { $log = [string]$env:YALINK_USAGE_LOG }; if ($log) { $log = $log.Split(';')[0].Trim() }
  Write-Output ('agent: ' + $(if ($agent) { $agent } else { '未知' }) + ' pid=' + $agentPid + '  usage_log: ' + $(if ($log) { $log } else { '(没挂)' }))

  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  $existingIo=Join-Path (Get-YaPackageHudHome $pkg) 'io'
  $registered=$null
  try { $registered=[YaEvidence]::Read((Join-Path $existingIo 'link.json')) } catch { }
  if ($registered -and $registered['slot'] -ceq $slot -and -not [YaEvidence]::CheckRegistered($pkg,$existingIo,$registered) -and [YaWindow]::Ready([int]$registered['pid'])) {
    Write-Output ('state: 已有本包登记会话，保持当前进程 pid=' + $registered['pid'])
    Write-Output 'next: 用 连接软件.ps1 -Action Connect -TaskFile 验收当前会话；已有登记仅表明通道可核验。'
    Write-Output 'RESULT: ALREADY_REGISTERED'
    exit 0
  }
  $work = Join-Path ([YaEvidence]::Work($pkg, $slot)) ([guid]::NewGuid().ToString('N'))
  if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }

  # 参数：卡里「参数」默认值，被命令行 键=值 覆盖
  $params = @{}
  if ($card.参数) { foreach ($p in $card.参数.PSObject.Properties) { $params[$p.Name] = ([string]$p.Value -split '（')[0].Trim() } }
  foreach ($k in $a.Keys) { if ($k -notin @('slot','card','wait','log','agent','existing','_worker')) { $params[$k] = $a[$k] } }

  Add-Type -Namespace YaFast -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);' -ErrorAction SilentlyContinue

  # 已有软件窗口：默认不另起，不重启、不杀使用者的会话
  $stage = '查已开会话'
  $before = @{}
  if ($procName) { foreach ($p in @(Get-Process -Name $procName -ErrorAction SilentlyContinue)) { $before[[int]$p.Id] = $true } }
  $vis = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { [YaWindow]::Find($_.Id) -ne [IntPtr]::Zero })
  if ($vis.Count -gt 0 -and (A 'existing') -ne 'new') {
    Write-Output ('busy: 已有 ' + $soft + ' 窗口开着 pid=' + (($vis | ForEach-Object { $_.Id }) -join ',') + '。快通道只连新起的会话：不重启、不杀这个会话。要连它请按卡里「已开会话」办法或举手；确认可以另起一个就加 existing=new。')
    Write-Output 'RESULT: BUSY'
    exit 3
  }

  # 适配准备及实时 Probe（不自动生成软件成功证据）
  $stage = '适配准备'
  Set-YaQuickStage 'adapter' $work
  $nonce = [guid]::NewGuid().ToString('N')
  $aout = @(& $adapter -Work $work -Nonce $nonce -Params $params)
  $aout | Where-Object { $_ -isnot [hashtable] } | ForEach-Object { Write-Output ('  ' + $_) }
  $prep = @($aout | Where-Object { $_ -is [hashtable] })[-1]
  if (-not $prep -or -not $prep.CommandLine) { throw '适配脚本没给出 CommandLine' }
  if ($prep.Probe -isnot [scriptblock]) { throw '适配须返回 Probe 脚本块，经合法通道让运行中的软件回应 challenge；旧适配需复核升级。' }
  $rb = [string]$prep.Readback
  if ($rb -and (Test-Path -LiteralPath $rb)) { Remove-Item -LiteralPath $rb -Force }
  Mark '适配就绪（编译/写启动文件）'

  # 脱离 Agent 启动：WMI Win32_Process.Create，父进程不是 Agent 的命令，命令结束软件不会被带走
  $stage = 'WMI 启动'
  Set-YaQuickStage 'launch' $work
  $cim = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = [string]$prep.CommandLine; CurrentDirectory = [string]$prep.CurrentDirectory }
  if ([int]$cim.ReturnValue -ne 0) { throw ('WMI 启动失败 ReturnValue=' + $cim.ReturnValue) }
  Mark 'WMI 已发起启动'

  # 等新进程 + 读回本次随机数
  $stage = '等读回'
  Set-YaQuickStage 'startup' $work
  $deadline = (Get-Date).AddSeconds($wait); $ok = $false; $seenProc = $false; $txt = ''
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1000
    $new = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { -not $before.ContainsKey([int]$_.Id) })
    if ($new.Count -gt 0 -and -not $seenProc) { $seenProc = $true; $newPid = [int]$new[0].Id; Mark ('新进程出现 pid=' + $newPid) }
    $errWin = ''
    foreach ($p in $new) { $tt = ''; try { $p.Refresh(); $tt = [YaWindow]::Title([YaWindow]::Find($p.Id)) } catch { }; if ($tt -match $errRx) { $newPid = [int]$p.Id; $errWin = $tt } }
    if ($errWin) { throw ('软件弹错误窗「' + $errWin + '」pid=' + $newPid + '：按卡「失败处理」查（中文路径/许可/库没加载）。不按键，本次新进程号由人决定关不关。') }
    if ($rb -and (Test-Path -LiteralPath $rb)) {
      try { $txt = [IO.File]::ReadAllText($rb, [Text.Encoding]::UTF8) } catch { $txt = '' }
      $all = $txt.Contains($nonce); foreach ($n in $need) { if (-not $txt.Contains([string]$n)) { $all = $false } }
      $m = [regex]::Match($txt, '(?m)^PID\s+(\d+)')
      if ($all -and $m.Success) { $newPid = [int]$m.Groups[1].Value; $ok = $true; break }
    }
  }
  if (-not $ok) { throw ('等 ' + $wait + ' 秒没读回本次随机数' + $(if ($seenProc) { '（进程起来了 pid=' + $newPid + '）' } else { '（进程都没起来）' }) + '：按卡「失败处理」。') }
  Mark ('读回 OK（随机数+' + ($need -join '+') + '）pid=' + $newPid)

  # 等主窗口可见且标题对上，再确认进程没中途退出
  $stage = '等主窗口'
  Set-YaQuickStage 'window' $work $newPid
  $deadline = (Get-Date).AddSeconds([Math]::Max(30, $wait)); $proc = $null; $windowReady = $false
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Id $newPid -ErrorAction SilentlyContinue
    if (-not $proc) { throw ('进程 ' + $newPid + ' 读回后退出了：多半随 Agent 命令被带走或加载失败，看卡「失败处理」。') }
    $proc.Refresh()
    if ([YaWindow]::Title([YaWindow]::Find($newPid)) -match $errRx) { throw ('软件弹错误窗「' + $proc.MainWindowTitle + '」pid=' + $newPid) }
    if ([YaWindow]::Ready($newPid) -and [YaWindow]::Title([YaWindow]::Find($newPid)) -match $titleRx) { $windowReady = $true; break }
    Start-Sleep -Milliseconds 800
  }
  if (-not $windowReady) { throw 'WINDOW_NOT_READY: 等待超时，未确认目标窗口可见、响应且标题匹配；保留进程，不登记。' }
  Start-Sleep -Seconds 3
  if (-not (Get-Process -Id $newPid -ErrorAction SilentlyContinue)) { throw ('进程 ' + $newPid + ' 出窗后退出了') }
  Mark ('主窗口可见「' + [YaWindow]::Title([YaWindow]::Find($newPid)) + '」')

  # 新鲜挑战必须由仍运行的软件通道回应；不把旧启动文本包装成成功 JSON。
  $stage = '软件挑战读回'
  $linkPs = Join-Path $pkg 'YA插件\ya_link.ps1'
  $prepareStarted = [DateTime]::UtcNow
  $prepareOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $linkPs prepare=1 ('soft=' + $soft) ('slot=' + $slot) ('pid=' + $newPid) | Out-String)
  if ($LASTEXITCODE -ne 2) { throw ('挑战准备失败：' + $prepareOut) }
  $challenge = [YaEvidence]::Read((Join-Path (Join-Path (Get-YaPackageHudHome $pkg) 'io') 'challenge.json'))
  if ([string]$challenge['session'] -cnotmatch '^[a-f0-9]{32}$' -or $challenge['package_id'] -cne [YaEvidence]::Identity($pkg) -or $challenge['slot'] -cne $slot -or [string]$challenge['pid'] -cne [string]$newPid -or $challenge['process_start'] -cne $proc.StartTime.ToUniversalTime().Ticks.ToString() -or [DateTime]::Parse([string]$challenge['issued_utc']).ToUniversalTime() -lt $prepareStarted) { throw '本次挑战身份或时间不匹配，禁止借用旧文件' }
  $challengePath = Join-Path ([YaEvidence]::Work($pkg,$slot)) ($challenge['session']+'\challenge.json')
  if (-not (Test-Path -LiteralPath $challengePath)) { throw '本次挑战文件缺失' }
  Set-YaQuickStage 'probe' $work $newPid
  & $prep.Probe $challengePath | Out-Null
  Set-YaQuickStage 'proof' $work $newPid
  $proofFile = Join-Path (Split-Path $challengePath -Parent) 'readback.json'
  $proofDeadline = (Get-Date).AddSeconds([Math]::Max(30, $wait))
  while (-not (Test-Path -LiteralPath $proofFile) -and (Get-Date) -lt $proofDeadline) { Start-Sleep -Milliseconds 400 }
  if (-not (Test-Path -LiteralPath $proofFile)) { throw 'SOFTWARE_READBACK_MISSING: 保留本次软件进程与证据，不自动重试' }

  # 前台 + 登记 + 再拉回前台复核：经 WMI 在使用者桌面上跑（Agent 自己的会话可能拿不到前台）。不按键、不点鼠标。
  $stage = '前台与登记'
  Set-YaQuickStage 'registration' $work $newPid
  $fgOut = Join-Path $work '_ya_fg_link.out.txt'
  if (Test-Path -LiteralPath $fgOut) { Remove-Item -LiteralPath $fgOut -Force }
  $helper = Join-Path $work '_ya_fg_link.ps1'
  $linkPs = Join-Path $pkg 'YA插件\ya_link.ps1'
  $h = @'
param([int]$TargetPid, [string]$LinkPs, [string]$Soft, [string]$Slot, [string]$Log, [string]$Agent, [int]$AgentPid, [string]$Out, [string]$CommandWork,[string]$QuickWorkerRequest)
$ErrorActionPreference = 'Continue'
if($QuickWorkerRequest){if($QuickWorkerRequest -cnotmatch '^[a-f0-9]{32}$'){throw 'INVALID_QUICK_WORKER_REQUEST'};$env:YALINK_QUICK_WORKER=$QuickWorkerRequest}
try{[Console]::OutputEncoding=[Text.Encoding]::UTF8}catch{}
Add-Type -Namespace YaFg -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
"@
function FgPid { $p = 0; [void][YaFg.U]::GetWindowThreadProcessId([YaFg.U]::GetForegroundWindow(), [ref]$p); return [int]$p }
function Front([int]$id) {
  $pr = Get-Process -Id $id -ErrorAction SilentlyContinue; if (-not $pr) { return 0 }
  $w = $pr.MainWindowHandle; if ($w -eq [IntPtr]::Zero) { return 0 }
  for ($i = 0; $i -lt 4; $i++) {
    if ((FgPid) -eq $id) { break }
    if ([YaFg.U]::IsIconic($w)) { [void][YaFg.U]::ShowWindow($w, 9) }
    $fp = 0; $ft = [YaFg.U]::GetWindowThreadProcessId([YaFg.U]::GetForegroundWindow(), [ref]$fp); $me = [YaFg.U]::GetCurrentThreadId()
    [void][YaFg.U]::AttachThreadInput($me, $ft, $true); [void][YaFg.U]::BringWindowToTop($w); [void][YaFg.U]::SetForegroundWindow($w); [void][YaFg.U]::AttachThreadInput($me, $ft, $false)
    Start-Sleep -Milliseconds 400
    if ((FgPid) -ne $id -and $i -ge 1) { [void][YaFg.U]::ShowWindow($w, 6); Start-Sleep -Milliseconds 250; [void][YaFg.U]::ShowWindow($w, 9); Start-Sleep -Milliseconds 400 }
  }
  return (FgPid)
}
$r = [ordered]@{}
$r.fg_before = Front $TargetPid
$args2 = @(('soft=' + $Soft), ('pid=' + $TargetPid), ('slot=' + $Slot), ('command_work=' + $CommandWork), ('agent=' + $Agent), ('agent_pid=' + $AgentPid))
if ($Log) { $args2 += ('log=' + $Log) }
$r.link = (& powershell -NoProfile -ExecutionPolicy Bypass -File $LinkPs @args2 2>&1 | Out-String)
Start-Sleep -Milliseconds 2500
$r.fg_after_link = FgPid
$r.fg_final = Front $TargetPid
Start-Sleep -Milliseconds 800
$r.fg_check = FgPid
$pr = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
$r.title = if ($pr) { $pr.MainWindowTitle } else { '' }
$r.alive = [bool]$pr
[IO.File]::WriteAllText($Out, (ConvertTo-Json -InputObject $r), (New-Object Text.UTF8Encoding $true))
'@
  [IO.File]::WriteAllText($helper, $h, (New-Object Text.UTF8Encoding $true))
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ' + (& $q $helper) + ' -TargetPid ' + $newPid + ' -LinkPs ' + (& $q $linkPs) + ' -Soft ' + (& $q $soft) + ' -Slot ' + (& $q $slot) + ' -Log ' + (& $q $log) + ' -Agent ' + (& $q $agent) + ' -AgentPid ' + $agentPid + ' -CommandWork ' + (& $q $work) + ' -Out ' + (& $q $fgOut) + '"'
  if($env:YALINK_QUICK_WORKER){$cmd=$cmd.Substring(0,$cmd.Length-1)+' -QuickWorkerRequest '+(& $q $env:YALINK_QUICK_WORKER)+'"'}
  $cim2 = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $pkg }
  if ([int]$cim2.ReturnValue -ne 0) { throw ('WMI 跑前台/登记助手失败 ReturnValue=' + $cim2.ReturnValue) }
  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $fgOut)) { Start-Sleep -Milliseconds 500 }
  if (-not (Test-Path -LiteralPath $fgOut)) { throw '前台/登记助手 45 秒没出结果' }
  Start-Sleep -Milliseconds 300
  $fr = [IO.File]::ReadAllText($fgOut, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $linkOk = ([string]$fr.link) -match 'RESULT: OK'
  Mark ('ya_link ' + $(if ($linkOk) { 'OK' } else { 'FAIL' }))
  Write-Output ('ya_link:')
  (([string]$fr.link) -split "`r?`n") | Where-Object { $_ -match '^(state|hud|agent|usage_log|single_card|ERROR|RESULT)' } | ForEach-Object { Write-Output ('  ' + $_) }
  $fgOk = [int]$fr.fg_check -eq $newPid
  Write-Output ('foreground: 登记前=' + $fr.fg_before + ' 登记后=' + $fr.fg_after_link + ' 复核=' + $fr.fg_check + ' 目标=' + $newPid + ' → ' + $(if ($fgOk) { '前台复核通过' } else { '前台复核没过（软件只是可见，前台是别的窗口）' }))
  Mark '前台复核'

  $okAll = $linkOk -and $fgOk -and [bool]$fr.alive
  # 连接记录（包外）：可作为连接卡的通道核验依据。
  $recDir = Join-Path ([YaEvidence]::Work($pkg, $slot)) 'records'
  if (-not (Test-Path -LiteralPath $recDir)) { New-Item -ItemType Directory -Path $recDir -Force | Out-Null }
  $rec = [ordered]@{ time = $t0.ToString('s'); slot = $slot; card = [string]$card.id; card_v = [int]$card.v; soft = $soft; pid = $newPid; nonce = $nonce; ok = $okAll; fg_check = [int]$fr.fg_check; title = [string]$fr.title; agent = $agent; agent_pid = $agentPid; usage_log = $log; params = $params; marks = $marks; readback = $txt; package = $pkg }
  $recPath = Join-Path $recDir ($slot + '_' + $t0.ToString('yyyyMMdd_HHmmss') + '.json')
  [IO.File]::WriteAllText($recPath, (ConvertTo-Json -InputObject $rec -Depth 5), (New-Object Text.UTF8Encoding $true))
  Write-Output ('record: ' + $recPath)
  Write-Output ('timing: ' + (($marks.Keys | ForEach-Object { $_ + '=' + $marks[$_] + 's' }) -join ' | '))
  Write-Output ('total_seconds: ' + [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1))
  if ($okAll) {
    Write-Output ('state: 前台通道就绪 · 待任务验收 · ' + $soft + '（pid=' + $newPid + '）')
    Write-Output 'next: 用 连接软件.ps1 -Action Connect -TaskFile 完成同窗口实际修改和独立读回。'
    Write-Output 'RESULT: OK'; exit 0
  } else {
    Write-Output ('state: 未达标（' + $(if (-not $linkOk) { 'ya_link 没 OK' } else { '前台复核没过' }) + '）。不要说已连上。软件 pid=' + $newPid + ' 仍开着，不杀。')
    Write-Output 'RESULT: FAIL'; exit 1
  }
}
catch {
  Write-Output ('error: [' + $stage + '] ' + $_.Exception.Message)
  if ($newPid -gt 0) { Write-Output ('note: 保留本次软件进程 pid=' + $newPid + ' 和模型、日志；不要自动结束、重启或重发。确需重启先核对保存并取得用户明确同意。') }
  Write-Output ('timing: ' + (($marks.Keys | ForEach-Object { $_ + '=' + $marks[$_] + 's' }) -join ' | '))
  Write-Output 'RESULT: FAIL'
  exit 1
}
