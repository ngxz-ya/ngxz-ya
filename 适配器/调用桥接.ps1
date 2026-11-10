# 第一步先读 AGENTS.md「第 0 步」。调用桥接（软件无关）：向目标进程内桥接的命名管道发一条请求 → 限时等一条回复 → 打印回复 JSON。读回也用本脚本发只读动作。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\调用桥接.ps1 -Pipe ngxz-ya-<32位hex> -TargetPid <软件PID> -Action <动作名>
#        [-Body '{"键":"值"}' 或 -BodyFile <artifacts\请求.json>] [-Protocol ngxz-ya/session-probe/1] [-TimeoutSec 30] [-Out <artifacts\回复.json>]
# 协议见 YA插件\说明.md：请求带 protocol/action/request（本脚本自动生成 32 位 request），回复须原样回传这三项。
# 超时/写入未知 = 结果未知：不要重发写操作，先用只读动作对账。退出码 0=有回复，5=通道错误/超时，2=参数错误。
param([Parameter(Mandatory=$true)][string]$Pipe,[Parameter(Mandatory=$true)][int]$TargetPid,[Parameter(Mandatory=$true)][string]$Action,
  [string]$Body,[string]$BodyFile,[string]$Protocol='ngxz-ya/session-probe/1',[ValidateRange(1,1800)][int]$TimeoutSec=30,[string]$Out)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if(-not ('YaEvidence' -as [type])){Add-Type -AssemblyName System.Web.Extensions;Add-Type -Path (Join-Path $pkg 'YA插件\连接证据.cs') -ReferencedAssemblies System.Web.Extensions}
Add-Type -AssemblyName System.Web.Extensions
$ser=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$msg=New-Object 'System.Collections.Generic.Dictionary[string,object]'
try{
  $txt=$null
  if($BodyFile){$txt=[IO.File]::ReadAllText([IO.Path]::GetFullPath($BodyFile),[Text.Encoding]::UTF8)}elseif($Body){$txt=$Body}
  if($txt){$d=$ser.DeserializeObject($txt);if($d -isnot [Collections.Generic.Dictionary[string,object]]){throw 'BODY_NOT_OBJECT'};foreach($k in $d.Keys){$msg[$k]=$d[$k]}}
}catch{Write-Output ('{"status":"BAD_BODY","error":'+$ser.Serialize([string]$_.Exception.Message)+'}');exit 2}
$msg['protocol']=$Protocol;$msg['action']=$Action;$msg['request']=[guid]::NewGuid().ToString('N')
$sw=[Diagnostics.Stopwatch]::StartNew()
try{
  $proc=Get-Process -Id $TargetPid -ErrorAction Stop
  $start=$proc.StartTime.ToUniversalTime().Ticks.ToString()
  $r=[YaEvidence]::SendMessage($Pipe,$TargetPid,$start,$msg,$TimeoutSec*1000)
}catch{
  $m=$_.Exception;while($m.InnerException){$m=$m.InnerException}
  $res=[ordered]@{status='CHANNEL_ERROR';action=$Action;request=$msg['request'];ms=$sw.ElapsedMilliseconds;error=$m.Message;next='超时或写入未知=结果未知：不要重发写操作；先用只读动作对账，或用 适配器\弹窗守护.ps1 查是否有弹窗挡住'}
  $j=$res|ConvertTo-Json -Compress
  if($Out){[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),$j,(New-Object Text.UTF8Encoding $false))}
  Write-Output $j;exit 5
}
$j=$ser.Serialize($r)
if($Out){[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),$j,(New-Object Text.UTF8Encoding $false))}
Write-Output $j
exit 0