# 第一步先读 AGENTS.md「第 0 步」。脚本链第 0 段：任何 Agent 一律使用桌面固定路径 ngxz-ya（特殊文件夹 DesktopDirectory\ngxz-ya）。
# 只检查这一条路径：已有包就用，没有才把本包复制到这里。不列举桌面其他内容。包根即工作区，不再生成 ngxz-ya-ws / ngxz-ya-main。
# 用法（一般由 一键连接.ps1 / 启动.ps1 自动调用）：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\落位.ps1 -Package <包根>
param([Parameter(Mandatory=$true)][string]$Package,[string]$StartDir)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
function Norm([string]$x){[IO.Path]::GetFullPath($x).TrimEnd('\' )}
$pkg=Norm $Package
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
$target=Norm (Get-YaDesktopPackageRoot)
if($pkg -ieq $target){
  [ordered]@{moved=$false;package=$pkg;reason='already-desktop'}|ConvertTo-Json -Compress
  exit 0
}
if(Test-YaPackageTree $target){
  Write-Output ('USE_EXISTING_DESKTOP_PACKAGE: 桌面已有 '+$target+' ，本轮只用这一固定路径，不另建、不覆盖。')
  [ordered]@{moved=$false;package=$target;reason='use-existing'}|ConvertTo-Json -Compress
  exit 0
}
if(Test-Path -LiteralPath $target){throw ('TARGET_NOT_PACKAGE: '+$target+' 已存在且不是本包，拒绝覆盖（只检查这一固定路径，不列举桌面其他内容）')}
$tmp=Norm $env:TEMP
$packer=Join-Path $pkg '准备隔离包.ps1'
$placed=$false
if([IO.File]::Exists($packer) -and [IO.File]::Exists((Join-Path $pkg '发布允许清单.json'))){
  $packOut=& powershell -NoProfile -ExecutionPolicy Bypass -File $packer -Destination $target -Profile TestCopy
  if($LASTEXITCODE -eq 0){$placed=$true}else{Write-Output ('RELOCATE_PACK_FALLBACK: 准备隔离包未成功，改复制本包文件。'+(@($packOut)|Select-Object -Last 3) -join ' ')}
}
if(-not $placed){
  [IO.Directory]::CreateDirectory($target)|Out-Null
  Get-ChildItem -LiteralPath $pkg -Force | Where-Object { $_.Name -notin @('.git','运行数据') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $target $_.Name) -Recurse -Force
  }
}
$originTop=$pkg
if($tmp -and $pkg.StartsWith($tmp+'\',[StringComparison]::OrdinalIgnoreCase)){$originTop=Join-Path $tmp ($pkg.Substring($tmp.Length+1).Split('\')[0])}
[IO.File]::WriteAllText((Join-Path $target '下载来源.json'),([ordered]@{schema=1;origin_package=$pkg;origin_top=$originTop;start_dir=$StartDir;relocated_utc=[DateTime]::UtcNow.ToString('o');rule='只允许本包自己的下载位置；只检查桌面固定路径 ngxz-ya，不列举桌面其他文件'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
Write-Output ('RELOCATED: 本包已放到桌面固定路径 '+$target+' ；之后只在该目录工作，包根即工作区。')
[ordered]@{moved=$true;package=$target}|ConvertTo-Json -Compress
exit 0