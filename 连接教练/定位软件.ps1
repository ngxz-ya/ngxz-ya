# 本机定位（第 0 步唯一允许的本机探测）：只按注册表卸载项 / App Paths / 环境变量 / Program Files 两级厂商目录
# 定位用户点名的软件。不读用户主目录、桌面、文档、下载、其他盘符根，不递归扫描任何目录。
# 结果写入本包根 本机定位.json；之后所有步骤只允许使用其中 install_dirs。
param([Parameter(Mandatory=$true)][string]$Software)
$ErrorActionPreference='Stop'
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$name=$Software.Trim()
if(-not $name -or $name.Length -gt 64){throw 'SOFTWARE_NAME_REQUIRED'}
$rx=New-Object regex ('(?i)(^|[^a-z0-9])'+[regex]::Escape($name)+'([^a-z0-9]|$)')
$hits=New-Object System.Collections.Generic.List[object]
$registered=New-Object System.Collections.Generic.List[object]
function Add-Hit([string]$src,[string]$label,[string]$dir,[string]$ver,[string]$pub){
  if(-not $dir){return}
  $d=$dir.Trim().Trim('"')
  if($d -match '^(.+?\.exe)'){$d=Split-Path $Matches[1] -Parent}
  try{$d=[IO.Path]::GetFullPath($d).TrimEnd('\')}catch{return}
  if($d.Length -le 3 -or -not [IO.Directory]::Exists($d)){return}
  $hits.Add([ordered]@{source=$src;name=$label;dir=$d;version=$ver;publisher=$pub})
}
# 1) 卸载注册项
foreach($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
  if(-not (Test-Path $k)){continue}
  foreach($s in @(Get-ChildItem $k -ErrorAction SilentlyContinue)){
    $p=Get-ItemProperty $s.PSPath -ErrorAction SilentlyContinue
    if(-not $p -or -not $p.DisplayName -or -not $rx.IsMatch([string]$p.DisplayName)){continue}
    $registered.Add([ordered]@{name=[string]$p.DisplayName;version=[string]$p.DisplayVersion;publisher=[string]$p.Publisher})
    $dir=[string]$p.InstallLocation
    if(-not $dir -and $p.DisplayIcon){$dir=[string]$p.DisplayIcon}
    Add-Hit 'uninstall' ([string]$p.DisplayName) $dir ([string]$p.DisplayVersion) ([string]$p.Publisher)
  }
}
# 2) App Paths
foreach($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths')){
  if(-not (Test-Path $k)){continue}
  foreach($s in @(Get-ChildItem $k -ErrorAction SilentlyContinue)){
    $p=Get-ItemProperty $s.PSPath -ErrorAction SilentlyContinue
    $exe=[string]$p.'(default)'
    if($rx.IsMatch($s.PSChildName) -or $rx.IsMatch($exe)){
      $dir=[string]$p.Path; if(-not $dir){$dir=$exe}
      Add-Hit 'app_paths' $s.PSChildName $dir '' ''
    }
  }
}
# 3) 环境变量（只看值本身，不顺着去列目录）
foreach($scope in @('Machine','User','Process')){
  $vars=[Environment]::GetEnvironmentVariables($scope)
  foreach($key in @($vars.Keys)){
    foreach($v in ([string]$vars[$key]).Split(';')){
      $v=$v.Trim()
      if($v -match '^[A-Za-z]:\\' -and ($rx.IsMatch($v) -or $rx.IsMatch([string]$key))){Add-Hit ('env:'+$key) ([string]$key) $v '' ''}
    }
  }
}
# 4) Program Files 两级：厂商目录名 / 厂商下一级产品目录名（不递归）
$pfRoots=@($env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramW6432)|Where-Object{$_ -and [IO.Directory]::Exists($_)}|ForEach-Object{[IO.Path]::GetFullPath($_).TrimEnd('\')}|Select-Object -Unique
foreach($root in $pfRoots){
  foreach($vendor in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)){
    if($rx.IsMatch($vendor.Name)){Add-Hit 'program_files' $vendor.Name $vendor.FullName '' ''}
    foreach($prod in @(Get-ChildItem -LiteralPath $vendor.FullName -Directory -ErrorAction SilentlyContinue)){
      if($rx.IsMatch($prod.Name)){Add-Hit 'program_files' ($vendor.Name+'\'+$prod.Name) $prod.FullName '' ''}
    }
  }
}
# 去重并折叠嵌套目录：保留最外层安装目录
$dirs=@($hits|ForEach-Object{$_.dir}|Select-Object -Unique|Sort-Object Length)
$install=New-Object System.Collections.Generic.List[string]
foreach($d in $dirs){
  if($pfRoots -contains $d){continue}
  $inside=$false
  foreach($k in $install){if($d.StartsWith($k+'\',[StringComparison]::OrdinalIgnoreCase)){$inside=$true;break}}
  if(-not $inside){$install.Add($d)}
}
$running=@(Get-Process -ErrorAction SilentlyContinue|ForEach-Object{
  $path=$null;try{$path=$_.Path}catch{}
  if($path){foreach($k in $install){if($path.StartsWith($k+'\',[StringComparison]::OrdinalIgnoreCase)){[ordered]@{pid=$_.Id;name=$_.ProcessName;path=$path};break}}}
})
$status=if($install.Count){'FOUND'}else{'NOT_FOUND'}
$result=[ordered]@{
  schema=1;status=$status;software=$name;generated_utc=[DateTime]::UtcNow.ToString('o')
  package=$pkg;start_dir=(Split-Path $pkg -Parent)
  install_dirs=[object[]]$install.ToArray();registered=[object[]]$registered.ToArray();candidates=[object[]]$hits.ToArray();running=[object[]]$running
  methods=@('uninstall_registry','app_paths','environment_values','program_files_two_levels')
  rule='之后只允许访问：本包、起点目录、install_dirs、本包管理的 YALink/YAHud 状态。其余本机路径一律禁止；每个大步骤前运行 连接教练\越界路径审计.ps1。'
}
$out=Join-Path $pkg '本机定位.json'
[IO.File]::WriteAllText($out,(ConvertTo-Json -InputObject $result -Depth 6),[Text.UTF8Encoding]::new($true))
ConvertTo-Json -InputObject $result -Depth 6
if($status -ne 'FOUND'){Write-Output 'NOT_FOUND: 未按允许方式找到该软件。停止并向用户报告，不得自行扩大搜索。';exit 3}
Write-Output ('LOCATED: '+($install -join ' | ')+' -> '+$out)
exit 0
