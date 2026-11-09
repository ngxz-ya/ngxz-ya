# 卸掉「安装.ps1」写到本机的运行目录和两个用户环境变量。
# 不删除本包，不删除经验库，不改任何机械软件的安装目录。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\安装卸载\卸载.ps1"
# 留下运行目录只卸登记：加上 -KeepFiles
param([switch]$KeepFiles,[switch]$PackageOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'YA插件\连接上下文.ps1') -PathsOnly
Assert-YaIsolatedPackage (Split-Path $PSScriptRoot -Parent)
if(-not $PackageOnly){throw 'ISOLATED_INSTALL_ONLY: 隔离包卸载必须使用 -PackageOnly。'}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Test-YaSafeHome([string]$Dir) {
  if (-not $Dir) { return $false }
  $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
  $allowed = @(
    [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YALink')).TrimEnd('\'),
    [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'YALink')).TrimEnd('\')
  )
  if($localInstall -and $full -ieq $localInstall){return $true}
  foreach ($one in $allowed) { if ($full -ieq $one) { return $true } }
  if($PackageOnly){foreach($one in $allowed){if($full -ieq (Join-Path $one ('packages\'+$packageIdentity))){return $true}}}
  return $false
}

$candidates = @(
  (Join-Path $env:LOCALAPPDATA 'YALink'),
  (Join-Path $env:ProgramData 'YALink')
)
$yaDir = $null
if($PackageOnly){
  $packageRoot=Split-Path $PSScriptRoot -Parent
  . (Join-Path $packageRoot 'YA插件\连接上下文.ps1')
  $packageIdentity=[YaEvidence]::Identity($packageRoot)
  $localInstall=Join-Path (Get-YaPackageHudHome $packageRoot) '安装'
  $candidates=@($localInstall)+@($candidates|ForEach-Object{Join-Path $_ ('packages\'+$packageIdentity)})
}
foreach ($c in $candidates) {
  if (Test-Path -LiteralPath (Join-Path $c 'install_state.json')) { $yaDir = $c; break }
}
if (-not $yaDir) {
  Write-Output '没找到 YALink 安装记录，看起来没装过这一版。'
  Write-Output '经验库在本包里，本来就不会被卸载删掉。'
  Write-Output '这一版只认 YALink。它不卸载任何机械软件。'
  Write-Output 'RESULT: OK'
  exit 0
}

try {
  $raw = [IO.File]::ReadAllText((Join-Path $yaDir 'install_state.json'), [Text.Encoding]::UTF8)
  if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
  $st = $raw | ConvertFrom-Json
} catch {
  Write-Output ('安装记录读不了: ' + (Join-Path $yaDir 'install_state.json'))
  Write-Output 'RESULT: FAIL'
  exit 1
}

Write-Output '=== YA 工具包 卸载 ==='
if (-not (Test-YaSafeHome ([string]$st.home)) -or ([IO.Path]::GetFullPath([string]$st.home).TrimEnd('\') -ine [IO.Path]::GetFullPath($yaDir).TrimEnd('\'))) {
  Write-Output ('安装记录里的目录不在允许范围内，已停止，没有删文件: ' + $st.home)
  Write-Output 'RESULT: FAIL'
  exit 1
}

if ($st.env) {
  foreach ($row in @($st.env)) {
    $name = [string]$row.name
    if($name -notin @('YALINK_HOME','YALINK_PACKAGE')){Write-Output 'RESULT: FAIL';exit 1}
    if (-not $row.set) { continue }
    $cur = [Environment]::GetEnvironmentVariable($name, 'User')
    $expect = ''
    if ($name -eq 'YALINK_HOME') { $expect = [string]$st.home }
    elseif ($name -eq 'YALINK_PACKAGE') { $expect = [string]$st.package }
    if (-not $cur) {
      Write-Output ('  环境变量 ' + $name + ' 已经没有了')
      continue
    }
    if ($expect -and ($cur.TrimEnd('\') -ine $expect.TrimEnd('\'))) {
      Write-Output ('  环境变量 ' + $name + ' 已是别的值，未改')
      continue
    }
    if ($row.had -and [string]$row.previous) {
      [Environment]::SetEnvironmentVariable($name, [string]$row.previous, 'User')
      Write-Output ('  已恢复 ' + $name)
    } else {
      [Environment]::SetEnvironmentVariable($name, $null, 'User')
      Write-Output ('  已删除用户环境变量 ' + $name)
    }
  }
}

if ($KeepFiles) {
  Write-Output ('  按 -KeepFiles 保留运行目录: ' + $yaDir)
  Write-Output '经验库未删除。'
  Write-Output 'RESULT: OK'
  exit 0
}

$names = New-Object System.Collections.Generic.List[string]
foreach ($n in @($st.copied)) { if ($n) { [void]$names.Add([string]$n) } }
foreach ($n in @($st.generated)) { if ($n) { [void]$names.Add([string]$n) } }
foreach ($n in @('ya.ps1', 'ya_slots.ps1', 'ya_flow.ps1', 'ya_panel.ps1', 'package_root.txt', 'library_path.txt', 'install_state.json', 'install.log')) {
  if ($names -notcontains $n) { [void]$names.Add($n) }
}
foreach($n in $names){if($n -notin @('ya.ps1','ya_slots.ps1','ya_flow.ps1','ya_panel.ps1','package_root.txt','library_path.txt','install_state.json','install.log')){Write-Output 'RESULT: FAIL';exit 1}}
foreach ($n in $names) {
  $p = Join-Path $yaDir $n
  if (Test-Path -LiteralPath $p) {
    Remove-Item -LiteralPath $p -Force
    Write-Output ('  已删除 ' + $p)
  }
}
$left = @(Get-ChildItem -LiteralPath $yaDir -Force -ErrorAction SilentlyContinue)
if ($left.Count -eq 0) {
  Remove-Item -LiteralPath $yaDir -Force
  Write-Output ('  已删除空目录 ' + $yaDir)
} else {
  Write-Output ('  运行目录里还有别的文件，目录保留: ' + $yaDir)
}
Write-Output '经验库未删除。本包未删除。'
Write-Output 'RESULT: OK'
exit 0
