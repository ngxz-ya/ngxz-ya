# ngxz-ya FreeCAD 命令行：给前台 FreeCAD 发一条命令，等它执行完，打印实读结果（JSON）。
# 例：
#   fc.ps1 wait                               等连接就绪（打印 CONNECTED）
#   fc.ps1 status                             文档、对象、实读尺寸
#   fc.ps1 box L=100 W=50 H=30                建方块（at=x,y,z 可选）
#   fc.ps1 set obj=Box prop=Height value=60   改尺寸（参数化，不删重建）
#   fc.ps1 cyl D=19 H=1.5                     建圆柱（at= dir= 可选）
#   fc.ps1 hole D=10 x=40 y=40                通孔（depth= 为盲孔；obj= 指定对象）
#   fc.ps1 chamfer size=1 edges=top           倒角；edges=top|bottom|vertical|outer|inner|circle|all|3,5,7，可用 + 连接
#   fc.ps1 fillet size=2 edges=vertical       倒圆
#   fc.ps1 measure bbox=100,50,60 faces=6     实读并核对（tol= 默认 0.01）
#   fc.ps1 dim n=1 p1=0,0,0 p2=100,0,0 at=50,-15,0    模型上标线性尺寸，文字 数值 (1)
#   fc.ps1 dim n=2 kind=dia obj=Cut edge=3 at=0,25,0  标直径（实读圆棱）
#   fc.ps1 py 脚本.py D=19                    在前台 FreeCAD 里跑 Python（result 字典回传）
#   fc.ps1 undo | clear | new | view to=iso | save path=x.FCStd | step path=x.step | shot path=x.png
#   fc.ps1 exp_search q=方块                  先搜经验（短词，一次一个）
#   fc.ps1 exp_get id=F001 | exp_done id=F001,G001 | exp_save file=卡.json | exp_list
param([Parameter(Position = 0)][string]$Command = 'status', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
function Find-Root([string]$d) { while ($d) { if (Test-Path -LiteralPath (Join-Path $d 'AGENTS.md')) { return $d }; $d = Split-Path $d -Parent }; return $null }
$Root = Find-Root $PSScriptRoot
if (-not $Root) { $Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
$Run = Join-Path $Root '运行数据'
$Scratch = Join-Path $Run '临时'; if (-not (Test-Path -LiteralPath $Scratch)) { New-Item -ItemType Directory -Force -Path $Scratch | Out-Null }
$Io = Join-Path $Run 'FreeCAD'
$SoftExp = Join-Path (Split-Path $PSScriptRoot -Parent) '经验'
$GenExp = Join-Path $Root '通用经验'
$Utf8 = New-Object Text.UTF8Encoding($false)

function Read-Json([string]$p) { if (Test-Path -LiteralPath $p) { return ([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json) }; return $null }
function Write-Text([string]$p, [string]$t) { $d = Split-Path $p -Parent; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; [IO.File]::WriteAllText($p, $t, $Utf8) }
function Conv([string]$v) {
  $d = 0.0
  if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  if ($v -eq 'true') { return $true }; if ($v -eq 'false') { return $false }
  return $v
}

# ---------------- 参数
$A = @{}
if ($Command -eq 'py' -and $Rest.Count -and $Rest[0] -notmatch '^\w+=') {
  $A.code = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Rest[0]).Path, [Text.Encoding]::UTF8); $Rest = @($Rest | Select-Object -Skip 1)
}
$Keep = @('obj', 'prop', 'name', 'path', 'code', 'edges', 'q', 'id', 'file', 'kind', 'to', 'p1', 'p2', 'at', 'dir', 'bbox', 'n', 'sw', 't', 'k', 'task', 'do', 'pit', 'api', 'check', 'evidence')
foreach ($kv in $Rest) {
  $i = $kv.IndexOf('=')
  if ($i -lt 1) { Write-Output ('参数要写成 key=value：' + $kv); exit 2 }
  $k = $kv.Substring(0, $i); $v = $kv.Substring($i + 1)
  if ($Command -eq 'py' -and $k -notin @('code', 'iso', 'timeout')) { if (-not $A.vars) { $A.vars = @{} }; $A.vars[$k] = Conv $v; continue }
  if ($k -in $Keep) { $A[$k] = $v } else { $A[$k] = Conv $v }
}

# ---------------- 经验库（本软件 经验\ + 通用经验\）
function Index-Path([string]$dir) { Join-Path $dir '索引.json' }
function Load-Index([string]$dir) { $j = Read-Json (Index-Path $dir); if ($j -and $j.entries) { return @($j.entries) }; return @() }
function Save-Index([string]$dir, $entries) {
  $lines = @($entries | ForEach-Object { '  ' + ($_ | ConvertTo-Json -Compress -Depth 5) })
  $t = "{`"说明`":`"一行一条：id t(一句话) k(关键词) sw(软件) task(任务类型) v(1=验证过) u(用过次数) f(卡片文件)`",`n`"entries`":[`n" + ($lines -join ",`n") + "`n]}`n"
  Write-Text (Index-Path $dir) $t
}
function All-Entries { $r = @(); foreach ($d in @($SoftExp, $GenExp)) { foreach ($e in (Load-Index $d)) { $e | Add-Member -NotePropertyName _dir -NotePropertyValue $d -Force; $r += $e } }; return $r }
# 本次会话 = 调用本命令的 Agent 进程（往上找 grok/codex/agy/claude/cursor/gemini/node…）。换了 Agent 进程就是新的一轮，YA 的「本次」只算这一轮。
function Agent-Session {
  $names = 'grok', 'codex', 'agy', 'claude', 'cursor', 'gemini', 'node', 'opencode', 'aider', 'windsurf', 'language_server_windows_x64'
  $cur = $PID
  for ($i = 0; $i -lt 12 -and $cur; $i++) {
    $r = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $cur) -ErrorAction SilentlyContinue
    if (-not $r) { break }
    $n = [IO.Path]::GetFileNameWithoutExtension([string]$r.Name).ToLowerInvariant()
    if ($names -contains $n) { return ($n + ':' + $r.ProcessId + ':' + $r.CreationDate.ToString('yyyyMMddHHmmss')) }
    $cur = $r.ParentProcessId
  }
  return ''
}
function New-Use([string]$sess) { [pscustomobject]@{ 开始 = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); 会话 = $sess; 搜索次数 = 0; 命中 = @(); 用上 = @(); 存入 = @() } }
function Load-Use {
  $p = Join-Path $Run '经验使用.json'; $u = $null
  try { $u = Read-Json $p } catch { $u = $null }
  $sess = Agent-Session
  if ($u) {
    $old = [string]$u.会话
    if ($sess -and $old -ne $sess) { $u = $null }                                   # 换了 Agent 进程：新一轮
    elseif (-not $sess -and ((Get-Date) - (Get-Item -LiteralPath $p).LastWriteTime).TotalMinutes -ge 10) { $u = $null }  # 认不出 Agent：10 分钟没动算新一轮
  }
  if (-not $u) { $u = New-Use $sess }
  foreach ($k in '会话', '存入') { if (-not ($u.PSObject.Properties.Name -contains $k)) { $u | Add-Member -NotePropertyName $k -NotePropertyValue $(if ($k -eq '会话') { $sess } else { @() }) } }
  return $u
}
function Mark-Used([string[]]$ids, [string]$q, [switch]$Saved) {
  $p = Join-Path $Run '经验使用.json'; $u = Load-Use
  $ids = @($ids | Where-Object { $_ })
  if ($Saved) { $u.存入 = @(@($u.存入) + $ids | Select-Object -Unique) }
  elseif ($q) { $u.搜索次数 = [int]$u.搜索次数 + 1; $u.命中 = @(@($u.命中) + $ids | Select-Object -Unique) } else { $u.用上 = @(@($u.用上) + $ids | Select-Object -Unique) }
  Write-Text $p ($u | ConvertTo-Json -Depth 5)
}
function Card-Text($e) {
  $c = Read-Json (Join-Path $e._dir $e.f)
  $o = [ordered]@{ id = $e.id; t = $e.t; sw = $e.sw }
  if ($c) { foreach ($f in 'do', 'pit', 'api', 'check', 'file') { if ($c.$f) { $o[$f] = $c.$f } } }
  return $o
}

