# 第一步先读 AGENTS.md「第 0 步」。限时运行（软件无关）：本轮**所有可执行程序**都经它跑——子进程标准输入已关闭（不会卡在等输入），到时结束整棵进程树，退出码 124 = TIMEOUT。
# 跑脚本：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -File <artifacts\脚本.ps1> [-TimeoutSec 60] [-ArgLine:"给脚本的参数原文"]
# 跑程序：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -Exe <install_dirs 内的命令行程序.exe> [-TimeoutSec 120] [-ArgLine:"程序参数原文"]
# 启动软件 GUI：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -File 适配器\启动软件.ps1 -TimeoutSec 300 -ArgLine:"-Exe <主程序.exe> -WaitSeconds 240 [-Env 名=值]"
#   （启动软件.ps1 不经本脚本直接调会拒绝；GUI 由它脱离本进程树启动，超时也不会被杀。不要用 -Exe 直接起 GUI 主程序。）
#   参数原文以 - 开头时务必用冒号写法 -ArgLine:"-Pid 123"，否则会被当成本脚本的参数。
# 规则：不要直接 & xxx.exe / Start-Process xxx.exe / cmd /c xxx.exe，越界审计把绕过限时运行的直接调用记为违规；也不要手写嵌套多行 powershell -Command "..."。
# -OnDesktop（配合 -File）：Agent 的命令若跑在隔离桌面（如某些 CLI Agent 的沙箱，看不到用户桌面上的软件窗口/弹窗/YA 面板），
#   就经 WMI 在用户交互桌面上跑该脚本（输出写回 artifacts\relay 再打印，同样限时）；本来就在交互桌面时等同普通运行。
#   窗口相关脚本（YA查询、弹窗守护、连接软件.ps1 Connect/Run、YA插件\ya_link.ps1、show_ya.ps1）在隔离桌面下都要这样跑。
# 每次运行记一行 工作区\artifacts\timed-runs.jsonl（开始/结束、PID、退出码），越界审计据此核对软件进程是否都经限时运行/启动软件启动。
param([string]$File,[string]$Exe,[ValidateRange(1,3600)][int]$TimeoutSec=60,[string]$ArgLine='',[switch]$OnDesktop)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
if([bool]$File -eq [bool]$Exe){Write-Output 'TIMED_BAD_ARGS: -File <脚本.ps1> 和 -Exe <程序.exe> 二选一';exit 2}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
# 快通道自验含读回后的挑战/登记/前台复核；外层 60s 会在 proof 完成前被掐掉，卡留 v=0。目标为 快连.ps1 且超时低于 300 秒时抬到 300。
if($File){ $fn=[IO.Path]::GetFileName($File); if($fn -ieq '快连.ps1' -and $TimeoutSec -lt 300){ Write-Output ('TIMEOUT_ADJUSTED: 快连/快通道自验至少 300 秒（调用方给了 '+[string]$TimeoutSec+'）。读回已成功后还要做挑战/登记/前台复核，60 秒会被掐掉并留下 v=0。'); $TimeoutSec=300 } }

