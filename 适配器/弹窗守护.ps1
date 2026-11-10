# 第一步先读 AGENTS.md「第 0 步」。通用「弹窗守护 / 静默自愈」（软件无关）：盯住目标软件进程（含子进程）的模态对话框，记录文字、关闭（发 WM_CLOSE，不按键不点鼠标），
# 文字像「找不到方法 / MissingMethod / 初始化错误 / TypeLoad / could not load」时，调用 Agent 写好的重建/重启脚本做有限次数自愈；超过上限如实报告 HEAL_FAILED。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\弹窗守护.ps1 -TargetPid <PID> [-Seconds 120] [-Dismiss] [-RetryScript <重建并重启.ps1>] [-MaxRetries 2]
#   许可类弹窗（标题或正文含 许可/License/授权/EULA/激活/Activation）一律只记录、不关闭、不自愈，即使给了 -Dismiss；记 license_dialog=true，算失败点上报，交用户处理。
#   -Seconds 0 = 只查一次。记录：工作区根\artifacts\dialogs.jsonl。每个弹窗都算一个失败点，必须写进报告。
# 退出码：0 无弹窗或已自愈(HEALED)；7 有弹窗（已记录/关闭），未自愈；8 自愈到上限仍失败。
param([Parameter(Mandatory=$true)][int]$TargetPid,[int]$Seconds=0,[switch]$Dismiss,[string]$RetryScript,[ValidateRange(0,5)][int]$MaxRetries=2,[string]$HealPattern='(?i)MissingMethod|找不到方法|初始化错误|TypeLoad|could not load|未能加载|EntryPoint|BadImageFormat',[string]$Log,[string]$LicensePattern='(?i)许可|License|授权|EULA|激活|Activation')
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
if(-not $Log){$Log=Join-Path $ws 'artifacts\dialogs.jsonl'}
[IO.Directory]::CreateDirectory((Split-Path $Log -Parent))|Out-Null
if(-not ('YaDialogScan' -as [type])){
Add-Type -TypeDefinition @"
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
public static class YaDialogScan{
 delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p,EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static List<string[]> Scan(int[] pids){
  var set=new HashSet<uint>();foreach(int p in pids)set.Add((uint)p);
  var r=new List<string[]>();
  EnumWindows(delegate(IntPtr h,IntPtr l){uint pid;GetWindowThreadProcessId(h,out pid);
   if(!set.Contains(pid)||!IsWindowVisible(h))return true;
   var c=new StringBuilder(256);GetClassName(h,c,256);if(c.ToString()!="#32770")return true;
   var t=new StringBuilder(512);GetWindowText(h,t,512);var body=new StringBuilder();
   EnumChildWindows(h,delegate(IntPtr ch,IntPtr l2){var s=new StringBuilder(2048);GetWindowText(ch,s,2048);if(s.Length>0){body.Append(s.ToString()).Append(" | ");}return true;},IntPtr.Zero);
   r.Add(new string[]{h.ToInt64().ToString(),pid.ToString(),t.ToString(),body.ToString()});return true;},IntPtr.Zero);
  return r;}
}
"@
}
function Tree([int]$root){$ids=@($root);try{$all=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId);$q=@($root);while($q.Count){$n=@();foreach($x in $q){$n+=@($all|Where-Object{$_.ParentProcessId -eq $x}|ForEach-Object{[int]$_.ProcessId})};$n=@($n|Where-Object{$ids -notcontains $_});$ids+=$n;$q=$n}}catch{};return [int[]]$ids}
$deadline=(Get-Date).AddSeconds([Math]::Max(0,$Seconds));$seen=@{};$found=0;$retries=0;$healed=$false
do{
  $alive=[bool](Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)
  if($alive){
    foreach($d in [YaDialogScan]::Scan((Tree $TargetPid))){
      $key=$d[0]+'|'+$d[2]+'|'+$d[3];if($seen.ContainsKey($key)){continue};$seen[$key]=1;$found++
      $rec=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');target_pid=$TargetPid;pid=[int]$d[1];hwnd=[int64]$d[0];title=$d[2];text=$d[3];dismissed=$false;heal='';license_dialog=$false}
      $lic=(($d[2]+' '+$d[3]) -match $LicensePattern);$rec.license_dialog=$lic
      if($Dismiss -and -not $lic){[void][YaDialogScan]::PostMessage([IntPtr][int64]$d[0],0x0010,[IntPtr]::Zero,[IntPtr]::Zero);$rec.dismissed=$true}
      Write-Output ('MODAL_DIALOG pid='+$d[1]+' title="'+$d[2]+'" text="'+$d[3]+'"'+$(if($lic){' -> 许可类弹窗：只记录不关闭，算失败点，交用户处理'}elseif($Dismiss){' -> 已关闭(WM_CLOSE)'}else{''}))
      if($RetryScript -and -not $lic -and (($d[2]+' '+$d[3]) -match $HealPattern)){
        if($retries -lt $MaxRetries){$retries++;Write-Output ('SELF_HEAL attempt '+$retries+'/'+$MaxRetries+': '+$RetryScript)
          & powershell -NoProfile -ExecutionPolicy Bypass -File $RetryScript -DialogText ($d[2]+' '+$d[3])
          $rc=$LASTEXITCODE;$rec.heal=('attempt '+$retries+' exit='+$rc);if($rc -eq 0){$healed=$true}else{$healed=$false}
        }else{$rec.heal='cap reached';$healed=$false}
      }
      [IO.File]::AppendAllText($Log,(($rec|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    }
  }
  if($Seconds -le 0 -or -not $alive){break}
  Start-Sleep -Seconds 2
}while((Get-Date) -lt $deadline)
if($found -eq 0){Write-Output 'NO_DIALOG';exit 0}
if($healed){Write-Output ('HEALED after '+$retries+' attempt(s); dialogs='+$found+' log='+$Log+' （弹窗仍算失败点，须写进报告）');exit 0}
if($RetryScript -and $retries -ge $MaxRetries){Write-Output ('HEAL_FAILED: 自愈 '+$retries+' 次仍有弹窗，停止重试，如实报告。log='+$Log);exit 8}
Write-Output ('DIALOGS='+$found+' log='+$Log+' 提示：弹窗里出现「找不到方法/初始化错误」且涉及非本轮生成的 DLL/目录，说明软件启动时自动加载了包外内容——用官方环境变量/参数指向本轮空配置；若是本轮桥接，先跑 接口探测.ps1 -Check 再按本机程序集重编。')
exit 7