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
#   fc.ps1 exp_search q=方块                  先搜经验（转给包根 经验.ps1 -Soft <本软件文件夹名>）
#   fc.ps1 exp_get id=F001 | exp_done id=F001,G001 | exp_save file=卡.json | exp_list
param([Parameter(Position = 0)][string]$Command = 'status', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
function Find-Root([string]$d) { while ($d) { if (Test-Path -LiteralPath (Join-Path $d 'AGENTS.md')) { return $d }; $d = Split-Path $d -Parent }; return $null }
$Root = Find-Root $PSScriptRoot
if (-not $Root) { $Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
$Run = Join-Path $Root '运行数据'
$Scratch = Join-Path $Run '临时'; if (-not (Test-Path -LiteralPath $Scratch)) { New-Item -ItemType Directory -Force -Path $Scratch | Out-Null }
$SoftName = Split-Path (Split-Path $PSScriptRoot -Parent) -Leaf   # 软件文件夹名（软件\<名>\连接程序\fc.ps1），复制到别的软件不用改
$Io = Join-Path $Run $SoftName
$Utf8 = New-Object Text.UTF8Encoding($false)

function Read-Json([string]$p) { if (Test-Path -LiteralPath $p) { return ([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json) }; return $null }
function Write-Text([string]$p, [string]$t) { $d = Split-Path $p -Parent; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; [IO.File]::WriteAllText($p, $t, $Utf8) }
function Conv([string]$v) {
  $d = 0.0
  if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  if ($v -eq 'true') { return $true }; if ($v -eq 'false') { return $false }
  return $v
}

# 经验命令转给包根 经验.ps1 -Soft <软件文件夹名>（旧用法 fc.ps1 exp_search q=… 照常可用）
if ($Command -like 'exp_*') { & (Join-Path $Root '经验.ps1') $Command -Soft $SoftName @Rest; exit $LASTEXITCODE }
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


# ---------------- 发命令给前台软件
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
if (-not (Link-Alive)) { Write-Output ('未连接：前台没有带连接的 ' + $SoftName + '。先运行 一键连接.ps1（已开就不要再开第二个）。'); exit 1 }
$to = 60; if ($A.timeout) { $to = [double]$A.timeout; $A.Remove('timeout') }
$r = Send $Command $A $to
if ($null -eq $r) { Write-Output ('超时 ' + $to + ' s：FreeCAD 可能在忙或弹了对话框，看前台窗口。'); exit 1 }
Write-Output $r
if ($r -match '"ok":\s*true') { exit 0 } else { exit 1 }
