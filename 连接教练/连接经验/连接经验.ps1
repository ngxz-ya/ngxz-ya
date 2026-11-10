# 第一步先读 AGENTS.md「第 0 步」。首连一条命令（包根）：.\一键连接.ps1 -Software "<软件名>" -StartDir "<本会话起点目录>"
# 连接经验（跨软件通用）：find 只读查卡 / add 登记候选卡（索引和目录都查重、缺文件的索引行不算重复、必填、禁词、强制整数 v=0）/ list / rebuild（小数 v 不收成 0；卡里或文件名里有禁止词也拒绝整次重建，不写进索引；索引不改）。
# 在本包根目录：
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\连接经验.ps1" find task="连接 NX"
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\连接经验.ps1" find slot=nx
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\连接经验.ps1" add slot=nx file=写好的卡.json
# find / list 不写包内任何文件（命中次数记在包外 %LOCALAPPDATA%\YAHud\io\card_hits.json，YA 卡「经验调用」据此计数）。add / rebuild 只写本目录（连接教练\连接经验\）。不是 ya.ps1 命令，不动经验库账本。
# 命中且卡里有「快通道」：直接跑 快连.ps1 slot=<槽>（一条命令做完 启动→读回→前台→登记→前台复核，并打出各段耗时）。
param([Parameter(Position = 0)][string]$Command = 'help', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$here = $PSScriptRoot
. (Join-Path (Split-Path (Split-Path $here -Parent) -Parent) 'YA插件\连接上下文.ps1') -PathsOnly
Assert-YaIsolatedPackage (Split-Path (Split-Path $here -Parent) -Parent)
$indexPath = Join-Path $here '索引.json'
$enc = New-Object Text.UTF8Encoding $true
$required = @('slot','别名','t','触发条件','适用前提','参数','启动方式','步骤','前台判定','读回','失败处理','证据','未验证','v','核验')

function Test-ConnFastpathComplete($c) {
  $fp = $c.快通道
  if ($null -eq $fp) { return '缺字段: 快通道。卡必须写明从软件未运行状态拉起、桥接自动加载、读回的完整步骤。没有登记。' }
  foreach ($k in @('适配','进程名','读回含','等待秒')) {
    $v = $null; try { $v = $fp.$k } catch { $v = $null }
    if ($null -eq $v -or ([string]$v).Trim() -eq '') { return ('快通道缺字段: ' + $k + '。没有登记。') }
  }
  $cold = $null; try { $cold = $fp.从零 } catch { $cold = $null }
  if ($null -eq $cold) { return '缺字段: 快通道.从零（须含 拉起软件、桥接自动加载、读回：从软件未运行/关机状态拉起软件、桥接自动加载、读回的完整步骤）。没有登记。' }
  foreach ($k in @('拉起软件','桥接自动加载','读回')) {
    $v = $null; try { $v = $cold.$k } catch { $v = $null }
    if ($null -eq $v -or ([string]$v).Trim().Length -lt 8) { return ('快通道.从零 缺完整步骤: ' + $k + '。须写清从软件未运行状态如何拉起、桥接如何自动加载、如何读回。没有登记。') }
  }
  return $null
}

$bad = '破解|注册机|盗版|crack|keygen|patch许可|绕过许可|license\s*key|许可密钥'
function Get-Args([string[]]$a) {
  $m = @{}
  foreach ($x in $a) { if ($x -match '^([^=]+)=(.*)$') { $m[$matches[1].Trim()] = $matches[2].Trim().Trim('"') } }
  return $m
}
function Read-Index {
  if (-not (Test-Path -LiteralPath $indexPath)) { return @() }
  $o = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  return @($o.entries)
}
function Test-ConnStoredV($Value, [bool]$AllowOne) {
  # 小数在 Windows PowerShell 5.1 里是 Decimal。[int]0.4 会收成 0，不能用来判断。
  if ($null -eq $Value) { return $false }
  if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return $false }
  $s = [string]$Value
  if ($s -eq '0') { return $true }
  if ($AllowOne -and $s -eq '1') { return $true }
  return $false
}
function Test-ConnFileOnDisk([string]$Rel) {
  if (-not $Rel) { return $false }
  $pkgRoot = Split-Path (Split-Path $here -Parent) -Parent
  return (Test-Path -LiteralPath (Join-Path $pkgRoot $Rel))
}
function Build-Index {
  $rows = @()
  foreach ($d in (Get-ChildItem -LiteralPath $here -Directory | Sort-Object Name)) {
    foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -Filter '连接卡-*.json' -File | Sort-Object Name)) {
      $rawCard = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
      $relName = $d.Name + '\' + $f.Name
      if (($rawCard -match $bad) -or ($relName -match $bad)) { throw '卡里有禁止写入的词（侵权或不合法连接相关），索引没有改。' }
      $c = $rawCard | ConvertFrom-Json
      foreach ($k in $required) { if ($null -eq $c.$k -or ([string]$c.$k).Trim() -eq '') { throw ('卡缺字段 ' + $k + ': ' + (Show-ConnFileName $f.Name) + '。索引没有改。') } }
      if (-not (Test-ConnStoredV $c.v $true)) { throw ('v 只能是整数 0 或 1，小数不会收成 0: ' + (Show-ConnFileName $f.Name) + '。索引没有改。') }
      $rows += [ordered]@{ id = [string]$c.id; slot = [string]$c.slot; 别名 = @($c.别名); t = [string]$c.t; v = [int]([string]$c.v); 状态 = [string]$c.状态; 启动方式 = ([string]$c.启动方式).Substring(0, [Math]::Min(60, ([string]$c.启动方式).Length)); f = ('连接教练\连接经验\' + $d.Name + '\' + $f.Name) }
    }
  }
  $o = [ordered]@{ 说明 = '连接经验索引（由 连接经验.ps1 rebuild/add 从各槽连接卡重建，不手改）。v=0 候选，v=1 使用者核验过。开源包出厂为空：不预置任何软件连接卡，使用者本人从 0 连通后才在本地长出。'; count = $rows.Count; entries = $rows }
  $tmp = $indexPath + '.tmp'
  [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $o -Depth 5), $enc)
  Move-Item -LiteralPath $tmp -Destination $indexPath -Force
  return $rows.Count
}
function Show-ConnText([string]$Text) {
  $t = [string]$Text
  if ($t -and ($t -match $bad)) { return '没有列出来' }
  return $t
}
function Show-ConnFileName([string]$Name) {
  return (Show-ConnText $Name)
}
function Show-ConnId([string]$Id) { return (Show-ConnText $Id) }
function Get-ConnLead([string]$Text) {
  $t = [string]$Text
  if (-not $t) { return '' }
  $n = [Math]::Min(60, $t.Length)
  return $t.Substring(0, $n)
}
function Find-ConnDup([string]$Slot, [string]$Title, [string]$Lead) {
  foreach ($e in @(Read-Index)) {
    if (([string]$e.slot).ToLower() -ne $Slot) { continue }
    if (-not (Test-ConnFileOnDisk ([string]$e.f))) { continue }
    $have = Get-ConnLead ([string]$e.启动方式)
    if ([string]$e.t -eq $Title -or ($Lead -and $have -eq $Lead)) {
      return ('dup: ' + (Show-ConnId ([string]$e.id)) + ' f=' + (Show-ConnText ([string]$e.f)))
    }
  }
  $dir = Join-Path $here $Slot
  if (-not (Test-Path -LiteralPath $dir)) { return '' }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '连接卡-*.json' -File -ErrorAction SilentlyContinue)) {
    try { $c = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
    $have = Get-ConnLead ([string]$c.启动方式)
    if ([string]$c.t -eq $Title -or ($Lead -and $have -eq $Lead)) {
      $id = [string]$c.id
      if (-not $id) { $id = [IO.Path]::GetFileNameWithoutExtension($f.Name) }
      $rel = '连接教练\连接经验\' + $Slot + '\' + $f.Name
      return ('dup: ' + (Show-ConnId $id) + ' f=' + (Show-ConnText $rel))
    }
  }
  return ''
}
function Test-ConnTask([string]$task) {
  if (-not $task) { return $false }
  if ($task -match '螺栓连接|焊接连接|键连接|销连接|法兰连接|连接件|连接强度|连接板|连杆') { if ($task -notmatch '软件') { return $false } }
  return ($task -match '连接|连上|接上|接通|打开|启动|连一下|帮我连|^连')
}
function Add-CardHit([string]$id, [string]$how) {
  # 包外计数：不改包内文件（测试包零改照样成立）
  try {
    $pkg = Split-Path (Split-Path $here -Parent) -Parent
    . (Join-Path $pkg 'YA插件\连接上下文.ps1')
    $h = Get-YaPackageHudHome $pkg
    $io = Join-Path $h 'io'; if (-not (Test-Path -LiteralPath $io)) { New-Item -ItemType Directory -Path $io -Force | Out-Null }
    $p = Join-Path $io 'card_hits.json'
    $ap = 0; $an = ''; $cur = $PID
    for ($k = 0; $k -lt 12; $k++) {
      $row = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $cur) -ErrorAction SilentlyContinue
      if (-not $row -or -not $row.ParentProcessId) { break }
      $pp = [int]$row.ParentProcessId; $pr = Get-Process -Id $pp -ErrorAction SilentlyContinue
      if (-not $pr) { break }
      if ($pr.ProcessName -match '^(WmiPrvSE|svchost|services|wininit|winlogon|explorer|taskeng|taskhostw)$') { break }
      if ($pr.ProcessName -notmatch '^(powershell|pwsh|cmd|bash|sh|conhost|OpenConsole|WindowsTerminal|python|pythonw|node)$') { $ap = $pp; $an = $pr.ProcessName; break }
      $cur = $pp
    }
    $log = @()
    if (Test-Path -LiteralPath $p) { try { $o = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json; $log = @($o.log) } catch { } }
    $t = [Math]::Round(((Get-Date).ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds, 1)
    $log = @($log | Select-Object -Last 499) + @([ordered]@{ t = $t; time = (Get-Date).ToString('s'); id = $id; how = $how; agent = $an; agent_pid = $ap })
    $doc = [ordered]@{ '说明' = '连接卡命中记录（包外；连接经验.ps1 find / 快连.ps1 写）。YA 卡把同一 Agent 的命中计入「经验调用」。'; total = $log.Count; log = $log }
    [IO.File]::WriteAllText($p, (ConvertTo-Json -InputObject $doc -Depth 5), (New-Object Text.UTF8Encoding $false))
  } catch { }
}
$a = Get-Args $Rest
try {
  switch ($Command) {
    'find' {
      $task = [string]$a['task']; $slot = ([string]$a['slot']).ToLower(); $q = [string]$a['q']
      if (-not $task -and -not $slot -and -not $q) { throw 'find 要写 task= 或 slot= 或 q=' }
      $entries = Read-Index
      $isConn = Test-ConnTask $task
      $hits = @()
      foreach ($e in $entries) {
        $hit = $false
        if ($slot -and ([string]$e.slot).ToLower() -eq $slot) { $hit = $true }
        if ($task) { foreach ($al in (@($e.别名) + @([string]$e.slot))) { if ($al -and $task.ToLower().Contains(([string]$al).ToLower())) { $hit = $true } } }
        if ($q -and (([string]$e.t + ' ' + [string]$e.启动方式 + ' ' + (@($e.别名) -join ' ')).ToLower().Contains($q.ToLower()))) { $hit = $true }
        if ($hit) { $hits += $e }
      }
      if ($task) { Write-Output ('task: ' + $task); Write-Output ('conn_task: ' + $(if ($isConn) { 'yes' } else { 'no' })) }
      if ($slot) { Write-Output ('slot: ' + (Show-ConnId $slot)) }
      Write-Output ('hits: ' + $hits.Count)
      foreach ($e in $hits) {
        Write-Output ('- slot=' + (Show-ConnId ([string]$e.slot)) + ' id=' + (Show-ConnId ([string]$e.id)) + ' v=' + $e.v + ' 状态=' + (Show-ConnText ([string]$e.状态)) + ' t=' + (Show-ConnText ([string]$e.t)))
        Write-Output ('  f: ' + (Show-ConnText ([string]$e.f)))
        Write-Output ('  also: ya.ps1 exp_recall q=连接 slot=' + (Show-ConnId ([string]$e.slot)) + ' tag=连接')
        $fast = $false
        try { $cardFile = Join-Path (Split-Path (Split-Path $here -Parent) -Parent) ([string]$e.f); $cj = [IO.File]::ReadAllText($cardFile, [Text.Encoding]::UTF8) | ConvertFrom-Json; if ($cj.快通道 -and $cj.快通道.适配) { $fast = $true } } catch { }
        if ($fast) { Write-Output ('  fast: powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\快连.ps1" slot=' + (Show-ConnId ([string]$e.slot)) + '   ← 一条命令照卡连，先跑这个') }
        Add-CardHit ([string]$e.id) 'find'
      }
      if ($hits.Count -gt 0) {
        Write-Output 'next: 有 fast: 行就直接跑那条（快连.ps1），看最后 RESULT；没有才只读那张卡照「步骤」做。核「适用前提」，参数不同只改参数（快连.ps1 key=值 覆盖），不重新摸索、不先上网。v=0 也要看前台复核和读回。'
      } else {
        Write-Output 'next: 本软件没有本机连接卡（首连）。按 一键连接.ps1 打印的 NEED_AGENT_METHOD 步骤上网找合法官方/开源接口并审查来源，测通后用 add 存卡；不读取本包以外的任何旧卡或旧项目。'
      }
      Write-Output 'RESULT: OK'
    }
    'hit' {
      # 只记一次命中（包外），给 快连.ps1 用；不写包内文件
      Add-CardHit ([string]$a['id']) ([string]$a['how'])
      Write-Output 'RESULT: OK'
    }
    'list' {
      $entries = Read-Index
      Write-Output ('count: ' + $entries.Count)
      foreach ($e in $entries) { Write-Output ('- slot=' + (Show-ConnId ([string]$e.slot)) + ' id=' + (Show-ConnId ([string]$e.id)) + ' v=' + $e.v + ' t=' + (Show-ConnText ([string]$e.t))) }
      Write-Output 'RESULT: OK'
    }
    'rebuild' {
      $n = Build-Index
      Write-Output ('count: ' + $n)
      Write-Output 'RESULT: OK'
    }
    'add' {
      $slot = ([string]$a['slot']).ToLower(); $file = [string]$a['file']
      if ($slot -notmatch '^[a-z][a-z0-9_-]{0,31}$' -or $slot -eq 'all' -or $slot -eq 'generic') { throw 'slot= 要写具体软件槽（小写英文），不能是 all 或 generic' }
      if (-not $file -or -not (Test-Path -LiteralPath $file)) { throw ('找不到 file=: ' + $file) }
      $raw = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $file).Path, [Text.Encoding]::UTF8)
      if ($raw -match $bad) { throw '卡里有禁止写入的词（侵权或不合法连接相关），没有登记。' }
      $c = $raw | ConvertFrom-Json
      foreach ($k in $required) { if ($null -eq $c.$k -or ([string]$c.$k).Trim() -eq '') { throw ('缺字段: ' + $k + '。模板见 说明.md 第三节。没有登记。') } }
      if (-not (Test-ConnStoredV $c.v $false)) { throw 'add 只收候选 v=0。v=1 只能在关闭软件后用本卡从零跑快通道通过时由快连写入，不能在 add 或首连握手后手改。没有登记。' }
      $fpErr = Test-ConnFastpathComplete $c; if ($fpErr) { throw $fpErr }
      $c.v = 0
      if (([string]$c.slot).ToLower() -ne $slot) { throw ('卡里 slot=' + (Show-ConnId ([string]$c.slot)) + ' 和参数 slot=' + (Show-ConnId $slot) + ' 不一致，没有登记。') }
      $lead = Get-ConnLead ([string]$c.启动方式)
      $dup = Find-ConnDup $slot ([string]$c.t) $lead
      if ($dup) {
        Write-Output $dup
        throw '同槽已有同一启动方式的连接卡。请在原卡补适用前提、失败处理或证据，不另起一张。'
      }
      $dir = Join-Path $here $slot
      if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
      $n = 1
      while (Test-Path -LiteralPath (Join-Path $dir ('连接卡-' + $slot + '-' + $n.ToString('000') + '.json'))) { $n++ }
      $id = '连接卡-' + $slot + '-' + $n.ToString('000')
      $c | Add-Member -NotePropertyName id -NotePropertyValue $id -Force
      if (-not $c.状态) { $c | Add-Member -NotePropertyName 状态 -NotePropertyValue '候选' -Force }
      $dst = Join-Path $dir ($id + '.json')
      [IO.File]::WriteAllText($dst, (ConvertTo-Json -InputObject $c -Depth 6), $enc)
      try { $cnt = Build-Index } catch { Remove-Item -LiteralPath $dst -Force; throw }
      Write-Output ('added: ' + $id)
      Write-Output ('f: 连接教练\连接经验\' + $slot + '\' + $id + '.json')
      Write-Output 'v: 0（候选。关闭软件后用本卡从零跑 快连.ps1 通过才标 v=1；首连握手/轻读回不算完成）'
      Write-Output ('count: ' + $cnt)
      Write-Output ('next: 再在软件槽写一条短草稿：ya.ps1 exp_recall q=连接 slot=' + $slot + ' tag=连接，然后 exp_done c=招式 tag=连接 slot=' + $slot + ' t=一句话（详卡见 连接教练\连接经验\' + $slot + '\）')
      Write-Output 'RESULT: OK'
    }
    default {
      Write-Output 'find task="连接 NX" | find slot=nx | find q=WMI | list | add slot=nx file=卡.json | rebuild'
      Write-Output 'RESULT: OK'
    }
  }
} catch {
  Write-Output ('error: ' + $_.Exception.Message)
  Write-Output 'RESULT: FAIL'
  exit 1
}
