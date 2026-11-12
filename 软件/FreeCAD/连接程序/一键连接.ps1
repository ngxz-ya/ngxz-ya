# 一键：找本机 FreeCAD → 前台打开并加载常驻连接 → 等到连上 → 打开 YA。已连上就直接报 OK，不开第二个。
# 用法（任意目录）：powershell -NoProfile -ExecutionPolicy Bypass -File <本包>\软件\FreeCAD\连接程序\一键连接.ps1 [-FreeCAD <FreeCAD.exe 路径>]
param([string]$FreeCAD = '')
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
function Find-Root([string]$d) { while ($d) { if (Test-Path -LiteralPath (Join-Path $d 'AGENTS.md')) { return $d }; $d = Split-Path $d -Parent }; return $null }
$Root = Find-Root $PSScriptRoot
$Run = Join-Path $Root '运行数据'
$Fc = Join-Path $PSScriptRoot 'fc.ps1'
New-Item -ItemType Directory -Force -Path (Join-Path $Run 'FreeCAD') | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
# 本次会话的经验使用记录：按调用它的 Agent 进程分轮（换 Agent 进程就重开），YA 只显示这一轮的
& $Fc exp_session | Out-Null

# 脱离 Agent 启动：用 WMI Win32_Process.Create 起进程，它不是 Agent 命令的子进程，命令结束、Agent 收工都不会把窗口带走。
function Start-Detached([string]$line, [string]$dir, [int]$show = 1) {
  $st = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]$show }
  $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $line; CurrentDirectory = $dir; ProcessStartupInformation = $st }
  if ($r.ReturnValue -ne 0) { throw ('WMI 启动失败 ' + $r.ReturnValue + '：' + $line) }
  return [int]$r.ProcessId
}

function Start-YA {
  $ya = Join-Path $Root 'YA插件\ya.ps1'
  if (-not (Test-Path -LiteralPath $ya)) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  # ShowWindow=0 + -WindowStyle Hidden：不出控制台、任务栏不出 PowerShell 图标；YA 自己单实例，重复启动会直接退出
  [void](Start-Detached ('"' + $ps + '" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ya + '"') $Root 0)
}

# 界面中文：用户配置在本包 运行数据\FreeCAD用户\user.cfg（不动本机原有 FreeCAD 设置）。启动前把 General/Language 设成 Chinese (Simplified)。
# 不想要中文：启动前设环境变量 NGXZ_FC_LANG=off，或改成别的语言名（如 English）。
function Set-FcLanguage([string]$cfg) {
  $lang = if ($env:NGXZ_FC_LANG) { $env:NGXZ_FC_LANG } else { 'Chinese (Simplified)' }
  if ($lang -eq 'off') { return }
  if (-not (Test-Path -LiteralPath $cfg)) {
    [IO.File]::WriteAllText($cfg, ('<?xml version="1.0" encoding="UTF-8"?><FCParameters><FCParamGroup Name="Root"><FCParamGroup Name="BaseApp"><FCParamGroup Name="Preferences"><FCParamGroup Name="General"><FCText Name="Language">' + $lang + '</FCText></FCParamGroup></FCParamGroup></FCParamGroup></FCParamGroup></FCParameters>'), $utf8)
    return
  }
  $x = New-Object Xml.XmlDocument; $x.Load($cfg)
  $node = $x.DocumentElement
  foreach ($g in 'Root', 'BaseApp', 'Preferences', 'General') {
    $c = $node.SelectSingleNode("FCParamGroup[@Name='$g']")
    if (-not $c) { $c = $x.CreateElement('FCParamGroup'); $c.SetAttribute('Name', $g); [void]$node.AppendChild($c) }
    $node = $c
  }
  $t = $node.SelectSingleNode("FCText[@Name='Language']")
  if (-not $t) { $t = $x.CreateElement('FCText'); $t.SetAttribute('Name', 'Language'); [void]$node.AppendChild($t) }
  if ($t.InnerText -ne $lang) { $t.InnerText = $lang; $x.Save($cfg) }
}

# 1) 已连上？
& $Fc wait timeout=2 | Out-Null
if ($LASTEXITCODE -eq 0) { Start-YA; & $Fc wait timeout=5; Write-Output 'RESULT: OK（已连上，沿用前台这个 FreeCAD）'; exit 0 }

# 2) 找 FreeCAD.exe：参数 → 上次记下的路径 → 注册表 → 常见安装位置 → 本机用户程序目录
$cache = Join-Path $Run 'FreeCAD路径.txt'
$cands = @()
if ($FreeCAD) { $cands += $FreeCAD }
if ($env:FREECAD_EXE) { $cands += $env:FREECAD_EXE }
if (Test-Path $cache) { $cands += (Get-Content $cache -Encoding UTF8 | Select-Object -First 1) }
foreach ($k in 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'FreeCAD' } | ForEach-Object {
    if ($_.InstallLocation) { $cands += (Join-Path $_.InstallLocation 'bin\FreeCAD.exe') }
    if ($_.DisplayIcon) { $cands += ($_.DisplayIcon -replace ',\d+$', '' -replace '"', '') }
  }
}
foreach ($b in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
  if ($b -and (Test-Path $b)) { Get-ChildItem $b -Directory -Filter 'FreeCAD*' -ErrorAction SilentlyContinue | ForEach-Object { $cands += (Join-Path $_.FullName 'bin\FreeCAD.exe') } }
}
$exe = $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $exe) {
  $exe = Get-ChildItem $env:LOCALAPPDATA -Recurse -Depth 6 -Filter 'FreeCAD.exe' -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -match '\\bin$' } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $exe) { Write-Output 'RESULT: FAIL 本机没找到 FreeCAD.exe。用 -FreeCAD <路径> 指定，或先装 FreeCAD。'; exit 1 }
if ($exe -notmatch '\\bin\\[^\\]+$' -and (Test-Path (Join-Path (Split-Path $exe) 'bin\FreeCAD.exe'))) { $exe = Join-Path (Split-Path $exe) 'bin\FreeCAD.exe' }
[IO.File]::WriteAllText($cache, $exe, $utf8)

# 3) 前台打开 FreeCAD 并加载连接。用户配置放 运行数据\FreeCAD用户\，不动本机原有 FreeCAD 设置。
$home2 = Join-Path $Run 'FreeCAD用户'
New-Item -ItemType Directory -Force -Path $home2 | Out-Null
Set-FcLanguage (Join-Path $home2 'user.cfg')
$link = Join-Path $PSScriptRoot 'fc_link.py'
# WMI 起的进程不继承本进程的环境变量，所以经 cmd 设好 NGXZ_RUN / FREECAD_USER_HOME 再 start FreeCAD
$line = 'cmd.exe /d /c set "NGXZ_RUN=' + $Run + '"&& set "FREECAD_USER_HOME=' + $home2 + '"&& start "" /D "' + (Split-Path $exe) + '" "' + $exe + '" "' + $link + '"'
[void](Start-Detached $line (Split-Path $exe) 0)
Write-Output ('START FreeCAD（脱离 Agent 启动）' + $exe)

# 4) 等连上（首次启动约 10–40 秒）
& $Fc wait timeout=150
if ($LASTEXITCODE -ne 0) { Write-Output 'RESULT: FAIL FreeCAD 开了但连接没起来。看前台有没有弹框，日志 运行数据\FreeCAD\host.log'; exit 1 }
Start-YA
& $Fc status
Write-Output 'RESULT: OK'
