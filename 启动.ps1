# 第一步先读 AGENTS.md「第 0 步」。首连推荐直接用一条命令：.\一键连接.ps1 -Software "<软件名>" -StartDir "<本会话起点目录>"（它会调用本脚本）。
# 本脚本只部署工作区；包在 %TEMP% 时先把本包复制到起点目录（连接教练\落位.ps1）再继续。
param([Parameter(Mandatory=$true)][string]$Software,[string]$Workspace,[switch]$NoPanel,[switch]$Fresh,[switch]$OpenCad,[string]$StartDir)
$ErrorActionPreference='Stop'
Write-Output 'STEP0: 只碰本包、起点目录、本机定位.json 的 install_dirs；每个大步骤前跑 连接教练\越界路径审计.ps1（退出码 2=本轮失败，立即停）。'
Write-Output 'CHAIN: 一键连接.ps1 = 0落位 → 1定位软件(连接教练\定位软件.ps1) → 2部署工作区(本脚本) → 3查通用卡(连接教练\查通用卡.ps1) → 4快连 | NEED_AGENT_METHOD → 适配器\编译桥接.ps1 → 适配器\启动软件.ps1 → YA插件\ya_link.ps1 → 查通用卡 -Stage 建模前 → 连接软件.ps1 -Action Connect -TaskFile → 连接经验.ps1 add'
$selfRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
if(-not $Workspace -and (Split-Path $selfRoot -Leaf) -ne '工作区' -and [IO.File]::Exists((Join-Path $selfRoot '连接教练\落位.ps1'))){
  $lw=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $selfRoot '连接教练\落位.ps1') -Package $selfRoot @(if($StartDir){@('-StartDir',$StartDir)})
  $lc=$LASTEXITCODE;$lw|Where-Object{$_ -notmatch '^\{'}|ForEach-Object{Write-Output $_}
  if($lc){exit $lc}
  $lr=($lw|Where-Object{$_ -match '^\{'}|Select-Object -Last 1)|ConvertFrom-Json
  if($lr.moved){
    $fa=@('-Software',$Software);if($NoPanel){$fa+='-NoPanel'};if($Fresh){$fa+='-Fresh'};if($OpenCad){$fa+='-OpenCad'}
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $lr.package '启动.ps1') @fa
    exit $LASTEXITCODE
  }
}
if($PSVersionTable.PSEdition -ne 'Desktop'){throw '请使用 Windows PowerShell 5.1'}
if($OpenCad -and ($Software -ine 'FreeCAD' -or $NoPanel)){throw 'OPEN_CAD_REQUIRES_FREECAD_AND_DESKTOP'}
if(-not $Workspace){
  # Package unzipped directly on Desktop = daily use (Desktop\ngxz-ya). Otherwise (start folder / Temp) = short sibling workspace in the same start folder.
  $desk=[IO.Path]::GetFullPath([Environment]::GetFolderPath('DesktopDirectory')).TrimEnd('\')
  $src=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
  $startDir=Split-Path $src -Parent
  if($startDir -ieq $desk){$Workspace=Join-Path $desk 'ngxz-ya'}else{$Workspace=Join-Path $startDir 'ngxz-ya-ws'}
}
$Workspace=[IO.Path]::GetFullPath($Workspace).TrimEnd('\')
$source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
if($Workspace -eq $source -or $Workspace.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw '部署位置不能是源码或源码子目录'}
if($Fresh -and (Test-Path -LiteralPath $Workspace)){throw 'FRESH_WORKSPACE_REQUIRED: 干净测试必须使用不存在的新工作区；不清空、不覆盖已有目录。'}
$runtime=Join-Path $Workspace '工作区'
$identity=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($identity.ComputeHash([Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant()))).Replace('-','')}finally{$identity.Dispose()}
$lock=[Threading.Mutex]::new($false,('Local\YADeploy-'+$key));$held=$false
try{
 try{$held=$lock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(-not $held){throw 'BUSY: 此工作区正在部署'}
 if($Fresh -and (Test-Path -LiteralPath $Workspace)){throw 'FRESH_WORKSPACE_REQUIRED: 请使用不存在的新工作区'}
 $marker=Join-Path $Workspace '工作区说明.json'
 if(Test-Path -LiteralPath $Workspace){
  if(-not (Test-Path -LiteralPath $marker)){throw '目标目录已有用户文件，拒绝覆盖；请指定其他 Workspace'}
  $managed=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
  if($managed.product -cne 'ngxz-ya' -or $managed.schema -ne 1){throw '工作区标识不符'}
 }else{
  New-Item -ItemType Directory -Path $Workspace -ErrorAction Stop|Out-Null
  [IO.File]::WriteAllText($marker,'{"schema":1,"product":"ngxz-ya","runtime":"工作区","state":"initializing"}',[Text.UTF8Encoding]::new($true))
 }
 $policy=Get-Content -LiteralPath (Join-Path $source '发布允许清单.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $sourceFiles=@($policy.files|ForEach-Object{@{file=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $source $_)).Hash}})
 $currentFile=Join-Path $Workspace '程序版本.json'
 $same=$false;$current=$null
 $updateMarker=Join-Path $runtime '更新中.json'
 $resume=Test-Path -LiteralPath $updateMarker
 if(Test-Path -LiteralPath $currentFile){
  $current=Get-Content -LiteralPath $currentFile -Raw -Encoding UTF8|ConvertFrom-Json
  $same=@($sourceFiles|Where-Object {$r=$_;@($current.files|Where-Object {$_.file -ceq $r.file -and $_.sha256 -ceq $r.sha256}).Count -ne 1 -or -not [IO.File]::Exists((Join-Path $runtime $r.file)) -or (Get-FileHash -LiteralPath (Join-Path $runtime $r.file)).Hash -cne $r.sha256}).Count -eq 0
 }
 if(-not $same -or $resume){
  $deployRecords=Join-Path $Workspace '部署记录'
  if(-not (Test-Path -LiteralPath $deployRecords)){
   $recordDir=[IO.Directory]::CreateDirectory($deployRecords)
   $recordDir.Attributes=$recordDir.Attributes -bor [IO.FileAttributes]::Hidden
  }
  $recordDir=Get-Item -LiteralPath $deployRecords -Force
  if(-not $recordDir.PSIsContainer -or ($recordDir.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '部署记录目录无效'}
  $stage=Join-Path $recordDir.FullName ('部署暂存-'+[guid]::NewGuid().ToString('N'))
  $packOutput=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source '准备隔离包.ps1') -Destination $stage -Profile TestCopy
  if($LASTEXITCODE){$packOutput|Write-Output;throw '部署检查失败；保留现场'}
  $guard=$null;$softwareGuard=$null;$runtimeHeld=$false;$softwareHeld=$false
  try{
   if(Test-Path -LiteralPath $runtime){
    . (Join-Path $source 'YA插件\连接上下文.ps1')
    $guard=[Threading.Mutex]::new($false,('Local\YARuntime-'+[YaEvidence]::Identity($runtime)))
    $softwareGuard=[Threading.Mutex]::new($false,('Local\YASoftwareOperation-'+[YaEvidence]::Identity($runtime)))
    try{$runtimeHeld=$guard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$runtimeHeld=$true}
    try{$softwareHeld=$softwareGuard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$softwareHeld=$true}
    if(-not $runtimeHeld -or -not $softwareHeld){throw 'BUSY: 工作区任务尚在运行，不能升级'}
    . (Join-Path $source 'YA插件\真实记录.ps1')
    if($resume){
     $pendingUpdate=Get-Content -LiteralPath $updateMarker -Raw -Encoding UTF8|ConvertFrom-Json
     if($pendingUpdate.schema -ne 1 -or @($pendingUpdate.files).Count -ne $sourceFiles.Count -or
        @($sourceFiles|Where-Object {$row=$_;@($pendingUpdate.files|Where-Object {$_.file -ceq $row.file -and $_.sha256 -ceq $row.sha256}).Count -ne 1}).Count){
      throw 'UPDATE_SOURCE_MISMATCH: 使用上次升级的同一份发布包继续'
     }
    }else{
    Assert-YaOperation $runtime
    $oldStatus=Get-YaPackageHudHome $runtime
    $localStatus=Join-Path $runtime '运行状态'
    if($oldStatus -ine $localStatus -and (Test-Path -LiteralPath $oldStatus) -and -not (Test-Path -LiteralPath $localStatus)){
     Copy-Item -LiteralPath $oldStatus -Destination $localStatus -Recurse
    }
    $backupDir=Join-Path $Workspace '备份';[IO.Directory]::CreateDirectory($backupDir)|Out-Null
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $backup=Join-Path $backupDir ('升级前程序-'+[guid]::NewGuid().ToString('N')+'.zip')
    $owned=@($current.files|ForEach-Object {$_.file})
    foreach($row in $sourceFiles){
     $target=Join-Path $runtime $row.file
     if((Test-Path -LiteralPath $target) -and $row.file -cnotin $owned -and
        (-not [IO.File]::Exists($target) -or (Get-FileHash -LiteralPath $target).Hash -cne $row.sha256)){
      throw ('UPDATE_FILE_NOT_OWNED: '+$row.file)
     }
    }
    # Only program files are replaced. Live task data and HUD logs stay in place.
    $zip=[IO.Compression.ZipFile]::Open($backup,[IO.Compression.ZipArchiveMode]::Create)
    try{
     foreach($row in $sourceFiles){
      $file=Join-Path $runtime $row.file
      if([IO.File]::Exists($file)){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file,$row.file)}
     }
    }finally{$zip.Dispose()}
    Write-YaAtomic $updateMarker @{schema=1;state='updating';files=$sourceFiles;backup=$backup}
    }
    # Only allowlisted program files are updated. Factory indices and all private records stay in place.
    foreach($row in $sourceFiles){
     $target=Join-Path $runtime $row.file
     if([IO.File]::Exists($target) -and (Get-FileHash -LiteralPath $target).Hash -ceq $row.sha256){continue}
     [IO.Directory]::CreateDirectory((Split-Path $target -Parent))|Out-Null
     $tmp=Join-Path (Split-Path $target -Parent) ([guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::Copy((Join-Path $stage $row.file),$tmp,$false)
     if([IO.File]::Exists($target)){[IO.File]::Replace($tmp,$target,[NullString]::Value)}else{[IO.File]::Move($tmp,$target)}
    }
   }else{
    if(-not $runtime.StartsWith($Workspace+'\',[StringComparison]::OrdinalIgnoreCase)){throw '目标越界'}
    Move-Item -LiteralPath $stage -Destination $runtime
   }
  }finally{if($runtimeHeld){$guard.ReleaseMutex()};if($softwareHeld){$softwareGuard.ReleaseMutex()};if($guard){$guard.Dispose()};if($softwareGuard){$softwareGuard.Dispose()}}
  [IO.File]::WriteAllText((Join-Path $runtime '包信息.json'),'{"schema":2,"stage":"UserWorkspace","product":"ngxz-ya"}',[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText($currentFile,(@{schema=1;files=$sourceFiles;updated_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($true))
  if([IO.File]::Exists($updateMarker)){[IO.File]::Delete($updateMarker)}
  if(Test-Path -LiteralPath $stage){
   $stagedCopy=Get-Item -LiteralPath $stage
   if($stagedCopy.PSIsContainer -and $stagedCopy.Parent.FullName -ieq $recordDir.FullName -and -not ($stagedCopy.Attributes -band [IO.FileAttributes]::ReparsePoint)){
    Remove-Item -LiteralPath $stagedCopy.FullName -Recurse -Force -ErrorAction Continue
   }
  }
 }
 [IO.File]::WriteAllText($marker,(@{schema=1;product='ngxz-ya';runtime='工作区';experience='工作区\经验库';connections='工作区\连接教练\连接经验';artifacts='artifacts';note='经验与程序更新独立保留；重新下载后仍使用这个工作区，不复制旧测试结果'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
 [IO.Directory]::CreateDirectory((Join-Path $Workspace 'artifacts'))|Out-Null
 $locate=Join-Path $source '本机定位.json';if([IO.File]::Exists($locate)){[IO.File]::Copy($locate,(Join-Path $Workspace '本机定位.json'),$true)}
 $origin=Join-Path $source '下载来源.json';if([IO.File]::Exists($origin)){[IO.File]::Copy($origin,(Join-Path $Workspace '下载来源.json'),$true)}
[IO.Directory]::CreateDirectory((Join-Path $Workspace '成果'))|Out-Null
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '安装卸载\安装.ps1') -PackageOnly
 if($LASTEXITCODE){throw '安装失败，保留工作区'}
 Write-Output ('workspace: '+$runtime)
 if($OpenCad){
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '适配器\FreeCAD\启动.ps1')
  exit $LASTEXITCODE
 }
 $checkArgs=@('-Software',$Software,'-Action','Check')
 if(-not $NoPanel){$checkArgs+='-ShowPanel'}
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '连接软件.ps1') @checkArgs
 exit $LASTEXITCODE
}finally{if($held){$lock.ReleaseMutex()};$lock.Dispose()}
