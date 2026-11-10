# 第一步先读 AGENTS.md「第 0 步」。
# Overreach audit (STEP 0 mandatory gate). Run before every major step: deploy workspace, write/compile bridge,
# start/attach software, edit model, independent readback, YA link, final report.
# Exit 2 = OVERREACH_FAIL = this round FAILED: stop immediately, run nothing else, report the hit paths truthfully.
# -Paths: every outside-package absolute path (or raw command text) accessed so far this round and planned for this step.
#         Several values may follow -Paths; all of them are checked (none of them widens the allowed set).
# -AgentLog/-PackageRoots: verifier-only (host/tester) replay of a session JSONL.
[CmdletBinding(PositionalBinding=$false)]
param([string[]]$Paths,[string]$AgentLog,[string[]]$PackageRoots,[string]$LocateFile,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$Paths=@($Paths)+@($Rest)|Where-Object{$_}
if(-not $Paths -and -not $AgentLog){throw 'PATHS_OR_AGENT_LOG_REQUIRED'}
$self=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if(-not $LocateFile){foreach($c in @((Join-Path $self '本机定位.json'),(Join-Path (Split-Path $self -Parent) '本机定位.json'))){if([IO.File]::Exists($c)){$LocateFile=$c;break}}}
$loc=$null;if($LocateFile -and [IO.File]::Exists($LocateFile)){$loc=Get-Content -LiteralPath $LocateFile -Raw -Encoding UTF8|ConvertFrom-Json}
function Norm([string]$p){try{return [IO.Path]::GetFullPath($p).TrimEnd('\')}catch{return $null}}
$special=@((Norm $env:USERPROFILE),(Norm ([Environment]::GetFolderPath('DesktopDirectory'))),(Norm ([Environment]::GetFolderPath('MyDocuments'))),(Norm (Join-Path $env:USERPROFILE 'Downloads')),(Norm $env:TEMP),(Norm $env:ProgramFiles),(Norm ${env:ProgramFiles(x86)}),(Norm $env:ProgramW6432),(Norm $env:LOCALAPPDATA),(Norm $env:APPDATA))|Where-Object{$_}
$allowed=New-Object System.Collections.Generic.List[string]
function Allow([string]$p){$n=Norm $p;if($n -and $n.Length -gt 3 -and -not ($special -contains $n)){$allowed.Add($n)}}
# package, its start folder, managed workspace
Allow $self
Allow (Split-Path $self -Parent)
if((Split-Path $self -Leaf) -eq '工作区'){Allow (Split-Path (Split-Path $self -Parent) -Parent)}
Allow (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'ngxz-ya')
# the agent's OWN fresh package download in %TEMP% is allowed (only this package's own download dir/zip; other Temp files stay forbidden)
$tmpN=Norm $env:TEMP
if($tmpN -and $self.StartsWith($tmpN+'\',[StringComparison]::OrdinalIgnoreCase)){Allow (Join-Path $tmpN ($self.Substring($tmpN.Length+1).Split('\')[0]))}
foreach($of in @((Join-Path $self '下载来源.json'),(Join-Path (Split-Path $self -Parent) '下载来源.json'))){
  if([IO.File]::Exists($of)){try{$oj=Get-Content -LiteralPath $of -Raw -Encoding UTF8|ConvertFrom-Json;Allow $oj.origin_top;Allow $oj.start_dir}catch{}}
}
# located target software (+ its vendor folder)
$tokens=New-Object System.Collections.Generic.List[string]
if($loc){
  Allow $loc.package;Allow $loc.start_dir
  foreach($d in @($loc.install_dirs)){Allow $d;$v=Split-Path $d -Parent;Allow $v;$tokens.Add((Split-Path $v -Leaf))}
  if($loc.software){$tokens.Add([string]$loc.software)}
  foreach($r in @($loc.registered)){if($r.publisher){$tokens.Add(([string]$r.publisher).Split(' ')[0])}}
}
# verifier-only extra roots
if($AgentLog){foreach($r in @($PackageRoots)){if($r){Allow $r}}}
# OS + .NET toolchain + this package's own state dirs (not user data)
Allow $env:WINDIR
foreach($d in @((Join-Path $env:LOCALAPPDATA 'YALink'),(Join-Path $env:LOCALAPPDATA 'YAHud'),(Join-Path $env:ProgramData 'YALink'),(Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs'),(Join-Path $env:ProgramFiles 'Git'),(Join-Path $env:ProgramFiles 'PowerShell'))){if($d){Allow $d}}
$tokRx=$null
$tk=@($tokens|Where-Object{$_ -and $_.Length -ge 2}|Select-Object -Unique)
if($tk.Count){$tokRx=New-Object regex ('(?i)^('+(($tk|ForEach-Object{[regex]::Escape($_)}) -join '|')+')([ 0-9.]|$)')}
$hits=New-Object System.Collections.Generic.List[string]
function Test-One([string]$raw){
  $nn=Norm (($raw -split ' -')[0].Trim('"',"'"))
  if($nn -and $tmpN -and $nn.StartsWith($tmpN+'\',[StringComparison]::OrdinalIgnoreCase) -and $nn.Substring($tmpN.Length+1).Split('\')[0] -match '(?i)^ngxz'){return $true}
  foreach($r in $allowed){
    if($raw.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){
      if($raw.Length -eq $r.Length -or $raw[$r.Length] -in @('\',' ','"',"'",')')){return $true}
    }
  }
  # targeted probe of the software's own name / vendor (e.g. <drive>:\<Vendor>\...), never a bare root
  $cut=$raw;$i=$cut.IndexOf(' -');if($i -gt 2){$cut=$cut.Substring(0,$i)}
  $n=Norm $cut
  $userish=$false
  if($n){if($n -match '(?i)^[a-z]:\\(Users|Documents and Settings)(\\|$)'){$userish=$true}
    foreach($u in @((Norm $env:USERPROFILE),(Norm ([Environment]::GetFolderPath('DesktopDirectory'))),(Norm ([Environment]::GetFolderPath('MyDocuments'))),(Norm $env:TEMP),(Norm $env:LOCALAPPDATA),(Norm $env:APPDATA))){if($u -and ($n -ieq $u -or $n.StartsWith($u+'\',[StringComparison]::OrdinalIgnoreCase))){$userish=$true}}}
  if($tokRx -and $n -and $n.Length -gt 3 -and -not $userish -and -not ($special -contains $n)){
    $segs=$n.Substring(3).Split('\')
    foreach($s in $segs){if($tokRx.IsMatch($s)){return $true}}
  }
  return $false
}
function Check-Text([string]$t){
  if(-not $t){return}
  foreach($m in [regex]::Matches($t,'(?i)(\$env:USERPROFILE|\$HOME\b|%USERPROFILE%|%HOMEPATH%|GetFolderPath|(?<![\w\\])~[\\/]|\.gitconfig|Get-PSDrive)')){$hits.Add('forbidden-token: '+$m.Value)}
  foreach($m in [regex]::Matches($t,'(?i)(?<![a-z0-9])[a-z]:\\[^"''\r\n<>|*?,;]*')){
    $raw=$m.Value.TrimEnd()
    if(-not (Test-One $raw)){$c=$raw;$i=$c.IndexOf(' -');if($i -gt 2){$c=$c.Substring(0,$i)};if($c.Length -gt 160){$c=$c.Substring(0,160)};$hits.Add($c)}
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
  [ordered]@{status='OVERREACH_FAIL';hits=$uniq;allowed=@($allowed|Select-Object -Unique);next='ROUND FAILED: stop now, run no further step, report these paths to the user truthfully.'}|ConvertTo-Json -Depth 4
  exit 2
}
[ordered]@{status='OVERREACH_CLEAR';hits=@();allowed=@($allowed|Select-Object -Unique);next='OK: continue with this step only.'}|ConvertTo-Json -Depth 4
exit 0
