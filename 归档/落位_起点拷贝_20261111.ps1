# 归档（2026-11-11）：桌面单一文件夹改革前的副本，供对照。现行脚本改为包根即工作区，不再生成 ngxz-ya-ws / 二次拷贝。
# 第一步先读 AGENTS.md「第 0 步」。本脚本是脚本链第 0 段：包在 %TEMP% 时把本包复制到本会话起点目录，之后只在那里工作。
# 用法（一般由 一键连接.ps1 / 启动.ps1 自动调用）：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\落位.ps1 -Package <包根> -StartDir <起点目录>
# 只复制本包自己的文件；不读取 %TEMP% 中任何其他文件，不列举任何用户目录。
param([Parameter(Mandatory=$true)][string]$Package,[string]$StartDir)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
function Norm([string]$x){[IO.Path]::GetFullPath($x).TrimEnd('\')}
$pkg=Norm $Package
$tmp=Norm $env:TEMP
if(-not $pkg.StartsWith($tmp+'\',[StringComparison]::OrdinalIgnoreCase)){
  [ordered]@{moved=$false;package=$pkg}|ConvertTo-Json -Compress;exit 0
}
if(-not $StartDir){$StartDir=(Get-Location).ProviderPath}
$sd=Norm $StartDir
if($sd -ieq $tmp -or $sd.StartsWith($tmp+'\',[StringComparison]::OrdinalIgnoreCase)){
  Write-Output 'STARTDIR_REQUIRED: 本包在 %TEMP%。请加 -StartDir "<本会话起点目录，即 Agent 的 cwd>" 重跑；落位后只在起点目录工作。'
  exit 10
}
if(-not (Test-Path -LiteralPath $sd -PathType Container)){throw ('STARTDIR_MISSING: '+$sd)}
$target=Join-Path $sd 'ngxz-ya-main'
if((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath (Join-Path $target 'AGENTS.md'))){throw ('TARGET_NOT_PACKAGE: '+$target+' 已存在且不是本包，拒绝覆盖')}
[IO.Directory]::CreateDirectory($target)|Out-Null
Copy-Item -Path (Join-Path $pkg '*') -Destination $target -Recurse -Force
$rel=$pkg.Substring($tmp.Length+1);$top=Join-Path $tmp ($rel.Split('\')[0])
[IO.File]::WriteAllText((Join-Path $target '下载来源.json'),([ordered]@{schema=1;origin_package=$pkg;origin_top=$top;start_dir=$sd;relocated_utc=[DateTime]::UtcNow.ToString('o');rule='只允许本包自己的下载位置；%TEMP% 其他文件不得读取'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
Write-Output ('RELOCATED: 本包已复制到 '+$target+' ；之后只在该目录工作（%TEMP% 中的下载副本不再使用）。')
[ordered]@{moved=$true;package=$target}|ConvertTo-Json -Compress
exit 0