param([switch]$PathsOnly)
# 所有调用方按包路径绑定状态；不读取其它解压包的旧指针。
if (-not $PathsOnly -and -not ('YaEvidence' -as [type])) {
  Add-Type -AssemblyName System.Web.Extensions
  Add-Type -Path (Join-Path $PSScriptRoot '连接证据.cs') -ReferencedAssemblies System.Web.Extensions
}
function Assert-YaIsolatedPackage([string]$Package) {
  $marker=Join-Path $Package '包信息.json'
  if(-not (Test-Path -LiteralPath $marker -PathType Leaf)){throw 'SOURCE_READ_ONLY: 研发源码禁止运行。请先用准备隔离包.ps1生成新副本。'}
  $info=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
  if($info.schema -ne 2 -or $info.stage -notin @('TestCopy','AuditCandidate')){throw 'ISOLATION_METADATA_INVALID: 请从当前源码重新生成隔离副本。'}
}
function Get-YaHudInstanceName([string]$PluginDir, [string]$HudHome) {
  $identity = [IO.Path]::GetFullPath($PluginDir).TrimEnd('\').ToLowerInvariant() + '|' + [IO.Path]::GetFullPath($HudHome).TrimEnd('\').ToLowerInvariant()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'Local\YALinkHud-' + [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '') } finally { $sha.Dispose() }
}
function Get-YaPackageHudHome([string]$Package, [string]$Base = '') {
  Assert-YaIsolatedPackage $Package
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
