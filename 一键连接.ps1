# 第一步先读 AGENTS.md「第 0 步」。这是一条命令的通用脚本链入口（任何机械软件同一套，不含任何软件专属连接方法）。
# 用法（在包根）：powershell -NoProfile -ExecutionPolicy Bypass -File .\一键连接.ps1 -Software "<软件名>" -StartDir "<本会话起点目录>"
# 阶段：0 落位 → 1 定位软件 → 2 部署工作区 → 3 连接前查通用卡 → 4 有本机连接经验就快连 / 没有就停在 NEED_AGENT_METHOD 并打印后续命令。
param([Parameter(Mandatory=$true)][string]$Software,[string]$StartDir,[string]$Slot,[switch]$NoPanel)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$t0=Get-Date
function Say([string]$s){Write-Output ('['+('{0,6:N1}' -f ((Get-Date)-$t0).TotalSeconds)+'s] '+$s)}
function PS1([string]$f,[string[]]$a){& powershell -NoProfile -ExecutionPolicy Bypass -File $f @a|Out-Host;return $LASTEXITCODE}
$me=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
Write-Output '== ngxz-ya 一键连接（通用脚本链）=='
Write-Output 'STEP0: 只碰本包、起点目录、本机定位.json 的 install_dirs；每个大步骤前跑 连接教练\越界路径审计.ps1（退出码 2=本轮失败，立即停）。'
Write-Output 'CHAIN: 0落位 → 1定位软件 → 2部署工作区 → 3连接前查通用卡 → 4快连(有经验) | NEED_AGENT_METHOD(无经验：上网找合法方法 → 编译桥接 → 启动软件 → 握手登记 → 建模前查卡 → Connect改模+独立读回 → 存经验)'
if((Split-Path $me -Leaf) -eq '工作区'){Write-Output 'WRONG_ENTRY: 请在下载包根（ngxz-ya-main）运行本脚本，不要在 工作区 内运行';exit 9}
# 0 落位
$lw=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $me '连接教练\落位.ps1') -Package $me @(if($StartDir){@('-StartDir',$StartDir)})
$lc=$LASTEXITCODE;$lw|Where-Object{$_ -notmatch '^\{'}|ForEach-Object{Say $_}
if($lc -ne 0){exit $lc}
$r=($lw|Where-Object{$_ -match '^\{'}|Select-Object -Last 1)|ConvertFrom-Json
if($r.moved){
  Say ('0 落位：转到 '+$r.package+' 继续（之后只在那里工作）')
  $a=@('-Software',$Software,'-StartDir',(Split-Path $r.package -Parent));if($Slot){$a+=@('-Slot',$Slot)};if($NoPanel){$a+='-NoPanel'}
  exit (PS1 (Join-Path $r.package '一键连接.ps1') $a)
}
Say ('0 落位：本包在 '+$me)
# 1 定位
$lo=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $me '连接教练\定位软件.ps1') -Software $Software;$c=$LASTEXITCODE;$lo|Where-Object{$_ -match '^(LOCATED|NOT_FOUND)'}|ForEach-Object{Say $_}
if($c -eq 3){Say 'STOP 1 定位：没找到目标软件。按规则报告并停止，不得自行扩大搜索。';exit 3}
if($c -ne 0){Say ('STOP 1 定位失败 exit='+$c);exit $c}
$loc=Get-Content -LiteralPath (Join-Path $me '本机定位.json') -Raw -Encoding UTF8|ConvertFrom-Json
Say ('1 定位：install_dirs = '+(@($loc.install_dirs) -join ' ; '))
# 1b 环境快照（之后越界审计每次自动对比：用户/系统环境变量、厂商注册表、自启项；有改动=本轮失败）
$snapF=Join-Path $me '环境快照.json'
if([IO.File]::Exists($snapF)){Say ('1b 环境快照：沿用本轮已有 '+$snapF)}else{& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $me '连接教练\环境快照.ps1') -Mode Snapshot -Out $snapF -LocateFile (Join-Path $me '本机定位.json')|ForEach-Object{Say ('1b '+$_)}}
# 1c 开测前环境硬检查：持久环境变量里不得有旧桥接/启动目录/本包残留（NGXZ_*、YALINK_*、*STARTUP*、*USER_DIR*、*PLUGIN* 等，或值指向 ngxz*/artifacts/.dll/起点目录）
$pc=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $me '连接教练\环境快照.ps1') -Mode Precheck -LocateFile (Join-Path $me '本机定位.json');$pcc=$LASTEXITCODE
if($pcc -eq 2){Say ('STOP 1c 开测前环境不干净：'+($pc -join ' '));Say '  这些持久环境变量会让软件启动时加载旧桥接/旧启动目录。不要自己删除（禁止持久改环境），如实报告用户，由用户清理后重跑本脚本。';exit 11}
Say ('1c 环境硬检查：'+($pc -join ' '))
# 2 部署
$start=Split-Path $me -Parent
$desk=[IO.Path]::GetFullPath([Environment]::GetFolderPath('DesktopDirectory')).TrimEnd('\')
$inPlace=($StartDir -and [IO.Path]::GetFullPath($StartDir).TrimEnd('\') -ieq $me)
$wsRoot=$(if($inPlace){Join-Path $me 'ngxz-ya-ws'}elseif($start -ieq $desk){Join-Path $desk 'ngxz-ya'}else{Join-Path $start 'ngxz-ya-ws'})
$a=@('-Software',$Software,'-Workspace',$wsRoot);if(-not (Test-Path -LiteralPath $wsRoot)){$a+='-Fresh'};if($NoPanel){$a+='-NoPanel'}
$src=Join-Path $me '下载来源.json'
$out=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $me '启动.ps1') @a
$dc=$LASTEXITCODE;$out|ForEach-Object{Write-Output $_}
$wl=$out|Where-Object{$_ -match '^workspace: '}|Select-Object -Last 1
if(-not $wl){Say ('STOP 2 部署失败 exit='+$dc+'（保留现场，报告上面原文）');exit 2}
$rt=$wl.Substring(11).Trim();$ws=Split-Path $rt -Parent
if([IO.File]::Exists($src)){[IO.File]::Copy($src,(Join-Path $ws '下载来源.json'),$true)}
if([IO.File]::Exists($snapF)){[void][IO.Directory]::CreateDirectory((Join-Path $ws 'artifacts'));[IO.File]::Copy($snapF,(Join-Path $ws 'artifacts\env-snapshot.json'),$true)}
Say ('2 部署：工作区 = '+$rt+'（Check exit='+$dc+'，FRONTEND_ADAPTER_MISSING 等在首连时属正常）')
# 2b 本会话起点（来源闸只认此后由 取页.ps1 打开的网页）+ 包自身脚本哈希基线（越界审计核对：Agent 改包脚本 = 本轮失败）
$artD=Join-Path $ws 'artifacts';[void][IO.Directory]::CreateDirectory($artD)
$roundF=Join-Path $artD 'round.json';$newRound=$true
if([IO.File]::Exists($roundF)){try{$oj=[IO.File]::ReadAllText($roundF,[Text.Encoding]::UTF8)|ConvertFrom-Json;$ou=[DateTime]::Parse([string]$oj.started_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime();if(([DateTime]::UtcNow-$ou).TotalHours -lt 12){$newRound=$false}}catch{}}
if($newRound){[IO.File]::WriteAllText($roundF,(([ordered]@{schema=1;round_id=[guid]::NewGuid().ToString('N');started_utc=[DateTime]::UtcNow.ToString('o');software=$Software;package=$me})|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
Say ('2b 本会话起点：'+$roundF+$(if($newRound){'（新）'}else{'（沿用 12 小时内的）'}))
$baseF=Join-Path $artD 'pkg-baseline.json'
if(-not [IO.File]::Exists($baseF)){
  $roots=[ordered]@{}
  foreach($root in @($me,$rt)){$rn=[IO.Path]::GetFullPath($root).TrimEnd('\');$fh=[ordered]@{}
    Get-ChildItem -LiteralPath $rn -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension -match '^(?i)\.(ps1|psm1|cs|bat|cmd|py|js)$'}|ForEach-Object{
      $rel=$_.FullName.Substring($rn.Length+1)
      if($rel -like 'artifacts\*' -or $rel -like 'ngxz-ya-ws\*' -or $rel -like '连接教练\连接经验\*\*'){return}
      $fh[$rel]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    $roots[$rn]=$fh}
  [IO.File]::WriteAllText($baseF,(([ordered]@{schema=1;created_utc=[DateTime]::UtcNow.ToString('o');rule='包自身脚本不得被 Agent 修改；越界审计逐个核对哈希';roots=$roots})|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  Say ('2b 包脚本哈希基线：'+$baseF+'（'+(@($roots.Values|ForEach-Object{$_.Count})|Measure-Object -Sum).Sum+' 个文件）')
}else{Say ('2b 包脚本哈希基线：沿用 '+$baseF)}
# 3 连接前查通用卡
$cl=Join-Path $ws 'artifacts\card-calls.jsonl'
PS1 (Join-Path $rt '连接教练\查通用卡.ps1') @('-Stage','连接前','-Log',$cl)|Out-Null
Say ('3 查卡：已记录 '+$cl)
# 4 复用
if(-not $Slot){$Slot=(($Software.ToLowerInvariant()) -replace '[^a-z0-9]','')}
$fast=$false
if($Slot){
  Push-Location $rt
  try{$f=& powershell -NoProfile -ExecutionPolicy Bypass -File '.\连接教练\连接经验\连接经验.ps1' find ("task=连接 "+$Software)}finally{Pop-Location}
  $f|ForEach-Object{Write-Output $_}
  $fl=@($f|Where-Object{$_ -match 'fast:.*slot=([A-Za-z0-9_-]+)'})
  if($fl){$fast=$true;[void]($fl[0] -match 'slot=([A-Za-z0-9_-]+)');$Slot=$matches[1]}
}
if($fast){
  Say ('4 复用：发现本机连接经验（槽 '+$Slot+'），跑 快连.ps1')
  Push-Location $rt
  try{$q=& powershell -NoProfile -ExecutionPolicy Bypass -File '.\连接教练\连接经验\快连.ps1' ("slot="+$Slot);$qc=$LASTEXITCODE}finally{Pop-Location}
  $q|ForEach-Object{Write-Output $_}
  if(@($q|Where-Object{$_ -match 'RESULT: (OK|ALREADY_REGISTERED)'}).Count){
    Say ('CONNECTED_VIA_SAVED_EXPERIENCE 槽='+$Slot+' 用时 '+[Math]::Round(((Get-Date)-$t0).TotalSeconds,1)+'s')
    Write-Output ('下一步（首连轻读回验收：建一个简单特征，独立读回核对尺寸和面数；复杂改模留到首连之后用 Run）：cd "'+$rt+'"；建模前 .\连接教练\查通用卡.ps1 -Stage 建模前；写任务 JSON；.\连接软件.ps1 -Software "'+$Software+'" -Action Connect -TaskFile <任务.json>')
    exit 0
  }
  Say ('STOP 4 快连未通过 exit='+$qc+'：不重试、不杀进程；按输出排查。如卡已不适用，按 NEED_AGENT_METHOD 流程修好后改原卡。');exit 4
}
Say '4 复用：本机没有该软件的连接经验（首连）。'
Write-Output ''
Write-Output 'NEED_AGENT_METHOD — 包内不含任何软件专属连接方法，下面每一步由你完成；每个大步骤前先跑越界审计：'
Write-Output ('  工作目录：cd "'+$rt+'"   软件槽：'+$Slot+'   证据目录：'+(Join-Path $ws 'artifacts'))
Write-Output '  a) 【硬闸】先上网找合法的开源/官方连接方案，并在本会话真实打开（Agent 自带网页工具被代理 fake-IP 挡 github.com 时，用本包取页脚本，已实测可开 github.com/api.github.com/raw）：'
Write-Output ('     .\连接教练\取页.ps1 -GitHubSearch "'+$Software+' automation api"   → 挑合法开源仓库 →   .\连接教练\取页.ps1 -Url <仓库或官方文档网址>（缓存+哈希，读它给的 .txt 正文）')
Write-Output '     读完逐条登记：.\连接教练\来源闸.ps1 -Add -Url <同一网址> -Points "要点（写页面原词：接口/类名/文件名/加载方式）" -Query "搜索词"'
Write-Output '     合格 = ≥2 条不同网址、≥1 条是 GitHub 仓库、每条都在本会话由 取页.ps1 打开过且哈希对得上、要点里 ≥2 个英文词出现在该页正文。没过，b) 准备接入 和 c) 编译桥接 都拒绝（退出码 5）。'
$sg=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rt '连接教练\来源闸.ps1') -Check)
if($LASTEXITCODE -eq 0){Write-Output ('  SOURCES_GATE: OPEN '+($sg|Select-Object -First 1))}else{Write-Output '  SOURCES_GATE: CLOSED — 现在只能做 a)（上网搜索+登记来源），不得跳到 b)/c)。'}
Write-Output '     只用 本机定位.json install_dirs 里的文件核对版本与接口。'
Write-Output ('  b) 生成驱动草稿：.\适配器\准备接入.ps1 -Software "'+$Software+'"')
Write-Output '  b2) 写任何接口调用前先探测本机版本真实有的成员：.\适配器\接口探测.ps1 -Assemblies <install_dirs 内官方程序集> ；用到的成员再 -Check "类型::成员,..."，缺失就换能力文件里有的成员（别照搬别的版本的示例）。'
Write-Output '  b3) 【硬闸】最小插件验证（完整桥接之前）：.\适配器\最小插件验证.ps1 -Init → 写一个只写 ready 文件+打印"已加载"的空插件 → .\适配器\编译桥接.ps1 -Probe -Source <空插件.cs> -Out <工作区>\artifacts\minplugin\<名>.dll -References <官方程序集>'
Write-Output '      → 按来源资料的加载方式（入口方法、插件/启动目录、启动参数、进程级环境变量）经 限时运行+启动软件 启动 → .\适配器\最小插件验证.ps1 -Verify -TargetPid <PID>（ready 文件+软件自身日志都确认才 MINPLUGIN_VERIFIED）。'
Write-Output '      空插件不过就别上完整桥接：看它打印的日志相关行，对照资料改加载方式；没过 c) 编译桥接（不带 -Probe）拒绝（退出码 8 MINPLUGIN_REQUIRED）。'
Write-Output ('  c) 桥接源码只写在 连接教练\连接经验\'+$Slot+'\ 或 artifacts 内；沿用空插件已验证的加载方式；编译：.\适配器\编译桥接.ps1 -Source <.cs> -Out <dll> -References <install_dirs 内的官方程序集> [-Versioned]')
Write-Output '     桥接通用要求（见 适配器\说明.md）：工作文件先查是否存在→存在就打开、打不开换唯一文件名再新建；拿到活动文档/部件先判空，空就回错误不执行；任何异常都回完整 JSON（带 protocol/action/request、ok=false、error=原文）。'
Write-Output '     改了桥接再编译 = RELOAD_REQUIRED：软件里已加载的是旧版，必须卸载/重载或重启软件后，用 QUERY_SESSION 核对 bridge_build 再测。'
Write-Output '  d) 启动软件（必须经限时运行；脱离 Agent 作业；可带只作用于本次的环境变量；软件 TEMP 默认指到 launch 目录\tmp，日志落 artifacts）：'
Write-Output '     .\适配器\限时运行.ps1 -File .\适配器\启动软件.ps1 -TimeoutSec 300 -ArgLine:"-Exe <install_dirs 内主程序.exe> -WaitSeconds 240 [-Env 名=值] [-ArgumentLine ''参数原文'']"'
Write-Output '     若打印 NOT_INTERACTIVE_DESKTOP（命令跑在隔离桌面）：弹窗守护、连接软件.ps1 Connect/Run、YA插件\ya_link.ps1、show_ya.ps1 都用 .\适配器\限时运行.ps1 -OnDesktop -File <脚本> -ArgLine:"参数" 在用户桌面上跑。'
Write-Output '     启动软件.ps1 自带弹窗守护：错误弹窗会被静默关闭并记录（退出码 7 = 失败点）；改模期间可另开 .\适配器\弹窗守护.ps1 -TargetPid <PID> -Seconds 600 -Dismiss -RetryScript <你的重建+重启脚本> -MaxRetries 2 做有限次自愈，到上限如实报告。'
Write-Output '     软件若自动加载包外自定义/插件目录：用官方文档的环境变量/参数指向 artifacts 内空配置，不读取不加载那些目录。'
Write-Output ('  e) 握手登记：.\YA插件\ya_link.ps1 soft='+$Software+' slot='+$Slot+' pid=<GUI PID> prepare=1 → 由软件内桥接写 readback → 去掉 prepare=1 再跑一次登记')
Write-Output '  f) 建模前查卡（必做，留证）：.\连接教练\查通用卡.ps1 -Stage 建模前 [-Q 关键词]；读全文 -Get <编号>；照做后 -Apply <编号> -How "..."。连接软件.ps1 Connect/Run 也会自动补记一次 建模前 查卡。'
Write-Output ('  g) 首连轻读回验收（简单特征，独立读回尺寸+面数）：.\连接软件.ps1 -Software "'+$Software+'" -Action Connect -TaskFile <任务.json>（见 适配器\说明.md）')
Write-Output ('  h) 通过后立即存经验：写 连接卡 + 连接教练\连接经验\'+$Slot+'\快通道.ps1，再 .\连接教练\连接经验\连接经验.ps1 add slot='+$Slot+' file=<卡.json>；下次 一键连接 会直接快连。')
Write-Output '  调用规则（防卡死）：所有可执行程序（软件自带的命令行工具、主程序）都经 .\适配器\限时运行.ps1（-Exe <程序> 或 -File <脚本>）跑；直接 & xxx.exe / Start-Process / cmd /c 调用 = 越界审计违规。'
Write-Output '     不要手写嵌套多行 powershell -Command "..."。多行逻辑写成 artifacts\*.ps1，用 .\适配器\限时运行.ps1 -File <脚本> -TimeoutSec 60 [-ArgLine:"参数"] 跑；'
Write-Output '     查软件窗口/YA：.\适配器\YA查询.ps1 -TargetPid <PID>；给桥接发命令/读回：.\适配器\调用桥接.ps1 -Pipe <ngxz-ya-32hex> -TargetPid <PID> -Action <动作> [-BodyFile <json>] -TimeoutSec 30。都自带超时。'
Write-Output '  环境规则：只许进程级环境变量（启动软件.ps1 -Env 名=值）。禁止 setx、SetEnvironmentVariable(…User/Machine)、写注册表、改 install_dirs 里的任何文件；越界审计会对比 1b 环境快照，有改动即本轮失败。'
Write-Output '  包规则：不得修改本包自带的脚本（适配器\*.ps1、YA插件\*.cs/*.ps1、连接教练\*.ps1 等）；自己的代码只写在 artifacts 或 连接教练\连接经验\<槽>\。越界审计核对包脚本哈希，改了 = 本轮失败。包脚本不适用就如实报告。'
Write-Output '  只有 Connect 返回 CONNECTED_INTERACTIVE 才算连上；任何一步失败如实报告，不把部分完成报成成功。'
exit 20