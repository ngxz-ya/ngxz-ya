# 越界路径审计（第 0 步强制闸门）：部署工作区、写/编译桥接、启动或接入软件、改模、读回、YA 接通、报告前各跑一次。
# 退出码 2 = OVERREACH_FAIL = 本轮失败：立即停止，不再执行后续步骤，如实报告命中路径。
# -Paths：本轮已访问及本步将访问的全部包外绝对路径（或命令原文）。-AgentLog：宿主/验收方用会话 JSONL 复核。
param([string[]]$Paths,[string]$AgentLog,[string[]]$PackageRoots,[string]$LocateFile)
$ErrorActionPreference='Stop'
if(-not $Paths -and -not $AgentLog){throw 'PATHS_OR_AGENT_LOG_REQUIRED'}
$self=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if(-not $LocateFile){foreach($c in @((Join-Path $self '本机定位.json'),(Join-Path (Split-Path $self -Parent) '本机定位.json'))){if([IO.File]::Exists($c)){$LocateFile=$c;break}}}
$loc=$null;if($LocateFile -and [IO.File]::Exists($LocateFile)){$loc=Get-Content -LiteralPath $LocateFile -Raw -Encoding UTF8|ConvertFrom-Json}
function Norm([string]$p){try{return [IO.Path]::GetFullPath($p).TrimEnd('\')}catch{return $null}}
$home1=Norm $env:USERPROFILE
$special=@($home1,(Norm ([Environment]::GetFolderPath('DesktopDirectory'))),(Norm ([Environment]::GetFolderPath('MyDocuments'))),(Norm (Join-Path $env:USERPROFILE 'Downloads')))|Where-Object{$_}
$allowed=New-Object System.Collections.Generic.List[string]
function Allow([string]$p){$n=Norm $p;if($n -and $n.Length -gt 3 -and -not ($special -contains $n)){$allowed.Add($n)}}
Allow $self
if((Split-Path $self -Leaf) -eq '工作区'){Allow (Split-Path $self -Parent)}
foreach($r in @($PackageRoots)){if($r){Allow $r}}
if($loc){Allow $loc.package;Allow $loc.start_dir;foreach($d in @($loc.install_dirs)){Allow $d}}
Allow (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'ngxz-ya')
Allow $env:WINDIR
foreach($d in @((Join-Path $env:LOCALAPPDATA 'YALink'),(Join-Path $env:LOCALAPPDATA 'YAHud'),(Join-Path $env:ProgramData 'YALink'),(Join-Path $env:ProgramFiles 'Git'),(Join-Path $env:ProgramFiles 'PowerShell'),(Join-Path $env:ProgramFiles 'dotnet'),(Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs'))){if($d){Allow $d}}
$tempRoot=Norm $env:TEMP
$hits=New-Object System.Collections.Generic.List[string]
function Check-Text([string]$t){
  if(-not $t){return}
  foreach($m in [regex]::Matches($t,'(?i)(\$env:USERPROFILE|\$HOME\b|%USERPROFILE%|%HOMEPATH%|GetFolderPath|(?<![\w\\])~[\\/]|\.gitconfig|Get-PSDrive)')){$hits.Add('forbidden-token: '+$m.Value)}
  foreach($m in [regex]::Matches($t,'(?i)(?<![a-z0-9])[a-z]:\\[^"''\r\n<>|*?,;]*')){
    $raw=$m.Value.TrimEnd()
    $ok=$false
    foreach($r in $allowed){
      if($raw.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){
        if($raw.Length -eq $r.Length -or $raw[$r.Length] -in @('\',' ','"',"'",')')){$ok=$true;break}
      }
    }
    if(-not $ok -and $tempRoot){
      if($raw.StartsWith($tempRoot+'\',[StringComparison]::OrdinalIgnoreCase) -and $raw.Length -gt $tempRoot.Length+1){$ok=$true}
    }
    if(-not $ok){
      $cut=$raw;$i=$cut.IndexOf(' -');if($i -gt 2){$cut=$cut.Substring(0,$i)}
      if($cut.Length -gt 3){foreach($r in $allowed){if($r.StartsWith($cut,[StringComparison]::OrdinalIgnoreCase) -and $cut.Contains(' ') -eq $false -and $r.Length -gt $cut.Length -and $r[$cut.Length] -eq ' '){$ok=$true;break}}}
      if(-not $ok){if($cut.Length -gt 160){$cut=$cut.Substring(0,160)};$hits.Add($cut)}
    }
  }
}
function Get-Strings($x){
  if($null -eq $x){return}
  if($x -is [string]){return $x}
  if($x -is [Collections.IEnumerable]){foreach($i in $x){Get-Strings $i};return}
  if($x -is [psobject]){foreach($pp in $x.PSObject.Properties){Get-Strings $pp.Value}}
}
foreach($p in @($Paths)){Check-Text $p}
if($AgentLog){
  if(-not (Test-Path -LiteralPath $AgentLog -PathType Leaf)){throw 'AGENT_LOG_REQUIRED'}
  foreach($line in [IO.File]::ReadLines($AgentLog,[Text.Encoding]::UTF8)){
    if($line -notmatch '"type"\s*:\s*"tool_call"'){continue}
    try{$o=$line|ConvertFrom-Json}catch{continue}
    if($o.rawInput){foreach($v in (Get-Strings $o.rawInput)){Check-Text $v}}
  }
}
$uniq=@($hits|Select-Object -Unique)
if($uniq.Count -gt 0){
  [ordered]@{status='OVERREACH_FAIL';hits=$uniq;allowed=@($allowed|Select-Object -Unique);next='本轮失败：立即停止，不再执行后续步骤，向用户如实报告这些路径。'}|ConvertTo-Json -Depth 4
  exit 2
}
[ordered]@{status='OVERREACH_CLEAR';hits=@();allowed=@($allowed|Select-Object -Unique)}|ConvertTo-Json -Depth 4
exit 0
