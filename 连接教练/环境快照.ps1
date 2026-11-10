# 第一步先读 AGENTS.md「第 0 步」。环境快照（软件无关）：记录用户/系统环境变量、目标软件厂商注册表、开机自启项；之后对比，发现本轮改动即越界。
# 快照（一键连接第 1 步自动做；测试方开测前也做）：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\环境快照.ps1 -Mode Snapshot [-Out <json>]
# 对比（越界审计每次自动对比环境变量和注册表；报告前再加 -ScanInstall 查 install_dirs 是否被写过）：... -Mode Diff [-Snap <json>] [-ScanInstall]
# 开测前硬检查（一键连接第 1b 步自动做；测试方也做）：... -Mode Precheck [-ExtraNames "<名字正则>"]
#   用户/系统持久环境变量里不得有：NGXZ_* / YALINK_*（非空）、名字含 STARTUP / USER_DIR / CUSTOM_DIR / PLUGIN / ADDIN / EXTENSION 的变量（非空），
#   以及值指向 ngxz* 目录、artifacts、本起点目录或 .dll 的变量——这些是旧轮次/旧桥接残留，会让软件开机就加载旧桥接，测试不再是「从零」。
#   有就退出码 2 ENV_PRECHECK_DIRTY 并停止：Agent 不得自己删（禁止持久改环境），报告用户清理后再跑。软件安装程序自己设的变量（值只指向 install_dirs，名字不命中上面规则）不算。
# 退出码：0 = ENV_CLEAN / 快照完成 / PRECHECK_CLEAN；2 = ENV_CHANGED / ENV_PRECHECK_DIRTY（本轮失败或不能开测，如实报告）；3 = 没有快照。
# 规则：本轮只允许进程级环境变量（启动软件.ps1 -Env 名=值）。禁止 setx、[Environment]::SetEnvironmentVariable(...,'User'/'Machine')、写注册表。
param([ValidateSet('Snapshot','Diff','Precheck')][string]$Mode='Diff',[string]$ExtraNames,[string]$Snap,[string]$Out,[string]$LocateFile,[switch]$ScanInstall,[switch]$Quiet)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$self=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if(-not $LocateFile){foreach($c in @((Join-Path $self '本机定位.json'),(Join-Path (Split-Path $self -Parent) '本机定位.json'))){if([IO.File]::Exists($c)){$LocateFile=$c;break}}}
$loc=$null;if($LocateFile -and [IO.File]::Exists($LocateFile)){$loc=Get-Content -LiteralPath $LocateFile -Raw -Encoding UTF8|ConvertFrom-Json}
function Default-Snap{
  $c=@((Join-Path $self '环境快照.json'),(Join-Path (Split-Path $self -Parent) '环境快照.json'))
  if((Split-Path $self -Leaf) -eq '工作区'){$c+=Join-Path (Split-Path $self -Parent) 'artifacts\env-snapshot.json'}
  foreach($x in $c){if([IO.File]::Exists($x)){return $x}};return $c[0]
}
function Vendors{
  $v=New-Object System.Collections.Generic.List[string]
  if($loc){foreach($d in @($loc.install_dirs)){if($d){$p=Split-Path $d -Parent;if($p -and $p.Length -gt 3){$v.Add((Split-Path $p -Leaf))}}};foreach($r in @($loc.registered)){if($r.publisher){$v.Add(([string]$r.publisher).Split(' ')[0])}}}
  @($v|Where-Object{$_ -and $_.Length -ge 2 -and $_ -notmatch '^(Program Files|Program Files \(x86\))$'}|Select-Object -Unique)
}
function Dump-Key([string]$path,$into,[int]$max=4000){
  if(-not (Test-Path -LiteralPath $path)){return}
  $keys=@(Get-Item -LiteralPath $path -ErrorAction SilentlyContinue)+@(Get-ChildItem -LiteralPath $path -Recurse -ErrorAction SilentlyContinue)
  foreach($k in $keys){if($into.Count -ge $max){$into['__truncated__']='1';return}
    foreach($n in @($k.GetValueNames())){try{$into[$k.Name+'|'+$n]=[string]$k.GetValue($n,$null,'DoNotExpandEnvironmentNames')}catch{}}
    $into[$k.Name+'|']='<key>'}
}
function Take{
  $o=[ordered]@{taken=(Get-Date).ToString('o');vendors=@(Vendors);env_user=@{};env_machine=@{};reg=@{};install_dirs=@($(if($loc){$loc.install_dirs}))}
  foreach($e in [Environment]::GetEnvironmentVariables('User').GetEnumerator()){$o.env_user[[string]$e.Key]=[string]$e.Value}
  foreach($e in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$o.env_machine[[string]$e.Key]=[string]$e.Value}
  $reg=@{}
  foreach($p in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce')){Dump-Key $p $reg 500}
  foreach($v in @($o.vendors)){foreach($p in @("HKCU:\Software\$v","HKLM:\SOFTWARE\$v","HKLM:\SOFTWARE\WOW6432Node\$v")){Dump-Key $p $reg}}
  $o.reg=$reg;return $o
}
if($Mode -eq 'Precheck'){
  $bad=New-Object System.Collections.Generic.List[string]
  $sd=$(if($loc -and $loc.start_dir){[string]$loc.start_dir}else{Split-Path $self -Parent})
  $nameRx='(?i)(^(NGXZ|YALINK)_)|((^|_)(USER_?STARTUP|STARTUP|USER_DIR|CUSTOM_DIR(ECTORY)?(_FILE)?|PLUGINS?|ADDINS?|EXTENSIONS?)(_|$))'
  foreach($t in @('User','Machine')){
    foreach($e in [Environment]::GetEnvironmentVariables($t).GetEnumerator()){
      $k=[string]$e.Key;$v=[string]$e.Value;if(-not $v.Trim()){continue}
      $why=''
      if($k -match $nameRx){$why='名字像插件/启动/本包变量'}
      elseif($ExtraNames -and $k -match $ExtraNames){$why='命中 -ExtraNames'}
      elseif($v -match '(?i)\\ngxz|\\artifacts(\\|;|$)|\.dll(;|$)'){$why='值指向 ngxz*/artifacts/.dll'}
      elseif($sd -and $sd.Length -gt 3 -and $v.IndexOf($sd,[StringComparison]::OrdinalIgnoreCase) -ge 0){$why='值指向本起点目录'}
      if($why){$bad.Add($t+' '+$k+'='+$v+'  ('+$why+')')}
    }
  }
  if($bad.Count){[ordered]@{status='ENV_PRECHECK_DIRTY';dirty=@($bad);next='不能开测：这些持久环境变量是旧轮次/旧桥接残留，会让软件启动时加载旧东西。Agent 不得自己删除（禁止持久改环境）；如实报告用户，由用户清理后重跑。'}|ConvertTo-Json -Depth 4 -Compress;exit 2}
  [ordered]@{status='PRECHECK_CLEAN';dirty=@()}|ConvertTo-Json -Compress;exit 0
}
if(-not $Snap){$Snap=Default-Snap}
if($Mode -eq 'Snapshot'){
  $o=Take;$dst=$(if($Out){$Out}else{$Snap})
  [IO.File]::WriteAllText([IO.Path]::GetFullPath($dst),($o|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding $false))
  if(-not $Quiet){Write-Output ('ENV_SNAPSHOT_SAVED: '+$dst+' env_user='+$o.env_user.Count+' env_machine='+$o.env_machine.Count+' reg='+$o.reg.Count+' vendors='+(@($o.vendors) -join ','))}
  exit 0
}
if(-not [IO.File]::Exists($Snap)){[ordered]@{status='NO_SNAPSHOT';snap=$Snap}|ConvertTo-Json -Compress;exit 3}
$old=Get-Content -LiteralPath $Snap -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $loc -and $old.vendors){}
$now=Take
$ch=New-Object System.Collections.Generic.List[string]
function Cmp([string]$tag,$a,$b){
  $ah=@{};if($a){foreach($p in $a.PSObject.Properties){$ah[$p.Name]=[string]$p.Value}}
  foreach($k in $b.Keys){if(-not $ah.ContainsKey($k)){$ch.Add($tag+' ADDED '+$k+'='+$b[$k])}elseif($ah[$k] -cne $b[$k]){$ch.Add($tag+' CHANGED '+$k+': '+$ah[$k]+' -> '+$b[$k])}}
  foreach($k in $ah.Keys){if(-not $b.ContainsKey($k)){$ch.Add($tag+' REMOVED '+$k+'='+$ah[$k])}}
}
Cmp 'env_user' $old.env_user $now.env_user
Cmp 'env_machine' $old.env_machine $now.env_machine
# vendor list may be empty in an early snapshot; only compare registry keys whose vendor was known at snapshot time
$ov=@($old.vendors);$nr=@{}
foreach($k in $now.reg.Keys){$keep=$k -match '\\CurrentVersion\\Run';foreach($v in $ov){if($k -match ('\\'+[regex]::Escape($v)+'(\\|\|)')){$keep=$true}};if($keep){$nr[$k]=$now.reg[$k]}}
Cmp 'reg' $old.reg $nr
if($ScanInstall){
  $t0=[datetime]$old.taken
  foreach($d in @($old.install_dirs)){if($d -and (Test-Path -LiteralPath $d)){
    Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime -gt $t0}|Select-Object -First 50|ForEach-Object{$ch.Add('install WRITTEN '+$_.FullName+' @'+$_.LastWriteTime.ToString('s'))}}}
}
$u=@($ch|Select-Object -Unique)
if($u.Count){[ordered]@{status='ENV_CHANGED';snap=$Snap;changes=$u;next='ROUND FAILED: 本轮改了用户/系统环境变量、注册表或软件安装目录。立即停止，如实报告这些改动；不要自己改回去以掩盖。'}|ConvertTo-Json -Depth 4 -Compress;exit 2}
[ordered]@{status='ENV_CLEAN';snap=$Snap;changes=@()}|ConvertTo-Json -Compress
exit 0