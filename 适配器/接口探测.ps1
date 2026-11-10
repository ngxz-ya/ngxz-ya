# 第一步先读 AGENTS.md「第 0 步」。通用「接口探测」（软件无关）：写任何桥接调用前，先列出本机已装版本程序集里真实存在的类型/方法/属性，写成能力文件；只准用里面有的成员。
# 列能力：powershell -NoProfile -ExecutionPolicy Bypass -File 适配器\接口探测.ps1 -Assemblies "<install_dirs 内的 .dll>,<...>" [-TypeFilter 正则] [-Out 能力文件.json]
# 核对成员：... -Assemblies <同上> -Check "命名空间.类型::成员,命名空间.类型::成员"   缺失则退出码 1，并列出同类型里相近的可用成员（含基类）。
# 只读：独立进程反射加载，不启动软件。程序集必须位于 本机定位.json install_dirs 内。属性 X 会以 X 和 get_X 两种写法都可核对。
param([Parameter(Mandatory=$true)][string[]]$Assemblies,[string]$TypeFilter='.',[string]$Out,[string[]]$Check)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
$locFile=@((Join-Path $ws '本机定位.json'),(Join-Path $pkg '本机定位.json'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $locFile){Write-Output 'LOCATE_REQUIRED: 先运行 一键连接.ps1';exit 3}
$inst=@((Get-Content -LiteralPath $locFile -Raw -Encoding UTF8|ConvertFrom-Json).install_dirs|ForEach-Object{[IO.Path]::GetFullPath($_).TrimEnd('\')})
$asm=@($Assemblies|ForEach-Object{$_ -split ','}|Where-Object{$_}|ForEach-Object{[IO.Path]::GetFullPath($_.Trim().Trim('"'))})
foreach($a in $asm){
  if(-not @($inst|Where-Object{$a.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){Write-Output ('ASSEMBLY_OUTSIDE_INSTALL_DIRS: '+$a);exit 2}
  if(-not [IO.File]::Exists($a)){Write-Output ('ASSEMBLY_MISSING: '+$a);exit 3}
}
if(-not $Out){$Out=Join-Path $ws ('artifacts\capabilities-'+(Get-Date).ToString('yyyyMMdd-HHmmss')+'.json')}
$Out=[IO.Path]::GetFullPath($Out);[IO.Directory]::CreateDirectory((Split-Path $Out -Parent))|Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '接口探测_子进程.ps1') -asmList $asm -filter $TypeFilter -out $Out
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($Out)){Write-Output ('PROBE_FAIL exit='+$LASTEXITCODE);exit 4}
$cap=Get-Content -LiteralPath $Out -Raw -Encoding UTF8|ConvertFrom-Json
foreach($a in @($cap.assemblies)){Write-Output ('PROBED '+(Split-Path $a.file -Leaf)+' v'+$a.version+' file='+$a.file_version+' types='+@($a.types).Count+' load_errors='+@($a.load_errors).Count)}
Write-Output ('CAPABILITIES: '+$Out+'  （写调用前先查这里；没有的成员不得使用，编译也必须引用这些本机程序集）')
if($Check){
  $all=@{};foreach($a in @($cap.assemblies)){foreach($t in @($a.types)){$all[$t.type]=$t}}
  function Members($tn){$m=@();$seen=0;while($tn -and $all.ContainsKey($tn) -and $seen -lt 12){$t=$all[$tn];$m+=@($t.methods|ForEach-Object{($_ -split '\(')[0]});$m+=@($t.properties);$m+=@($t.properties|ForEach-Object{'get_'+$_});$tn=$t.base;$seen++};return @($m|Select-Object -Unique)}
  $miss=0
  foreach($c in @($Check|ForEach-Object{$_ -split ','}|Where-Object{$_})){
    if($c.Trim() -notmatch '^(.+)::(.+)$'){Write-Output ('CHECK_FORMAT: '+$c);$miss++;continue}
    $tn=$matches[1];$mn=$matches[2]
    if(-not $all.ContainsKey($tn)){Write-Output ('MISSING_TYPE '+$tn+'（本机版本没有这个类型）');$miss++;continue}
    $ms=Members $tn
    if($ms -ccontains $mn){Write-Output ('OK '+$c)}else{$miss++;$k=$mn -replace '^get_','';$near=@($ms|Where-Object{$_ -match [regex]::Escape($k.Substring(0,[Math]::Min(4,$k.Length)))}|Select-Object -First 10);Write-Output ('MISSING '+$c+'  相近可用: '+($near -join ' | '))}
  }
  if($miss){Write-Output ('CHECK_FAIL missing='+$miss+'：改用能力文件里存在的成员，或查官方文档中适用于本版本的方法');exit 1}
  Write-Output 'CHECK_OK'
}
exit 0