if ($Command -eq 'exp_session') { $u = Load-Use; Write-Text (Join-Path $Run '经验使用.json') ($u | ConvertTo-Json -Depth 5); Write-Output ('本次会话：' + $(if ($u.会话) { $u.会话 } else { '（未识别 Agent）' })); exit 0 }
if ($Command -eq 'exp_search') {
  $q = [string]$A.q; if (-not $q) { Write-Output '用法：fc.ps1 exp_search q=短词'; exit 2 }
  $terms = @($q -split '[\s,，]+' | Where-Object { $_ })
  $hits = @()
  foreach ($e in (All-Entries)) {
    $s = 0
    foreach ($t in $terms) {
      foreach ($k in @($e.k)) { if ($k -eq $t) { $s += 3 } elseif ($k.Length -ge 2 -and ($k.Contains($t) -or $t.Contains($k))) { $s += 2 } }
      if (([string]$e.t + ' ' + $e.task + ' ' + $e.sw).Contains($t)) { $s += 1 }
    }
    if ($s -gt 0) { $hits += [pscustomobject]@{ s = $s; e = $e } }
  }
  $top = @($hits | Sort-Object s -Descending | Select-Object -First 5)
  Mark-Used @($top | ForEach-Object { $_.e.id }) $q
  if (-not $top.Count) { Write-Output ('没命中：' + $q + '。换个短词/同义词/英文再搜；都没有就自己做，做通后 exp_save。'); exit 0 }
  Write-Output ((@($top | ForEach-Object { Card-Text $_.e }) | ConvertTo-Json -Depth 6))
  exit 0
}
if ($Command -eq 'exp_list') { All-Entries | ForEach-Object { '{0}  [{1}] {2}  ({3})' -f $_.id, $_.sw, $_.t, ($_.k -join ',') }; exit 0 }
if ($Command -eq 'exp_get') {
  $e = All-Entries | Where-Object { $_.id -eq $A.id } | Select-Object -First 1
  if (-not $e) { Write-Output ('没有 ' + $A.id); exit 1 }
  Write-Output ([IO.File]::ReadAllText((Join-Path $e._dir $e.f), [Text.Encoding]::UTF8)); exit 0
}
if ($Command -eq 'exp_done') {
  $ids = @(([string]$A.id) -split '[,\s，]+' | Where-Object { $_ })
  foreach ($d in @($SoftExp, $GenExp)) {
    $en = Load-Index $d; $hit = $false
    foreach ($e in $en) { if ($e.id -in $ids) { $e.u = [int]$e.u + 1; $hit = $true } }
    if ($hit) { Save-Index $d $en }
  }
  Mark-Used $ids $null; Write-Output ('已记用上：' + ($ids -join ',')); exit 0
}
if ($Command -eq 'exp_save') {
  # 卡片字段：t 一句话结论；k 关键词(逗号)；sw；task；do 怎么做；pit 易卡点和绕法；api 关键命令；check 怎么核对；evidence 实测结果；v=1 验证过
  if ($A.file) { $c = Read-Json ((Resolve-Path -LiteralPath $A.file).Path) } else { $c = [pscustomobject]@{} ; foreach ($f in 't', 'k', 'sw', 'task', 'do', 'pit', 'api', 'check', 'evidence', 'v') { if ($A.ContainsKey($f)) { $c | Add-Member -NotePropertyName $f -NotePropertyValue $A[$f] -Force } } }
  if (-not $c.t -or -not $c.k) { Write-Output '至少要 t（一句话结论）和 k（关键词）'; exit 2 }
  $kw = @(if ($c.k -is [string]) { $c.k -split '[,，]' } else { @($c.k) }) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  $c | Add-Member -NotePropertyName k -NotePropertyValue @($kw) -Force
  if (-not $c.sw) { $c | Add-Member -NotePropertyName sw -NotePropertyValue 'FreeCAD' -Force }
  $gen = ($c.sw -eq '通用')
  $dir = if ($gen) { $GenExp } else { $SoftExp }
  $ok = ([string]$c.v -eq '1') -and $c.check -and $c.evidence
  if (-not $ok) {
    $f = Join-Path $dir ('_草稿\' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
    Write-Text $f ($c | ConvertTo-Json -Depth 6)
    Write-Output ('没验证（要 v=1 + check + evidence），只进草稿：' + $f); exit 0
  }
  $en = @(Load-Index $dir)
  # 查重：同软件里标题相同，或关键词重合≥一半 → 更新原条
  $dup = $null
  foreach ($e in $en) {
    if ($c.id -and $e.id -eq $c.id) { $dup = $e; break }
    $inter = @($e.k | Where-Object { $_ -in $kw }).Count; $min = [Math]::Min(@($e.k).Count, $kw.Count)
    if ($e.t -eq $c.t -or ($min -gt 0 -and $inter * 2 -ge $min -and $inter -ge 2)) { $dup = $e; break }
  }
  if ($dup) { $id = $dup.id } else {
    $pre = if ($gen) { 'G' } else { 'F' }
    $nums = @($en | ForEach-Object { if ($_.id -match '^\D+(\d+)$') { [int]$Matches[1] } }) + 0
    $id = $pre + ([int](($nums | Measure-Object -Maximum).Maximum) + 1).ToString('000')
  }
  $c | Add-Member -NotePropertyName id -NotePropertyValue $id -Force
  $c | Add-Member -NotePropertyName v -NotePropertyValue 1 -Force
  $c | Add-Member -NotePropertyName date -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
  $file = $id + '.json'
  Write-Text (Join-Path $dir $file) ($c | ConvertTo-Json -Depth 6)
  $row = [pscustomobject][ordered]@{ id = $id; t = $c.t; k = @($kw); sw = $c.sw; task = [string]$c.task; v = 1; u = $(if ($dup) { [int]$dup.u } else { 0 }); f = $file }
  $en = @($en | Where-Object { $_.id -ne $id }) + $row
  Save-Index $dir $en
  Mark-Used @($id) $null -Saved
  Write-Output ($(if ($dup) { '已更新原条 ' } else { '已新增 ' }) + $id + '：' + $c.t); exit 0
}

# ---------------- 发命令给前台 FreeCAD
function Link-Alive {
  $s = Read-Json (Join-Path $Run '状态.json')
  if (-not $s) { return $null }
  $age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0 - [double]$s.心跳
  if ($age -lt 5 -and (Get-Process -Id $s.pid -ErrorAction SilentlyContinue)) { return $s }
  return $null
}
function Send([string]$cmd, $args2, [double]$timeout = 60) {
  $id = [guid]::NewGuid().ToString('N')
  $inbox = Join-Path $Io 'inbox'; $out = Join-Path $Io ('outbox\' + $id + '.json')
  $job = @{ id = $id; cmd = $cmd; args = $args2 } | ConvertTo-Json -Depth 8 -Compress
  Write-Text (Join-Path $inbox ($id + '.tmp')) $job
  Move-Item -LiteralPath (Join-Path $inbox ($id + '.tmp')) -Destination (Join-Path $inbox ($id + '.json'))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    if (Test-Path -LiteralPath $out) { Start-Sleep -Milliseconds 30; $t = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8); Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue; return $t }
    Start-Sleep -Milliseconds 100
  }
  return $null
}

