# 第一步先读 AGENTS.md「第 0 步」。限时运行（软件无关）：子进程跑一个 .ps1，标准输入已关闭（不会卡在等输入），到时结束整棵进程树，退出码 124 = TIMEOUT。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\限时运行.ps1 -File <artifacts\脚本.ps1> [-TimeoutSec 60] [-ArgLine:"给脚本的参数原文"]
#   参数原文以 - 开头时务必用冒号写法 -ArgLine:"-Pid 123"，否则会被当成本脚本的参数。
# 规则：不要手写嵌套多行 powershell -Command "..."（引号/换行一断，内层会永远等输入）；多行逻辑写成 artifacts\*.ps1，再用本脚本限时运行。
param([Parameter(Mandatory=$true)][string]$File,[ValidateRange(1,3600)][int]$TimeoutSec=60,[string]$ArgLine='')
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$f=[IO.Path]::GetFullPath($File)
if(-not [IO.File]::Exists($f)){Write-Output ('SCRIPT_MISSING: '+$f);exit 2}
$cmd='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$ErrorActionPreference=''Continue'';$ProgressPreference=''SilentlyContinue'';& '''+$f.Replace("'","''")+''' '+$ArgLine+';exit $LASTEXITCODE'
$b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand '+$b64
$psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.StandardOutputEncoding=[Text.Encoding]::UTF8;$psi.StandardErrorEncoding=[Text.Encoding]::UTF8
$psi.WorkingDirectory=(Get-Location).ProviderPath
$p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Close()
$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
$t=$false
if(-not $p.WaitForExit($TimeoutSec*1000)){$t=$true;& taskkill.exe /PID $p.Id /T /F 2>&1|Out-Null;[void]$p.WaitForExit(5000)}
[void]$o.Wait(5000);[void]$e.Wait(5000)
if($o.IsCompleted -and $o.Result){Write-Output $o.Result.TrimEnd()}
if($e.IsCompleted -and $e.Result){$er=$e.Result
  if($er.StartsWith('#< CLIXML')){$er=(@([regex]::Matches($er,'<S S="Error">(.*?)</S>')|ForEach-Object{[Net.WebUtility]::HtmlDecode($_.Groups[1].Value).Replace('_x000D__x000A_',"`n")}) -join '')}
  if($er.Trim()){Write-Output ('STDERR: '+$er.TrimEnd())}}
if($t){Write-Output ('TIMEOUT after '+$TimeoutSec+'s: '+$f+' （进程树已结束；结果未知的写操作不要重发，先用只读动作对账）');exit 124}
exit $p.ExitCode