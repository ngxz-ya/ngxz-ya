param([Parameter(Mandatory=$true)][string]$Software,[string]$Workspace,[switch]$NoPanel,[switch]$Fresh)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop'){throw '请使用 Windows PowerShell 5.1'}
if(-not $Workspace){$Workspace=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'ngxz-ya'}
$Workspace=[IO.Path]::GetFullPath($Workspace).TrimEnd('\')
$source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
if($Workspace -eq $source -or $Workspace.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw '部署位置不能是源码或源码子目录'}
if($Fresh -and (Test-Path -LiteralPath $Workspace)){throw 'FRESH_WORKSPACE_REQUIRED: 干净测试必须使用不存在的新工作区；不清空、不覆盖已有目录。'}
$runtime=Join-Path $Workspace '工作区'
$identity=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($identity.ComputeHash([Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant()))).Replace('-','')}finally{$identity.Dispose()}
$lock=[Threading.Mutex]::new($false,('Local\YADeploy-'+$key));$held=$false
try{
 $held=$lock.WaitOne(0);if(-not $held){throw 'BUSY: 此工作区正在部署'}
 $marker=Join-Path $Workspace '工作区说明.json'
 if(Test-Path -LiteralPath $Workspace){
  if(-not (Test-Path -LiteralPath $marker)){throw '目标目录已有用户文件，拒绝覆盖；请指定其他 Workspace'}
  $managed=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
  if($managed.product -cne 'ngxz-ya' -or $managed.schema -ne 1){throw '工作区标识不符'}
 }else{[IO.Directory]::CreateDirectory($Workspace)|Out-Null}
 $policy=Get-Content -LiteralPath (Join-Path $source '发布允许清单.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $sourceFiles=@($policy.files|ForEach-Object{@{file=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $source $_)).Hash}})
 $currentFile=Join-Path $Workspace '程序版本.json'
 $same=$false
 if(Test-Path -LiteralPath $currentFile){
  $current=Get-Content -LiteralPath $currentFile -Raw -Encoding UTF8|ConvertFrom-Json
  $same=@($sourceFiles|Where-Object {$r=$_;@($current.files|Where-Object {$_.file -ceq $r.file -and $_.sha256 -ceq $r.sha256}).Count -ne 1 -or -not [IO.File]::Exists((Join-Path $runtime $r.file)) -or (Get-FileHash -LiteralPath (Join-Path $runtime $r.file)).Hash -cne $r.sha256}).Count -eq 0
 }
 if(-not $same){
  $stage=Join-Path $Workspace ('部署暂存-'+[guid]::NewGuid().ToString('N'))
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source '准备隔离包.ps1') -Destination $stage -Profile TestCopy
  if($LASTEXITCODE){throw '打包检查失败；保留现场'}
  $guard=$null;$softwareGuard=$null;$runtimeHeld=$false;$softwareHeld=$false
  try{
   if(Test-Path -LiteralPath $runtime){
    . (Join-Path $runtime 'YA插件\连接上下文.ps1')
    $guard=[Threading.Mutex]::new($false,('Local\YARuntime-'+[YaEvidence]::Identity($runtime)))
    $softwareGuard=[Threading.Mutex]::new($false,('Local\YASoftwareOperation-'+[YaEvidence]::Identity($runtime)))
    $runtimeHeld=$guard.WaitOne(0);$softwareHeld=$softwareGuard.WaitOne(0)
    if(-not $runtimeHeld -or -not $softwareHeld){throw 'BUSY: 工作区任务尚在运行，不能升级'}
    . (Join-Path $runtime 'YA插件\真实记录.ps1');Assert-YaOperation $runtime
    $oldStatus=Get-YaPackageHudHome $runtime
    $localStatus=Join-Path $runtime '运行状态'
    if($oldStatus -ine $localStatus -and (Test-Path -LiteralPath $oldStatus) -and -not (Test-Path -LiteralPath $localStatus)){
     Copy-Item -LiteralPath $oldStatus -Destination $localStatus -Recurse
    }
    $backupDir=Join-Path $Workspace '备份';[IO.Directory]::CreateDirectory($backupDir)|Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $backup=Join-Path $backupDir ('升级前程序和经验-'+[guid]::NewGuid().ToString('N')+'.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($runtime,$backup)
    [IO.File]::WriteAllText((Join-Path $runtime '更新中.json'),'{"state":"updating"}',[Text.UTF8Encoding]::new($true))
    # Only allowlisted program files are updated. Factory indices and all private records stay in place.
    foreach($row in $sourceFiles){
     $target=Join-Path $runtime $row.file;[IO.Directory]::CreateDirectory((Split-Path $target -Parent))|Out-Null
     $tmp=Join-Path (Split-Path $target -Parent) ([guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::Copy((Join-Path $stage $row.file),$tmp,$false)
     if([IO.File]::Exists($target)){[IO.File]::Replace($tmp,$target,[NullString]::Value)}else{[IO.File]::Move($tmp,$target)}
    }
    [IO.File]::Delete((Join-Path $runtime '更新中.json'))
   }else{
    if(-not $runtime.StartsWith($Workspace+'\',[StringComparison]::OrdinalIgnoreCase)){throw '目标越界'}
    Move-Item -LiteralPath $stage -Destination $runtime
   }
  }finally{if($runtimeHeld){$guard.ReleaseMutex()};if($softwareHeld){$softwareGuard.ReleaseMutex()};if($guard){$guard.Dispose()};if($softwareGuard){$softwareGuard.Dispose()}}
  [IO.File]::WriteAllText((Join-Path $runtime '包信息.json'),'{"schema":2,"stage":"UserWorkspace","product":"ngxz-ya"}',[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText($currentFile,(@{schema=1;files=$sourceFiles;updated_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($true))
 }
 [IO.File]::WriteAllText($marker,(@{schema=1;product='ngxz-ya';runtime='工作区';experience='工作区\经验库';connections='工作区\连接教练\连接经验';artifacts='成果';note='经验与程序更新独立保留；重新下载后仍使用这个工作区，不复制旧测试结果'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
 [IO.Directory]::CreateDirectory((Join-Path $Workspace '成果'))|Out-Null
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '安装卸载\安装.ps1') -PackageOnly
 if($LASTEXITCODE){throw '安装失败，保留工作区'}
 if(-not $NoPanel){Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $runtime 'YA插件\ya_hud.ps1')+'" -Show')|Out-Null}
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtime '连接软件.ps1') -Software $Software -Action Check
 exit $LASTEXITCODE
}finally{if($held){$lock.ReleaseMutex()};$lock.Dispose()}