function WsOf([string]$p){$data=Join-Path $p '运行数据';if(Test-Path -LiteralPath $data){return $data};if((Split-Path $p -Leaf) -eq '工作区'){return Split-Path $p -Parent};foreach($c in @((Join-Path $p 'ngxz-ya-ws'),(Join-Path (Split-Path $p -Parent) 'ngxz-ya-ws'))){if(Test-Path -LiteralPath (Join-Path $c '工作区')){return $c}};return $data}
$ws=WsOf $pkg
$runLog=Join-Path $ws 'artifacts\timed-runs.jsonl'
function Log($o){try{[IO.Directory]::CreateDirectory((Split-Path $runLog -Parent))|Out-Null;[IO.File]::AppendAllText($runLog,(($o|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))}catch{}}
$runId=[guid]::NewGuid().ToString('N').Substring(0,12)
if(-not ('NgxzDesk' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class NgxzDesk{[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);}'}
$interactive=([NgxzDesk]::FindWindow('Shell_TrayWnd',$null) -ne [IntPtr]::Zero)
if($OnDesktop -and $File -and -not $interactive){
  $f=[IO.Path]::GetFullPath($File);if(-not [IO.File]::Exists($f)){Write-Output ('SCRIPT_MISSING: '+$f);exit 2}
  $rd=Join-Path $ws 'artifacts\relay';[IO.Directory]::CreateDirectory($rd)|Out-Null
  $of=Join-Path $rd ($runId+'.out.txt');$cf=Join-Path $rd ($runId+'.code.txt')
  $cmd='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$ErrorActionPreference=''Continue'';$ProgressPreference=''SilentlyContinue'';$env:NGXZ_TIMED='''+$runId+''';& '''+$f.Replace("'","''")+''' '+$ArgLine+' *>&1|Out-File -LiteralPath '''+$of.Replace("'","''")+''' -Encoding utf8 -Width 4096;[IO.File]::WriteAllText('''+$cf.Replace("'","''")+''',[string]$LASTEXITCODE)'
  $b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  $line='"'+(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')+'" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand '+$b64
  $envList=@([Environment]::GetEnvironmentVariables('Process').GetEnumerator()|Where-Object{$_.Key -notmatch '^='}|ForEach-Object{$_.Key+'='+$_.Value})
  $si=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0;EnvironmentVariables=[string[]]$envList}
  $t0=Get-Date
  $r=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$line;CurrentDirectory=(Get-Location).ProviderPath;ProcessStartupInformation=$si}
  if($r.ReturnValue -ne 0){Write-Output ('DESKTOP_RELAY_FAILED code='+$r.ReturnValue);exit 6}
  $rp=[int]$r.ProcessId
  Log ([ordered]@{event='start';run=$runId;utc=[DateTime]::UtcNow.ToString('o');kind='file-desktop';target=$f;args=$ArgLine;timeout=$TimeoutSec;pid=$rp;parent=$PID})
  $t=$false;$dl=(Get-Date).AddSeconds($TimeoutSec)
  while(Get-Process -Id $rp -ErrorAction SilentlyContinue){if((Get-Date) -gt $dl){$t=$true;& taskkill.exe /PID $rp /T /F 2>&1|Out-Null;break};Start-Sleep -Milliseconds 300}
  Start-Sleep -Milliseconds 200
  if([IO.File]::Exists($of)){Write-Output ([IO.File]::ReadAllText($of,[Text.Encoding]::UTF8).TrimEnd())}
  $code=$(if($t){124}elseif([IO.File]::Exists($cf)){[int]([IO.File]::ReadAllText($cf).Trim())}else{1})
  Log ([ordered]@{event='end';run=$runId;utc=[DateTime]::UtcNow.ToString('o');kind='file-desktop';target=$f;pid=$rp;exit=$code;timed_out=$t;seconds=[Math]::Round(((Get-Date)-$t0).TotalSeconds,1)})
  if($t){Write-Output ('TIMEOUT after '+$TimeoutSec+'s (desktop relay): '+$f+' （进程树已结束；结果未知的写操作不要重发，先用只读动作对账）');exit 124}
  exit $code
}
$psi=New-Object Diagnostics.ProcessStartInfo
if($File){
  $f=[IO.Path]::GetFullPath($File)
  if(-not [IO.File]::Exists($f)){Write-Output ('SCRIPT_MISSING: '+$f);exit 2}
  $cmd='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$ErrorActionPreference=''Continue'';$ProgressPreference=''SilentlyContinue'';& '''+$f.Replace("'","''")+''' '+$ArgLine+';exit $LASTEXITCODE'
  $b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  $psi.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand '+$b64
  $kind='file';$target=$f
}else{
  $f=$Exe;if(-not [IO.Path]::IsPathRooted($f)){$w=Get-Command $f -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($w){$f=$w.Source}}
  $f=[IO.Path]::GetFullPath($f)
  if(-not [IO.File]::Exists($f)){Write-Output ('EXE_MISSING: '+$f);exit 2}
  $psi.FileName=$f;$psi.Arguments=$ArgLine
  $kind='exe';$target=$f
}
$psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.StandardOutputEncoding=[Text.Encoding]::UTF8;$psi.StandardErrorEncoding=[Text.Encoding]::UTF8
$psi.WorkingDirectory=(Get-Location).ProviderPath
$psi.EnvironmentVariables['NGXZ_TIMED']=$runId
$t0=Get-Date
$p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Close()
Log ([ordered]@{event='start';run=$runId;utc=[DateTime]::UtcNow.ToString('o');kind=$kind;target=$target;args=$ArgLine;timeout=$TimeoutSec;pid=$p.Id;parent=$PID})
$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
$t=$false
if(-not $p.WaitForExit($TimeoutSec*1000)){$t=$true;& taskkill.exe /PID $p.Id /T /F 2>&1|Out-Null;[void]$p.WaitForExit(5000)}
[void]$o.Wait(5000);[void]$e.Wait(5000)
if($o.IsCompleted -and $o.Result){Write-Output $o.Result.TrimEnd()}
if($e.IsCompleted -and $e.Result){$er=$e.Result
  if($er.StartsWith('#< CLIXML')){$er=(@([regex]::Matches($er,'<S S="Error">(.*?)</S>')|ForEach-Object{[Net.WebUtility]::HtmlDecode($_.Groups[1].Value).Replace('_x000D__x000A_',"`n")}) -join '')}
  if($er.Trim()){Write-Output ('STDERR: '+$er.TrimEnd())}}
$code=$(if($t){124}else{$p.ExitCode})
Log ([ordered]@{event='end';run=$runId;utc=[DateTime]::UtcNow.ToString('o');kind=$kind;target=$target;pid=$p.Id;exit=$code;timed_out=$t;seconds=[Math]::Round(((Get-Date)-$t0).TotalSeconds,1)})
if($t){Write-Output ('TIMEOUT after '+$TimeoutSec+'s: '+$target+' （进程树已结束；结果未知的写操作不要重发，先用只读动作对账）');exit 124}
exit $code