if ($Command -eq 'wait') {
  $limit = 120; if ($A.timeout) { $limit = [int]$A.timeout }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $limit) {
    if (Link-Alive) { $r = Send 'ping' @{} 10; if ($r -and $r -match '"ok":\s*true') { $j = $r | ConvertFrom-Json; Write-Output ('CONNECTED ' + $j.软件 + ' pid=' + $j.pid + ' after ' + [math]::Round($sw.Elapsed.TotalSeconds) + ' s'); exit 0 } }
    Start-Sleep -Milliseconds 500
  }
  Write-Output ('NOT CONNECTED after ' + $limit + ' s。先运行 一键连接.ps1。日志：' + (Join-Path $Io 'host.log')); exit 1
}
if (-not (Link-Alive)) { Write-Output '未连接：前台没有带连接的 FreeCAD。先运行 一键连接.ps1（已开就不要再开第二个）。'; exit 1 }
$to = 60; if ($A.timeout) { $to = [double]$A.timeout; $A.Remove('timeout') }
$r = Send $Command $A $to
if ($null -eq $r) { Write-Output ('超时 ' + $to + ' s：FreeCAD 可能在忙或弹了对话框，看前台窗口。'); exit 1 }
Write-Output $r
if ($r -match '"ok":\s*true') { exit 0 } else { exit 1 }
