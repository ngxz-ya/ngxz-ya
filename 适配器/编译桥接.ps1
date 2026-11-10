# 第一步先读 AGENTS.md「第 0 步」。脚本链「编译桥接」段（软件无关）：用 Windows 自带 .NET Framework csc 把 Agent 写好的桥接源码编进本包/本轮目录。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\编译桥接.ps1 -Source <.cs,...> -Out <dll> [-References <dll,...>] [-Target library|exe] [-Platform x64|anycpu] [-Win32Resource <.res>] [-Resources <file,...>]
# 软件要求程序集内嵌签名/资源包时（以其官方文档为准），用 -Win32Resource / -Resources 传入安装目录或本包内的资源文件。
# 规则：-Source/-Out 必须在本包或本工作区（含 artifacts、连接教练\连接经验\<槽>）内；-References 只能来自 本机定位.json install_dirs、Windows 或 .NET 参考程序集。
# 桥接源码由 Agent 依据目标软件官方/合法开源文档自写；本包不附送任何软件专属接口。
param([Parameter(Mandatory=$true)][string[]]$Source,[Parameter(Mandatory=$true)][string]$Out,[string[]]$References=@(),[ValidateSet('library','exe')][string]$Target='library',[ValidateSet('x64','anycpu','x86')][string]$Platform='x64',[string]$Win32Resource='',[string[]]$Resources=@())
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
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not [IO.File]::Exists($csc)){$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if(-not [IO.File]::Exists($csc)){Write-Output 'CSC_MISSING';exit 3}
[IO.Directory]::CreateDirectory((Split-Path (Norm $Out) -Parent))|Out-Null
$a=@('/nologo','/optimize+',('/target:'+$Target),('/platform:'+$Platform),('/out:'+(Norm $Out)))
foreach($r in $refs){$a+=('/reference:'+$r)}
if($Win32Resource){$a+=('/win32res:'+(Norm $Win32Resource))}
foreach($r in $res){$a+=('/resource:'+(Norm $r))}
$a+=@($src|ForEach-Object{Norm $_})
$log=(Norm $Out)+'.build.log'
& $csc @a 2>&1|Tee-Object -FilePath $log|Write-Output
$code=$LASTEXITCODE
if($code -ne 0){Write-Output ('BUILD_FAIL exit='+$code+' log='+$log);exit 1}
$h=(Get-FileHash -LiteralPath (Norm $Out)).Hash
Write-Output ('BUILD_OK out='+(Norm $Out)+' sha256='+$h+' log='+$log)
exit 0