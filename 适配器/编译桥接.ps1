# 第一步先读 AGENTS.md「第 0 步」。脚本链「编译桥接」段（软件无关）：用 Windows 自带 .NET Framework csc 把 Agent 写好的桥接源码编进本包/本轮目录。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\编译桥接.ps1 -Source <.cs,...> -Out <dll> [-References <dll,...>] [-Target library|exe] [-Platform x64|anycpu] [-Win32Resource <.res>] [-Resources <file,...>]
# 软件要求程序集内嵌签名/资源包时（以其官方文档为准），用 -Win32Resource / -Resources 传入安装目录或本包内的资源文件。
# 规则：-Source/-Out 必须在本包或本工作区（含 artifacts、连接教练\连接经验\<槽>）内；-References 只能来自 本机定位.json install_dirs、Windows 或 .NET 参考程序集。
# 桥接源码由 Agent 依据目标软件官方/合法开源文档自写；本包不附送任何软件专属接口。
# 硬闸：编译前先过 连接教练\来源闸.ps1 -Check（上网搜到的开源/官方方案要登记进 artifacts\sources.json），不合格退出码 5。
# 版本：每次编译记一行 artifacts\bridge-builds.jsonl（build 号、sha256），旁边写 <dll>.version.json；第 2 次起打印 RELOAD_REQUIRED。
#      -Versioned：输出成 <名>.v<build>.dll（旧版本被软件占用时用；别把多个版本放进软件会自动加载的目录）。
param([Parameter(Mandatory=$true)][string[]]$Source,[Parameter(Mandatory=$true)][string]$Out,[string[]]$References=@(),[ValidateSet('library','exe')][string]$Target='library',[ValidateSet('x64','anycpu','x86')][string]$Platform='x64',[string]$Win32Resource='',[string[]]$Resources=@(),[switch]$Versioned)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
function Norm([string]$x){[IO.Path]::GetFullPath($x).TrimEnd('\')}
$pkg=Norm (Join-Path $PSScriptRoot '..')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
function Under([string]$x,[string[]]$roots){$n=Norm $x;foreach($r in $roots){if($r -and $n.StartsWith((Norm $r)+'\',[StringComparison]::OrdinalIgnoreCase)){return $true}};return $false}
$locFile=@((Join-Path $ws '本机定位.json'),(Join-Path $pkg '本机定位.json'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
$inst=@();if($locFile){$inst=@((Get-Content -LiteralPath $locFile -Raw -Encoding UTF8|ConvertFrom-Json).install_dirs)}
$src=@($Source|ForEach-Object{$_ -split ','}|Where-Object{$_})
foreach($s in $src+@($Out)){if(-not (Under $s @($pkg,$ws))){Write-Output ('PATH_OUTSIDE_PACKAGE: '+$s);exit 2}}
$refs=@($References|ForEach-Object{$_ -split ','}|Where-Object{$_})
$refRoots=@($inst)+@($env:WINDIR,(Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies'))
foreach($r in $refs){if(-not ([IO.Path]::IsPathRooted($r))){continue};if(-not (Under $r $refRoots)){Write-Output ('REFERENCE_OUTSIDE_ALLOWED: '+$r+' （只允许 install_dirs / Windows / Reference Assemblies）');exit 2}}
$res=@($Resources|ForEach-Object{$_ -split ','}|Where-Object{$_})
foreach($r in @($res)+@($Win32Resource|Where-Object{$_})){if(-not (Under $r (@($inst)+@($pkg,$ws)))){Write-Output ('RESOURCE_OUTSIDE_ALLOWED: '+$r+' （只允许 install_dirs / 本包 / 工作区）');exit 2}}
$gate=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\来源闸.ps1') -Check);$gc=$LASTEXITCODE;$gate|ForEach-Object{Write-Output $_}
if($gc -ne 0){Write-Output 'BUILD_REFUSED: 来源闸未通过。先上网搜开源/官方连接方案并登记 sources.json，再编译。';exit 5}
$art=Join-Path $ws 'artifacts';[IO.Directory]::CreateDirectory($art)|Out-Null;$bl=Join-Path $art 'bridge-builds.jsonl'
$prev=@();if([IO.File]::Exists($bl)){$prev=@([IO.File]::ReadAllLines($bl,[Text.Encoding]::UTF8)|Where-Object{$_}|ForEach-Object{try{$_|ConvertFrom-Json}catch{}}|Where-Object{$_ -and [string]$_.out -ieq (Norm $Out)})}
$ver=$prev.Count+1
$outFile=Norm $Out;if($Versioned){$outFile=Join-Path (Split-Path $outFile -Parent) ([IO.Path]::GetFileNameWithoutExtension($outFile)+'.v'+$ver+[IO.Path]::GetExtension($outFile))}
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not [IO.File]::Exists($csc)){$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if(-not [IO.File]::Exists($csc)){Write-Output 'CSC_MISSING';exit 3}
[IO.Directory]::CreateDirectory((Split-Path (Norm $Out) -Parent))|Out-Null
$a=@('/nologo','/optimize+',('/target:'+$Target),('/platform:'+$Platform),('/out:'+$outFile))
foreach($r in $refs){$a+=('/reference:'+$r)}
if($Win32Resource){$a+=('/win32res:'+(Norm $Win32Resource))}
foreach($r in $res){$a+=('/resource:'+(Norm $r))}
$a+=@($src|ForEach-Object{Norm $_})
$log=$outFile+'.build.log'
& $csc @a 2>&1|Tee-Object -FilePath $log|Write-Output
$code=$LASTEXITCODE
if($code -ne 0){
  if((Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) -match 'CS0016|being used by another process|另一进程'){Write-Output 'BUILD_LOCKED: 输出文件正被软件加载占用。加 -Versioned 编成新文件名，或先按官方方式卸载桥接/退出软件。'}
  Write-Output ('BUILD_FAIL exit='+$code+' log='+$log);exit 1}
$h=(Get-FileHash -LiteralPath $outFile).Hash
$last=$prev|Select-Object -Last 1;$changed=[bool]($last -and [string]$last.sha256 -ne $h)
$rec=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');out=(Norm $Out);file=$outFile;build=$ver;sha256=$h;changed_from_previous=$changed}
[IO.File]::AppendAllText($bl,(($rec|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($outFile+'.version.json',($rec|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output ('BUILD_OK out='+$outFile+' build=v'+$ver+' sha256='+$h+' log='+$log)
Write-Output ('  桥接里请把 bridge_build='+$ver+' / bridge_sha256 前 12 位 '+$h.Substring(0,12)+' 放进 QUERY_SESSION 回复，好核对软件里跑的是哪一版。')
if($ver -gt 1){Write-Output ('RELOAD_REQUIRED: 这是同一输出第 '+$ver+' 次编译'+$(if($changed){'（内容已变）'}else{''})+'。软件里已加载的旧桥接不会自动换成新文件：按软件官方方式卸载/重载桥接，或退出软件后用 适配器\启动软件.ps1 重启；重连后用 适配器\调用桥接.ps1 QUERY_SESSION 核对 bridge_build=v'+$ver+'。没重载就测 = 测的还是旧版本。')}
exit 0