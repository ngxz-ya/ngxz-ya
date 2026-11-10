# 第一步先读 AGENTS.md「第 0 步」。YA查询（软件无关）：限时查目标进程主窗口是否可见可用（YaWindow.Find/Title/Ready），不会卡死。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\YA查询.ps1 -TargetPid <软件PID> [-TimeoutSec 15]
# 输出一行 JSON：pid / hwnd / title / ready。Agent 命令跑在隔离桌面时自动经 限时运行 -OnDesktop 到用户交互桌面上查。退出码 0=ready，1=窗口不可用，124=超时（窗口卡住或被弹窗挡住，先跑弹窗守护）。
param([Parameter(Mandatory=$true)][int]$TargetPid,[ValidateRange(1,600)][int]$TimeoutSec=15,[switch]$Inner)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
if(-not $Inner){
  & (Join-Path $PSScriptRoot '限时运行.ps1') -File $PSCommandPath -TimeoutSec $TimeoutSec -ArgLine ('-TargetPid '+$TargetPid+' -Inner') -OnDesktop
  exit $LASTEXITCODE
}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
$h=[YaWindow]::Find($TargetPid);$t='';$r=$false
if($h -ne [IntPtr]::Zero){$t=[YaWindow]::Title($h);$r=[YaWindow]::Ready($TargetPid)}
[ordered]@{pid=$TargetPid;hwnd=[int64]$h;title=$t;ready=$r}|ConvertTo-Json -Compress
if($r){exit 0}else{exit 1}