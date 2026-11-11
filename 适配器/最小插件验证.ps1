# 第一步先读 AGENTS.md「第 0 步」。最小插件验证（软件无关，完整桥接之前必做）：先让目标软件按官方/开源资料的方式加载一个「什么都不干、只写 ready 文件并打印已加载」的空插件，
# 用软件自身日志确认真的加载了，才允许 适配器\编译桥接.ps1 编完整桥接（否则退出码 8 MINPLUGIN_REQUIRED）。空插件不过，完整桥接也一定加载不进去，别在完整桥接上反复试。最小插件通过后立即换完整桥，只再启动软件一次。
# 1 准备： powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\最小插件验证.ps1 -Init        （给出 ready 文件路径、本轮口令和要写进插件入口的两行代码）
# 2 编译： powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\编译桥接.ps1 -Probe -Source <空插件.cs> -Out <工作区>\artifacts\minplugin\<名>.dll -References <install_dirs 内官方程序集>
# 3 加载： 按你在来源里读到的官方/开源加载方式（启动参数、进程级环境变量、插件/启动目录指向 artifacts 等），经 限时运行 调 适配器\启动软件.ps1 启动软件；
#          启动软件.ps1 默认把软件的 TEMP/TMP 指到本次 launch 目录\tmp，软件写在临时目录里的日志会落在本轮 artifacts 里。
# 4 核对： powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\最小插件验证.ps1 -Verify -TargetPid <软件PID> [-SoftwareLog <日志文件,...>] [-LogPattern "<正则>"]
#          通过 = ready 文件口令对、写它的是目标软件进程、且软件自身日志里出现插件名/口令/-LogPattern → MINPLUGIN_VERIFIED（退出码 0，写 artifacts\minplugin\verified.json）。
#          4 = 没加载（ready 文件没出现：看下面打印的日志相关行，按资料改加载方式；不改 install_dirs、不写持久环境变量）；5 = ready 有但日志没确认；2 = 参数/前置缺失。
# -Status：只看当前状态。
param([switch]$Init,[switch]$Verify,[switch]$Status,[switch]$Force,[int]$TargetPid,[string[]]$SoftwareLog=@(),[string]$LogPattern)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
function Norm([string]$x){[IO.Path]::GetFullPath($x).TrimEnd('\')}
$pkg=Norm (Join-Path $PSScriptRoot '..')
function WsOf([string]$p){$data=Join-Path $p '运行数据';if(Test-Path -LiteralPath $data){return $data};if((Split-Path $p -Leaf) -eq '工作区'){return Split-Path $p -Parent};foreach($c in @((Join-Path $p 'ngxz-ya-ws'),(Join-Path (Split-Path $p -Parent) 'ngxz-ya-ws'))){if(Test-Path -LiteralPath (Join-Path $c '工作区')){return $c}};return $data}
$ws=WsOf $pkg
$art=Join-Path $ws 'artifacts';$dir=Join-Path $art 'minplugin';$probeF=Join-Path $dir 'probe.json';$verF=Join-Path $dir 'verified.json'
function UtcOf([string]$s){[DateTime]::Parse($s,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}
function Under([string]$x,[string[]]$roots){$n=Norm $x;foreach($r in $roots){if($r -and ($n -ieq (Norm $r) -or $n.StartsWith((Norm $r)+'\',[StringComparison]::OrdinalIgnoreCase))){return $true}};return $false}
$locFile=@((Join-Path $ws '本机定位.json'),(Join-Path $pkg '本机定位.json'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
$loc=$null;if($locFile){$loc=Get-Content -LiteralPath $locFile -Raw -Encoding UTF8|ConvertFrom-Json}
$inst=@();if($loc){$inst=@($loc.install_dirs|Where-Object{$_})}
function Snippet($p){
  Write-Output ('  ready 文件：'+$p.marker)
  Write-Output ('  本轮口令：  '+$p.token)
  Write-Output '  空插件入口里只放这两行（C#；其他语言照同样意思写），别的什么都不做：'
  Write-Output ('    System.IO.File.WriteAllText(@"'+$p.marker+'", "'+$p.token+'|" + System.Diagnostics.Process.GetCurrentProcess().Id + "|" + System.DateTime.UtcNow.ToString("o") + "|已加载");')
  Write-Output ('    （再用该软件官方日志/输出接口打印一行 "ngxz-minplugin '+$p.token+' 已加载"；没有日志接口就靠软件自己记录的加载日志里的插件文件名）')
  Write-Output '  入口方法、放哪个目录、用什么参数/环境变量让软件加载：照你在来源闸登记的官方/开源资料写，不要猜，不要改 install_dirs。'
}
if($Init){
  if([IO.File]::Exists($probeF) -and -not $Force){$p=Get-Content -LiteralPath $probeF -Raw -Encoding UTF8|ConvertFrom-Json;Write-Output ('MINPLUGIN_INIT_EXISTS: '+$probeF+'（-Force 换新口令）');Snippet $p;exit 0}
  [IO.Directory]::CreateDirectory($dir)|Out-Null
  $p=[ordered]@{schema=1;token=('ngxzmp'+[guid]::NewGuid().ToString('N').Substring(0,16));marker=(Join-Path $dir 'ready.txt');created_utc=[DateTime]::UtcNow.ToString('o')}
  if([IO.File]::Exists($p.marker)){[IO.File]::Move($p.marker,$p.marker+'.old-'+(Get-Date).ToString('HHmmss'))}
  [IO.File]::WriteAllText($probeF,($p|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  Write-Output ('MINPLUGIN_INIT: '+$probeF);Snippet ([pscustomobject]$p)
  Write-Output ('下一步：编译 .\适配器\编译桥接.ps1 -Probe -Source <空插件.cs> -Out "'+(Join-Path $dir '<名>.dll')+'" -References <官方程序集>；再按资料的加载方式经 限时运行 启动软件；最后 -Verify -TargetPid <PID>。')
  exit 0
}
if(-not [IO.File]::Exists($probeF)){Write-Output 'MINPLUGIN_NOT_INIT: 先运行 适配器\最小插件验证.ps1 -Init';exit 2}
$p=Get-Content -LiteralPath $probeF -Raw -Encoding UTF8|ConvertFrom-Json
$builds=@();$bl=Join-Path $art 'bridge-builds.jsonl';if([IO.File]::Exists($bl)){$builds=@([IO.File]::ReadAllLines($bl,[Text.Encoding]::UTF8)|Where-Object{$_}|ForEach-Object{try{$_|ConvertFrom-Json}catch{}}|Where-Object{$_ -and [string]$_.kind -eq 'probe'})}
if($Status){
  Write-Output ('probe: '+$probeF+' token='+$p.token)
  Write-Output ('probe builds: '+$builds.Count+$(if($builds){' last='+$builds[-1].file}else{''}))
  Write-Output ('ready file: '+$(if([IO.File]::Exists($p.marker)){[IO.File]::ReadAllText($p.marker)}else{'(none)'}))
  Write-Output ('verified: '+$(if([IO.File]::Exists($verF)){[IO.File]::ReadAllText($verF)}else{'no'}))
  exit 0
}
if(-not $Verify){Write-Output 'MINPLUGIN_BAD_ARGS: 用 -Init / -Verify -TargetPid <PID> / -Status';exit 2}
if(-not $TargetPid){Write-Output 'MINPLUGIN_BAD_ARGS: -Verify 需要 -TargetPid <软件PID>';exit 2}
if(-not $builds){Write-Output 'MINPLUGIN_NO_BUILD: 没有用 编译桥接.ps1 -Probe 编过空插件（bridge-builds.jsonl 无 kind=probe）';exit 2}
$dll=[string]$builds[-1].file;$dllName=[IO.Path]::GetFileName($dll);$stem=[IO.Path]::GetFileNameWithoutExtension($dll)
$all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
$tp=$all|Where-Object{$_.ProcessId -eq $TargetPid}|Select-Object -First 1
if(-not $tp){Write-Output ('MINPLUGIN_TARGET_GONE: 进程 '+$TargetPid+' 不在（软件已退出？看它的日志）')}
elseif($inst -and $tp.ExecutablePath -and -not (Under $tp.ExecutablePath $inst)){Write-Output ('MINPLUGIN_TARGET_NOT_SOFTWARE: '+$tp.ExecutablePath+' 不在 install_dirs');exit 2}
function Related([int]$a,[int]$b){if($a -eq $b){return $true};foreach($pair in @(@($a,$b),@($b,$a))){$x=$pair[0];for($i=0;$i -lt 6;$i++){$q=$all|Where-Object{$_.ProcessId -eq $x}|Select-Object -First 1;if(-not $q){break};$x=[int]$q.ParentProcessId;if($x -eq $pair[1]){return $true}}};return $false}
# launch record of the target -> its redirected temp dir
$launch=$null
foreach($lj in @(Get-ChildItem -LiteralPath $art -Filter 'launch.json' -Recurse -File -ErrorAction SilentlyContinue)){try{$j=[IO.File]::ReadAllText($lj.FullName,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)|ConvertFrom-Json;if([int]$j.pid -and (Related ([int]$j.pid) $TargetPid)){$launch=$j}}catch{}}
$logRoots=@($ws,(Split-Path $ws -Parent))+$inst
$logs=New-Object System.Collections.Generic.List[string]
foreach($s in @($SoftwareLog|ForEach-Object{$_ -split ','}|Where-Object{$_})){
  if(-not (Under $s $logRoots)){Write-Output ('MINPLUGIN_LOG_OUTSIDE: '+$s+' 不在工作区/起点/install_dirs。别去 %TEMP% 或用户目录翻日志：用 启动软件.ps1（默认把软件 TEMP 指到 launch 目录\tmp）重启后，日志就在 artifacts 里。');exit 2}
  if([IO.File]::Exists($s)){$logs.Add((Norm $s))}
}
$since=$(if($launch){([datetime]$launch.started_local).ToUniversalTime().AddSeconds(-5)}else{UtcOf ([string]$p.created_utc)})
$scanDirs=@();if($launch){$scanDirs+=[string]$launch.directory};$scanDirs=@($scanDirs|Where-Object{$_ -and (Test-Path -LiteralPath $_)})
foreach($d in $scanDirs){Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTimeUtc -ge $since -and $_.Length -lt 64MB -and $_.Extension -notmatch '^(?i)\.(dll|exe|prt|bin|dat|pdb|zip)$'}|Select-Object -First 200|ForEach-Object{$logs.Add($_.FullName)}}
$logs=@($logs|Select-Object -Unique)
# 1 ready file
$ready=$false;$readyWhy='';$rpid=0
if([IO.File]::Exists([string]$p.marker)){
  $parts=([IO.File]::ReadAllText([string]$p.marker)).Trim().Split('|')
  if($parts[0] -ne [string]$p.token){$readyWhy='ready 文件口令不对（不是本轮空插件写的）'}
  else{[void][int]::TryParse($parts[1],[ref]$rpid)
    if(-not (Related $rpid $TargetPid)){$readyWhy=('写 ready 的进程 '+$rpid+' 不是目标软件 '+$TargetPid+' （或其父子进程）')}
    elseif((UtcOf $parts[2]) -lt (UtcOf ([string]$builds[-1].utc))){$readyWhy='ready 文件比空插件编译时间还早'}
    else{$ready=$true}}
}else{$readyWhy='ready 文件没出现：软件没执行空插件入口'}
# 2 software's own log
$pat='(?i)('+[regex]::Escape([string]$p.token)+'|'+[regex]::Escape($dllName)+'|'+[regex]::Escape($stem)+$(if($LogPattern){'|'+$LogPattern}else{''})+')'
$logHit=$null;$related=New-Object System.Collections.Generic.List[string]
foreach($f in $logs){
  try{$ln=0;foreach($l in [IO.File]::ReadLines($f)){$ln++
    if($l -match $pat){if(-not $logHit){$logHit=[ordered]@{file=$f;line=$ln;text=$(if($l.Length -gt 300){$l.Substring(0,300)}else{$l})}};if($related.Count -lt 15){$related.Add((Split-Path $f -Leaf)+':'+$ln+': '+$l.Trim())}}
    elseif($related.Count -lt 15 -and $l -match '(?i)(error|fail|exception|could not|cannot|unable|not found|错误|失败|无法).*(load|dll|assembly|plugin|addin|startup|library|加载|插件)|(load|dll|assembly|plugin|addin|startup|加载|插件).*(error|fail|exception|could not|cannot|not found|错误|失败|无法)'){$related.Add((Split-Path $f -Leaf)+':'+$ln+': '+$l.Trim())}
  }}catch{}
}
Write-Output ('目标进程：'+$TargetPid+$(if($tp){' '+$tp.ExecutablePath}else{' (已退出)'}))
Write-Output ('空插件：'+$dll+'  口令 '+$p.token)
Write-Output ('ready：'+$(if($ready){'OK pid='+$rpid}else{'NO — '+$readyWhy}))
Write-Output ('软件日志：查了 '+$logs.Count+' 个文件'+$(if($launch){'（launch 目录 '+$launch.directory+'）'}else{'（没找到这个 PID 的 启动软件 记录：请用 限时运行+启动软件.ps1 启动，日志才会落进 artifacts）'})+' → '+$(if($logHit){'命中 '+$logHit.file+':'+$logHit.line}else{'未命中插件名/口令'}))
if($related.Count){Write-Output '日志相关行：';$related|ForEach-Object{Write-Output ('  | '+$(if($_.Length -gt 260){$_.Substring(0,260)}else{$_}))}}
if($ready -and $logHit){
  $v=[ordered]@{schema=1;token=[string]$p.token;target_pid=$TargetPid;ready_pid=$rpid;probe_dll=$dll;probe_sha256=[string]$builds[-1].sha256;log_file=$logHit.file;log_line=$logHit.line;log_text=$logHit.text;launch_dir=$(if($launch){[string]$launch.directory}else{''});verified_utc=[DateTime]::UtcNow.ToString('o')}
  [IO.File]::WriteAllText($verF,($v|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  Write-Output ('MINPLUGIN_VERIFIED: 空插件已被目标软件加载（ready+软件日志都确认）→ '+$verF)
  Write-Output '下一步：完整桥接沿用同一加载方式（同一入口、同一目录/参数/环境变量），再 编译桥接.ps1（不带 -Probe）。'
  exit 0
}
if($ready){Write-Output 'MINPLUGIN_LOG_UNCONFIRMED: ready 文件对，但软件自身日志里没找到插件名/口令。用 -SoftwareLog 指定软件日志（必须在工作区/起点/install_dirs 内），或在空插件里用软件官方日志接口打印口令后重试。';exit 5}
Write-Output 'MINPLUGIN_NOT_LOADED: 软件没加载空插件。对照来源资料核对：入口方法签名、插件放置目录或注册方式、启动参数/进程级环境变量名；看上面日志相关行。不要上完整桥接，不要改 install_dirs，不要写持久环境变量。'
exit 4
