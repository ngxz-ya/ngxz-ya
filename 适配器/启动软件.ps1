# 第一步先读 AGENTS.md「第 0 步」。脚本链「启动」段（软件无关）：脱离 Agent 作业启动目标软件的 GUI，等主窗口，记下 PID。
# 用法（在工作区 工作区\ 下）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\启动软件.ps1 -Exe "<本机定位.json install_dirs 内的可执行文件>" [-ArgumentLine "-x:值 ""带空格的值"""] [-Env "名=值","名=值"] [-WaitSeconds 180]
# -Exe 必须位于 本机定位.json 的 install_dirs 内，否则拒绝。-Env 只作用于本次启动的子进程（不改系统/用户环境变量）。
# 若软件启动日志显示它会自动加载包外的自定义/插件/启动目录：用该软件官方文档写明的环境变量或参数（-Env/-Arguments）指向本轮 artifacts 内的空配置，不要读取、复制或加载那些包外目录。
# 不按进程名杀进程、不重启已有使用者的窗口。失败时保留现场并报告原始信息。
# 必须经限时运行调用：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -File 适配器\启动软件.ps1 -TimeoutSec 300 -ArgLine:"-Exe <主程序.exe> -WaitSeconds 240 [-Env 名=值]"（直接调用退出码 9 UNTIMED_LAUNCH）。
# 默认把软件进程的 TEMP/TMP 指到 本次 launch 目录\tmp（只作用于该进程），软件写在临时目录的日志就落在本轮 artifacts，供 最小插件验证.ps1 查；-KeepTemp 不改。
# 本脚本是包自身脚本：Agent 不得修改（越界审计核对包文件哈希，改了 = 本轮失败）。启动方式不适用时如实报告。
param([Parameter(Mandatory=$true)][string]$Exe,[string[]]$Arguments=@(),[string]$ArgumentLine,[string[]]$Env=@(),[string]$Directory,[ValidateRange(5,900)][int]$WaitSeconds=180,[switch]$KeepTemp)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$timedRun=[string]$env:NGXZ_TIMED
if(-not $timedRun){Write-Output 'UNTIMED_LAUNCH: 启动软件.ps1 必须经 适配器\限时运行.ps1 调用：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -File 适配器\启动软件.ps1 -TimeoutSec 300 -ArgLine:"-Exe <主程序.exe> -WaitSeconds 240"';exit 9}
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
if($ArgumentLine){$Arguments=@([regex]::Matches($ArgumentLine,'"([^"]*)"|(\S+)')|ForEach-Object{if($_.Groups[1].Success){$_.Groups[1].Value}else{$_.Groups[2].Value}})}
$set=@{}
foreach($kv in $Env){if($kv -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'){throw ('ENV_FORMAT: '+$kv)};$set[$matches[1]]=$matches[2]}
[Environment]::SetEnvironmentVariable('NGXZ_TIMED',$null,'Process')
$tempDir=''
if(-not $KeepTemp -and -not ($set.ContainsKey('TEMP') -or $set.ContainsKey('TMP'))){$tempDir=Join-Path $Directory 'tmp';[IO.Directory]::CreateDirectory($tempDir)|Out-Null;$set['TEMP']=$tempDir;$set['TMP']=$tempDir}
foreach($k in $set.Keys){[Environment]::SetEnvironmentVariable($k,$set[$k],'Process')}
$t0=Get-Date
$via='CreateProcess(breakaway)'
try{$id=[YaWindow]::LaunchInteractive($exeFull,[string[]]$Arguments,$Directory)}
catch{
  # Agent host job forbids breakaway (e.g. some CLI agents): fall back to WMI Win32_Process.Create, which is not a child of the Agent job.
  Write-Output ('BREAKAWAY_DENIED: '+$_.Exception.Message+' -> fallback WMI Win32_Process.Create')
  function Q([string]$s){if($s -match '[\s"]'){'"'+$s.Replace('"','\"')+'"'}else{$s}}
  $line=(@(Q $exeFull)+@($Arguments|ForEach-Object{Q $_})) -join ' '
  # ShowWindow=1 (SW_SHOWNORMAL): WMI default start info hides GUI main windows (R7: NX ran with only hidden windows).
  # Env passed as the full current process environment (already includes -Env overrides); no cmd.exe wrapper.
  $envList=@([Environment]::GetEnvironmentVariables('Process').GetEnumerator()|Where-Object{$_.Key -notmatch '^='}|ForEach-Object{$_.Key+'='+$_.Value})
  $si=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]1;EnvironmentVariables=[string[]]$envList}
  $r=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$line;CurrentDirectory=$Directory;ProcessStartupInformation=$si}
  if($r.ReturnValue -ne 0){Write-Output ('WMI_START_FAILED code='+$r.ReturnValue);exit 6}
  $id=[int]$r.ProcessId;$via='WMI(ShowWindow=1)'
}
Write-Output ('LAUNCHED pid='+$id+' via='+$via+' exe='+$exeFull)
$title='';$hwnd=0;$exited=$null;$dialogs=@()
if(-not ('NgxzDesk' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class NgxzDesk{[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);}'}
$interactive=([NgxzDesk]::FindWindow('Shell_TrayWnd',$null) -ne [IntPtr]::Zero)
$timed=Join-Path $PSScriptRoot '限时运行.ps1'
if(-not $interactive){Write-Output 'NOT_INTERACTIVE_DESKTOP: 本命令跑在隔离桌面（看不到用户桌面窗口）；窗口/弹窗检查改经 限时运行 -OnDesktop 在用户桌面上做。之后窗口相关脚本（YA查询、弹窗守护、连接软件.ps1 Connect/Run、YA插件\ya_link.ps1、show_ya.ps1）都用 适配器\限时运行.ps1 -OnDesktop -File <脚本> 跑。'}
$deadline=(Get-Date).AddSeconds($WaitSeconds)
while((Get-Date) -lt $deadline){
  $pr=Get-Process -Id $id -ErrorAction SilentlyContinue
  if(-not $pr){$exited=$true;break}
  if($interactive){
    $wd=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '弹窗守护.ps1') -TargetPid $id -Dismiss -Log (Join-Path $Directory 'dialogs.jsonl');$wd|Where-Object{$_ -match '^MODAL_DIALOG'}|ForEach-Object{$dialogs+=$_;Write-Output $_}
    if($pr.MainWindowHandle -ne 0 -and $pr.MainWindowTitle){$hwnd=[int64]$pr.MainWindowHandle;$title=$pr.MainWindowTitle;break}
  }else{
    $wd=& $timed -File (Join-Path $PSScriptRoot '弹窗守护.ps1') -TimeoutSec 40 -OnDesktop -ArgLine ('-TargetPid '+$id+' -Dismiss -Log "'+(Join-Path $Directory 'dialogs.jsonl')+'"');$wd|Where-Object{$_ -match '^MODAL_DIALOG'}|ForEach-Object{$dialogs+=$_;Write-Output $_}
    $q=& (Join-Path $PSScriptRoot 'YA查询.ps1') -TargetPid $id -TimeoutSec 30
    $qj=$null;try{$qj=(@($q)|Where-Object{$_ -match '^\{'}|Select-Object -Last 1)|ConvertFrom-Json}catch{}
    if($qj -and [int64]$qj.hwnd -ne 0 -and [string]$qj.title){$hwnd=[int64]$qj.hwnd;$title=[string]$qj.title;break}
  }
  Start-Sleep -Seconds 2
}
$kids=@();try{$kids=@(Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$id)|ForEach-Object{[ordered]@{pid=$_.ProcessId;name=$_.Name}})}catch{}
$rec=[ordered]@{schema=1;pid=$id;via=$via;interactive_desktop=$interactive;exe=$exeFull;arguments=$Arguments;env_keys=@($set.Keys);temp_dir=$tempDir;timed_run=$timedRun;directory=$Directory;started_local=$t0.ToString('o');seconds=[Math]::Round(((Get-Date)-$t0).TotalSeconds,1);main_window=$hwnd;title=$title;exited=[bool]$exited;children=$kids;modal_dialogs=$dialogs}
$out=Join-Path $Directory 'launch.json'
[IO.File]::WriteAllText($out,($rec|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
if($dialogs.Count){Write-Output ('MODAL_DIALOG_FAILPOINT: 启动期间出现 '+$dialogs.Count+' 个错误弹窗（已静默关闭并记录到 '+(Join-Path $Directory 'dialogs.jsonl')+'）。这是失败点：若弹窗涉及非本轮生成的 DLL/启动目录，说明软件自动加载了包外内容，改用官方环境变量/参数指向本轮空配置后重启；若是本轮桥接，先 接口探测.ps1 -Check 再按本机程序集重编。record='+$out);exit 7}
# 换新进程自动重绑 YA（2026-11-10 R10，软件无关）：本包登记的旧进程已退出、且是同一个可执行文件时，对新 PID 自动 ya_link prepare=1，面板从「已掉线」改为「已打开 · 待读回」；之后照常让新进程内桥接写 readback 再登记。
if($hwnd){
 try{
  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  $linkF=Join-Path (Join-Path (Get-YaPackageHudHome $pkg) 'io') 'link.json'
  if(Test-Path -LiteralPath $linkF){
   $old=Get-Content -LiteralPath $linkF -Raw -Encoding UTF8|ConvertFrom-Json
   $oldAlive=$false;try{$op=Get-Process -Id ([int]$old.pid) -ErrorAction Stop;$oldAlive=($op.StartTime.ToUniversalTime().Ticks.ToString() -ceq [string]$old.process_start)}catch{}
   $newExe='';try{$newExe=[string](Get-Process -Id $id -ErrorAction Stop).Path}catch{}
   if($old.state -in @('ok','opened') -and $old.soft -and $old.slot -and $old.exe -and -not $oldAlive -and [int]$old.pid -ne $id -and ([string]$old.exe -ieq $newExe -or [string]$old.exe -ieq $exeFull)){
    $rb=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'YA插件\ya_link.ps1') ('soft='+$old.soft) ('slot='+$old.slot) ('pid='+$id) 'prepare=1' 2>&1)
    Write-Output ('YA_REBIND: 旧登记 PID '+$old.pid+' 已退出，YA 已改绑新进程 '+$id+'（已打开 · 待读回）；让新进程内桥接按新挑战写 readback，再 ya_link 登记。'+((@($rb)|Where-Object{$_ -match '^(challenge|readback):'}) -join ' '))
   }
  }
 }catch{Write-Output ('YA_REBIND_SKIPPED: '+$_.Exception.Message)}
}
if($hwnd){Write-Output ('WINDOW_READY pid='+$id+' title="'+$title+'" ('+$rec.seconds+'s) record='+$out);Write-Output '下一步：确认窗口是正常主界面（不是错误对话框）→ 加载本包内桥接 → ya_link prepare/登记。';exit 0}
if($exited){Write-Output ('PROCESS_EXITED pid='+$id+' （可能是启动器转交给子进程或启动失败）children='+(($kids|ForEach-Object{$_.name+':'+$_.pid}) -join ',')+' record='+$out);exit 4}
Write-Output ('WINDOW_TIMEOUT pid='+$id+' 未在 '+$WaitSeconds+'s 内出现主窗口；进程保留，不杀不重启。检查是否卡在对话框/许可。record='+$out);exit 5