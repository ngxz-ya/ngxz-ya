# 第一步先读 AGENTS.md「第 0 步」。脚本链「启动」段（软件无关）：脱离 Agent 作业启动目标软件的 GUI，等主窗口，记下 PID。
# 用法（在工作区 工作区\ 下）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\启动软件.ps1 -Exe "<本机定位.json install_dirs 内的可执行文件>" [-Arguments a,b] [-Env "名=值","名=值"] [-WaitSeconds 180]
# -Exe 必须位于 本机定位.json 的 install_dirs 内，否则拒绝。-Env 只作用于本次启动的子进程（不改系统/用户环境变量）。
# 若软件启动日志显示它会自动加载包外的自定义/插件/启动目录：用该软件官方文档写明的环境变量或参数（-Env/-Arguments）指向本轮 artifacts 内的空配置，不要读取、复制或加载那些包外目录。
# 不按进程名杀进程、不重启已有使用者的窗口。失败时保留现场并报告原始信息。
param([Parameter(Mandatory=$true)][string]$Exe,[string[]]$Arguments=@(),[string[]]$Env=@(),[string]$Directory,[ValidateRange(5,900)][int]$WaitSeconds=180)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
$locFile=@((Join-Path $ws '本机定位.json'),(Join-Path $pkg '本机定位.json'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $locFile){Write-Output 'LOCATE_REQUIRED: 先运行 连接教练\定位软件.ps1（或 一键连接.ps1）';exit 3}
$loc=Get-Content -LiteralPath $locFile -Raw -Encoding UTF8|ConvertFrom-Json
$exeFull=[IO.Path]::GetFullPath($Exe)
$inside=@($loc.install_dirs|Where-Object{$_ -and $exeFull.StartsWith(([IO.Path]::GetFullPath($_).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)})
if(-not $inside){Write-Output ('EXE_OUTSIDE_INSTALL_DIRS: '+$exeFull+' 不在 本机定位.json install_dirs 内，拒绝启动');exit 2}
if(-not [IO.File]::Exists($exeFull)){Write-Output ('EXE_MISSING: '+$exeFull);exit 3}
$stamp=(Get-Date).ToString('yyyyMMdd-HHmmss')
if(-not $Directory){$Directory=Join-Path $ws ('artifacts\launch-'+$stamp)}
[IO.Directory]::CreateDirectory($Directory)|Out-Null
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
$set=@{}
foreach($kv in $Env){if($kv -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'){throw ('ENV_FORMAT: '+$kv)};$set[$matches[1]]=$matches[2]}
foreach($k in $set.Keys){[Environment]::SetEnvironmentVariable($k,$set[$k],'Process')}
$t0=Get-Date
$id=[YaEvidence]::LaunchInteractive($exeFull,[string[]]$Arguments,$Directory)
Write-Output ('LAUNCHED pid='+$id+' exe='+$exeFull)
$title='';$hwnd=0;$exited=$null
$deadline=(Get-Date).AddSeconds($WaitSeconds)
while((Get-Date) -lt $deadline){
  $pr=Get-Process -Id $id -ErrorAction SilentlyContinue
  if(-not $pr){$exited=$true;break}
  if($pr.MainWindowHandle -ne 0 -and $pr.MainWindowTitle){$hwnd=[int64]$pr.MainWindowHandle;$title=$pr.MainWindowTitle;break}
  Start-Sleep -Seconds 2
}
$kids=@();try{$kids=@(Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$id)|ForEach-Object{[ordered]@{pid=$_.ProcessId;name=$_.Name}})}catch{}
$rec=[ordered]@{schema=1;pid=$id;exe=$exeFull;arguments=$Arguments;env_keys=@($set.Keys);directory=$Directory;started_local=$t0.ToString('o');seconds=[Math]::Round(((Get-Date)-$t0).TotalSeconds,1);main_window=$hwnd;title=$title;exited=[bool]$exited;children=$kids}
$out=Join-Path $Directory 'launch.json'
[IO.File]::WriteAllText($out,($rec|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
if($hwnd){Write-Output ('WINDOW_READY pid='+$id+' title="'+$title+'" ('+$rec.seconds+'s) record='+$out);Write-Output '下一步：确认窗口是正常主界面（不是错误对话框）→ 加载本包内桥接 → ya_link prepare/登记。';exit 0}
if($exited){Write-Output ('PROCESS_EXITED pid='+$id+' （可能是启动器转交给子进程或启动失败）children='+(($kids|ForEach-Object{$_.name+':'+$_.pid}) -join ',')+' record='+$out);exit 4}
Write-Output ('WINDOW_TIMEOUT pid='+$id+' 未在 '+$WaitSeconds+'s 内出现主窗口；进程保留，不杀不重启。检查是否卡在对话框/许可。record='+$out);exit 5