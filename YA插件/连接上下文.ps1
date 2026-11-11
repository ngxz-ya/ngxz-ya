param([switch]$PathsOnly)
# 所有调用方按包路径绑定状态；不读取其它解压包的旧指针。
if (-not $PathsOnly -and -not ('YaEvidence' -as [type])) {
  Add-Type -AssemblyName System.Web.Extensions
  Add-Type -Path (Join-Path $PSScriptRoot '连接证据.cs') -ReferencedAssemblies System.Web.Extensions
}
function Assert-YaIsolatedPackage([string]$Package) {
  if((Test-Path -LiteralPath (Join-Path $Package '更新中.json')) -or (Test-Path -LiteralPath (Join-Path $Package '运行数据\更新中.json'))){throw 'UPDATE_INCOMPLETE: 更新未完成，保留现场并从备份恢复程序后再运行'}
  $marker=Join-Path $Package '包信息.json'
  if(-not (Test-Path -LiteralPath $marker -PathType Leaf)){throw 'SOURCE_READ_ONLY: 研发源码禁止运行。请先用准备隔离包.ps1生成新副本。'}
  $info=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
  if($info.schema -ne 2 -or $info.stage -notin @('TestCopy','AuditCandidate','UserWorkspace')){throw 'ISOLATION_METADATA_INVALID: 请从当前源码重新生成隔离副本。'}
}

function Assert-YaLocalBridge([string]$Package, [string]$BridgePath) {
  if (-not ('YaEvidence' -as [type])) { throw 'YaEvidence type required before Assert-YaLocalBridge' }
  $reason = [YaEvidence]::AssertLocalBridge($Package, $BridgePath)
  if ($reason) { throw ('FOREIGN_BRIDGE_REFUSED: ' + $reason + '; bridge must be under this package or its managed workspace / this-run artifacts') }
  return $true
}
function Test-YaLocalBridge([string]$Package, [string]$BridgePath) {
  if (-not ('YaEvidence' -as [type])) { return $false }
  return ([YaEvidence]::AssertLocalBridge($Package, $BridgePath) -eq '')
}
function Get-YaHudInstanceName([string]$PluginDir, [string]$HudHome) {
  $identity = [IO.Path]::GetFullPath($PluginDir).TrimEnd('\').ToLowerInvariant() + '|' + [IO.Path]::GetFullPath($HudHome).TrimEnd('\').ToLowerInvariant()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'Local\YALinkHud-' + [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '') } finally { $sha.Dispose() }
}
function Get-YaPackageHudHome([string]$Package, [string]$Base = '') {
  Assert-YaIsolatedPackage $Package
  $info=Get-Content -LiteralPath (Join-Path $Package '包信息.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($info.stage -eq 'UserWorkspace'){
    $dataState=Join-Path $Package '运行数据\运行状态'
    $legacy=Join-Path $Package '运行状态'
    if((Test-Path -LiteralPath $legacy) -and -not (Test-Path -LiteralPath $dataState)){return $legacy}
    return $dataState
  }
  if (-not $Base) { $Base = $env:YALINK_HUD_HOME }
  if (-not $Base) {
    $Base = Join-Path $env:LOCALAPPDATA 'YAHud'
    if ($Base -match '[^\x00-\x7F]') { $Base = Join-Path $env:ProgramData 'YAHud' }
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Package).TrimEnd('\').ToLowerInvariant()))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
  $tail = Join-Path 'instances' $id
  if ($Base.TrimEnd('\').EndsWith($tail, [StringComparison]::OrdinalIgnoreCase)) { return $Base }
  return (Join-Path $Base $tail)
}

function Get-YaDesktopPackageRoot {
  $desk=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
  if([string]::IsNullOrWhiteSpace($desk)){throw 'DESKTOP_PATH_UNAVAILABLE'}
  return [IO.Path]::GetFullPath((Join-Path $desk 'ngxz-ya'))
}

function Test-YaPackageTree {
  param([Parameter(Mandatory=$true)][string]$Path)
  $p=[IO.Path]::GetFullPath($Path)
  return (Test-Path -LiteralPath (Join-Path $p 'AGENTS.md')) -and (Test-Path -LiteralPath (Join-Path $p 'YA插件\连接上下文.ps1'))
}

function Test-YaOfficialSourceTree {
  param([Parameter(Mandatory=$true)][string]$Path)
  $p=[IO.Path]::GetFullPath($Path)
  $desk=Get-YaDesktopPackageRoot
  if($p.TrimEnd('\') -ieq $desk.TrimEnd('\')){return $false}
  $marker=Join-Path $p '包信息.json'
  $stage=''
  if(Test-Path -LiteralPath $marker){
    try{$stage=(Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json).stage}catch{$stage=''}
  }
  if(@('TestCopy','AuditCandidate','UserWorkspace') -contains $stage){return $false}
  return (Test-Path -LiteralPath (Join-Path $p '.git')) -and (Test-YaPackageTree $p)
}

function Get-YaDataRoot {
  param([Parameter(Mandatory=$true)][string]$PackageRoot)
  $p=[IO.Path]::GetFullPath($PackageRoot)
  $new=Join-Path $p '运行数据'
  if(Test-Path -LiteralPath $new){return $new}
  $leaf=Split-Path $p -Leaf
  $parent=Split-Path $p -Parent
  if($leaf -ceq '工作区'){
    if((Test-Path -LiteralPath (Join-Path $parent 'artifacts')) -or (Test-Path -LiteralPath (Join-Path $p '运行状态'))){return $parent}
  }
  return $new
}

function Get-YaArtifactsDir {
  param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Slot)
  $root=Join-Path (Get-YaDataRoot $PackageRoot) 'artifacts'
  if($Slot){return (Join-Path $root $Slot)}
  return $root
}
