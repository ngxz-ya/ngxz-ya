# 第一步先读 AGENTS.md「第 0 步」。首连推荐直接用一条命令：.\一键连接.ps1 -Software "<软件名>"（它会调用本脚本）。
# 本脚本部署或就地启用工作区。任何 Agent 一律使用桌面固定路径 ngxz-ya（DesktopDirectory\ngxz-ya）：已有包就用，没有才放到那里。
# 包根即工作区，不再生成 ngxz-ya-ws / 二次拷贝。研发源码目录不得就地打成 UserWorkspace。
param([Parameter(Mandatory=$true)][string]$Software,[string]$Workspace,[switch]$NoPanel,[switch]$Fresh,[switch]$OpenCad,[string]$StartDir)
$ErrorActionPreference='Stop'
Write-Output 'STEP0: 只碰本包、桌面固定路径 ngxz-ya、本机定位.json 的 install_dirs；每个大步骤前跑 连接教练\越界路径审计.ps1（退出码 2=本轮失败，立即停）。'
Write-Output 'CHAIN: 一键连接.ps1 = 0落位(桌面 ngxz-ya) → 1定位软件(连接教练\定位软件.ps1) → 2部署/就地启用(本脚本) → 3查通用卡(连接教练\查通用卡.ps1) → 4快连 | NEED_AGENT_METHOD → 上网找开源方案 → 适配器\接口探测.ps1 → 适配器\编译桥接.ps1 → 适配器\启动软件.ps1(含弹窗守护) → YA插件\ya_link.ps1 → 查通用卡 -Stage 建模前 → 连接软件.ps1 -Action Connect -TaskFile → 连接经验.ps1 add'
$selfRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
. (Join-Path $selfRoot 'YA插件\连接上下文.ps1')
if(-not $Workspace -and [IO.File]::Exists((Join-Path $selfRoot '连接教练\落位.ps1'))){
  $lw=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $selfRoot '连接教练\落位.ps1') -Package $selfRoot @(if($StartDir){@('-StartDir',$StartDir)})
  $lc=$LASTEXITCODE;$lw|Where-Object{$_ -notmatch '^\{'}|ForEach-Object{Write-Output $_}
  if($lc){exit $lc}
  $lr=($lw|Where-Object{$_ -match '^\{'}|Select-Object -Last 1)|ConvertFrom-Json
  if($lr.moved){
    $fa=@('-Software',$Software);if($NoPanel){$fa+='-NoPanel'};if($Fresh){$fa+='-Fresh'};if($OpenCad){$fa+='-OpenCad'}
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $lr.package '启动.ps1') @fa
    exit $LASTEXITCODE
  }
  if($lr.package -and ([IO.Path]::GetFullPath($lr.package).TrimEnd('\') -ine $selfRoot)){
    $fa=@('-Software',$Software);if($NoPanel){$fa+='-NoPanel'};if($Fresh){$fa+='-Fresh'};if($OpenCad){$fa+='-OpenCad'}
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $lr.package '启动.ps1') @fa
    exit $LASTEXITCODE
  }
}
if($PSVersionTable.PSEdition -ne 'Desktop'){throw '请使用 Windows PowerShell 5.1'}
if($OpenCad){throw 'OPEN_CAD_REMOVED: 本包不再内置任何软件的连接实现。请运行 一键连接.ps1，并按 NEED_AGENT_METHOD 先上网找合法开源连接方案。'}
$source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
if(-not $Workspace){ $Workspace=Get-YaDesktopPackageRoot }
$Workspace=[IO.Path]::GetFullPath($Workspace).TrimEnd('\')
if(Test-YaOfficialSourceTree $Workspace){throw '部署位置不能是研发源码目录。任何 Agent 只使用桌面固定路径 ngxz-ya，不要在 git 源码树上就地写成 UserWorkspace。'}
if($Workspace.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw '部署位置不能是源码子目录'}
$inPlace=($Workspace -ieq $source)
if($inPlace -and (Test-YaOfficialSourceTree $source)){throw '研发源码目录不得就地部署。请把包放到桌面 ngxz-ya（有则用、无则下载/复制到那里）。'}
if($Fresh -and (Test-Path -LiteralPath $Workspace) -and -not $inPlace){throw 'FRESH_WORKSPACE_REQUIRED: 干净测试必须使用不存在的新工作区；不清空、不覆盖已有目录。'}
# 包根即工作区：程序文件、经验库与 运行数据 都在 $Workspace 下，不再套 工作区\ 或 ngxz-ya-ws。
$runtime=$Workspace

$identity=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($identity.ComputeHash([Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant()))).Replace('-','')}finally{$identity.Dispose()}
$lock=[Threading.Mutex]::new($false,('Local\YADeploy-'+$key));$held=$false
try{
 try{$held=$lock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(-not $held){throw 'BUSY: 此工作区正在部署'}
 if($Fresh -and (Test-Path -LiteralPath $Workspace)){throw 'FRESH_WORKSPACE_REQUIRED: 请使用不存在的新工作区'}
 $marker=Join-Path $Workspace '工作区说明.json'
 if(Test-Path -LiteralPath $Workspace){
  $isPkg=Test-YaPackageTree $Workspace
  if(-not (Test-Path -LiteralPath $marker) -and -not $isPkg){throw '目标目录已有用户文件，拒绝覆盖；请指定其他 Workspace'}
  if(Test-Path -LiteralPath $marker){
   $managed=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
   if($managed.product -cne 'ngxz-ya' -or $managed.schema -ne 1){throw '工作区标识不符'}
  }
 }else{
  New-Item -ItemType Directory -Path $Workspace -ErrorAction Stop|Out-Null
  [IO.File]::WriteAllText($marker,'{"schema":1,"product":"ngxz-ya","runtime":"包根","state":"initializing"}',[Text.UTF8Encoding]::new($true))
 }
 if($inPlace -and -not (Test-Path -LiteralPath (Join-Path $runtime '包信息.json'))){
  [IO.File]::WriteAllText((Join-Path $runtime '包信息.json'),'{"schema":2,"stage":"UserWorkspace","product":"ngxz-ya"}',[Text.UTF8Encoding]::new($true))
 }
 $policy=Get-Content -LiteralPath (Join-Path $source '发布允许清单.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $sourceFiles=@($policy.files|ForEach-Object{@{file=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $source $_)).Hash}})
 $currentFile=Join-Path $Workspace '程序版本.json'
 $same=$false;$current=$null
 $updateMarker=Join-Path $runtime '运行数据\更新中.json'
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
   $runtimeReady=Test-Path -LiteralPath (Join-Path $runtime 'YA插件\连接上下文.ps1')
   if($runtimeReady){
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
    $localStatus=Join-Path $runtime '运行数据\运行状态'
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
    if($inPlace){throw 'INPLACE_INCOMPLETE: 桌面包缺少程序文件，拒绝就地补拷以免覆盖用户内容。请换到空的桌面 ngxz-ya 后重新下载。'}
    Get-ChildItem -LiteralPath $stage -Force | ForEach-Object {
     $dest=Join-Path $runtime $_.Name
     if($_.Name -ceq '工作区说明.json' -and (Test-Path -LiteralPath $dest)){return}
     if(Test-Path -LiteralPath $dest){throw ('目标已有文件，拒绝覆盖: '+$_.Name)}
     Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }
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
 [IO.File]::WriteAllText($marker,(@{schema=1;product='ngxz-ya';runtime='包根';experience='经验库';connections='连接教练\连接经验';artifacts='运行数据\artifacts';state='ready';note='包根即工作区；运行状态与 artifacts 收在 运行数据；经验按软件分夹存在包内经验库；重新下载后仍用桌面 ngxz-ya，不另建副本'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
 [IO.Directory]::CreateDirectory((Join-Path $runtime '运行数据\artifacts'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $runtime '运行数据\运行状态'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $runtime '成果'))|Out-Null
 $locate=Join-Path $source '本机定位.json';if([IO.File]::Exists($locate) -and $locate -ine (Join-Path $runtime '本机定位.json')){[IO.File]::Copy($locate,(Join-Path $runtime '本机定位.json'),$true)}
 $origin=Join-Path $source '下载来源.json';if([IO.File]::Exists($origin) -and $origin -ine (Join-Path $runtime '下载来源.json')){[IO.File]::Copy($origin,(Join-Path $runtime '下载来源.json'),$true)}
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '安装卸载\安装.ps1') -PackageOnly
 if($LASTEXITCODE){throw '安装失败，保留工作区'}
 Write-Output ('workspace: '+$runtime)
 if($OpenCad){
  throw 'OPEN_CAD_REMOVED'
 }
 $checkArgs=@('-Software',$Software,'-Action','Check')
 if(-not $NoPanel){$checkArgs+='-ShowPanel'}
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '连接软件.ps1') @checkArgs
 exit $LASTEXITCODE
}finally{if($held){$lock.ReleaseMutex()};$lock.Dispose()}
