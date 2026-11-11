param([ValidateSet('Backup','Restore')][string]$Action='Backup',[Parameter(Mandatory=$true)][string]$Workspace,[Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference='Stop'
$Workspace=[IO.Path]::GetFullPath($Workspace).TrimEnd('\');$Archive=[IO.Path]::GetFullPath($Archive)
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
function Get-YaBackupLayout([string]$Workspace,[object]$Manifest){
 $legacy=$false
 if($Manifest){ $legacy=@($Manifest.files|Where-Object {$_.file -ceq '工作区/包信息.json'}).Count -gt 0 }
 elseif(Test-Path -LiteralPath (Join-Path $Workspace '工作区\包信息.json')){ $legacy=$true }
 if($legacy){
  return [ordered]@{legacy=$true;runtime=(Join-Path $Workspace '工作区');state=(Join-Path $Workspace '工作区\运行状态');required=@('工作区说明.json','程序版本.json','工作区/包信息.json','工作区/AGENTS.md');names=@('工作区','artifacts','成果','工作区说明.json','程序版本.json','迁移待核验.json');hudSkip=@('工作区/运行状态/io/hud_view.json')}
 }
 return [ordered]@{legacy=$false;runtime=$Workspace;state=(Join-Path $Workspace '运行数据\运行状态');required=@('工作区说明.json','程序版本.json','包信息.json','AGENTS.md');names=@('运行数据','经验库','连接教练\连接经验','成果','artifacts','工作区说明.json','程序版本.json','包信息.json','AGENTS.md','迁移待核验.json');hudSkip=@('运行数据/运行状态/io/hud_view.json','工作区/运行状态/io/hud_view.json')}
}
if($Action -eq 'Restore'){
 if(Test-Path -LiteralPath $Workspace){throw '恢复只允许不存在的新目录，拒绝覆盖'}
 $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
 try{
  $manifestEntry=$zip.GetEntry('backup-manifest.json');if(-not $manifestEntry){throw '备份清单缺失'}
  $reader=[IO.StreamReader]::new($manifestEntry.Open());try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
  if($manifest.schema -ne 1 -or $manifest.product -cne 'ngxz-ya'){throw '备份类型不符'}
  $layout=Get-YaBackupLayout $Workspace $manifest
  foreach($required in @($layout.required)){if(@($manifest.files|Where-Object {$_.file -ceq $required}).Count -ne 1){throw ('备份缺少必需内容: '+$required)}}
  $names=@{};foreach($entry in $zip.Entries){
   $target=[IO.Path]::GetFullPath((Join-Path $Workspace $entry.FullName))
   if(-not $target.StartsWith($Workspace+'\',[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName -match '[:\\]' -or $names.ContainsKey($entry.FullName)){throw '不安全或重复的备份路径'}
   $names[$entry.FullName]=$true
  }
  if($zip.Entries.Count -ne @($manifest.files).Count+1){throw '备份文件集合不符'}
  foreach($row in $manifest.files){
   $entry=$zip.GetEntry($row.file);if(-not $entry){throw '备份文件缺失'}
   $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
   try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
   if($hash -cne $row.sha256){throw ('备份校验失败: '+$row.file)}
  }
 }finally{$zip.Dispose()}
 [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$Workspace)
 $layout=Get-YaBackupLayout $Workspace $null
 $stateHome=$layout.state
 $history=Join-Path $stateHome ('迁移历史\'+[guid]::NewGuid().ToString('N'))
 foreach($name in @('operation.json','operation_request.json','quick_request.json','io\link.json','io\challenge.json','io\frontend-acceptance.json','io\hud_window.json')){
  $oldPath=Join-Path $stateHome $name
  if([IO.File]::Exists($oldPath)){
   $newPath=Join-Path $history $name
   [IO.Directory]::CreateDirectory((Split-Path $newPath -Parent))|Out-Null
   [IO.File]::Move($oldPath,$newPath)
  }
 }
 $mappingFile=Join-Path $Workspace '迁移待核验.json'
 $origins=@($manifest.source)
 if([IO.File]::Exists($mappingFile)){
  $prior=Get-Content -LiteralPath $mappingFile -Raw -Encoding UTF8|ConvertFrom-Json
  $origins+=@($prior.source)+@($prior.origins)
 }
 [IO.File]::WriteAllText($mappingFile,(@{source=$manifest.source;origins=@($origins|Where-Object {$_}|Select-Object -Unique);destination=$Workspace;note='证据按新路径重新核对哈希；活动软件和接口重新验证。'}|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
 @{status='RESTORED_REVALIDATION_REQUIRED';workspace=$Workspace}|ConvertTo-Json;exit 0
}
if(Test-Path -LiteralPath $Archive){throw '备份文件已存在，拒绝覆盖'}
if($Archive.StartsWith($Workspace+'\',[StringComparison]::OrdinalIgnoreCase)){throw '请将备份保存到工作区之外'}
$marker=Get-Content -LiteralPath (Join-Path $Workspace '工作区说明.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.product -cne 'ngxz-ya' -or $marker.schema -ne 1){throw '不是本工具管理的工作区'}
if($marker.runtime -cnotin @('工作区','包根')){throw '不是本工具管理的工作区'}
$layout=Get-YaBackupLayout $Workspace $null
$runtime=$layout.runtime
. (Join-Path $runtime 'YA插件\连接上下文.ps1')
. (Join-Path $runtime 'YA插件\真实记录.ps1')
$locks=@();$zip=$null
try{
 foreach($prefix in @('YASoftwareOperation','YARuntime')){
  $lock=[Threading.Mutex]::new($false,('Local\'+$prefix+'-'+[YaEvidence]::Identity($runtime)))
  if(-not $lock.WaitOne(0)){$lock.Dispose();throw 'BUSY: 任务进行中，不能制作一致备份'};$locks+=,$lock
 }
 Assert-YaOperation $runtime
 $filesByName=@{}
 $backupNames=@($layout.names)
 if(-not $layout.legacy){ $backupNames=@(Get-ChildItem -LiteralPath $Workspace -Force | Where-Object { $_.Name -notin @('部署记录','备份') -and $_.Name -notlike '*.zip' } | ForEach-Object { $_.Name }) }
 foreach($name in @($backupNames)){
  $path=Join-Path $Workspace $name
  if(Test-Path -LiteralPath $path){
   foreach($item in @(Get-Item -LiteralPath $path)+@(Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue)){
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '备份拒绝重解析点'}
    if(-not $item.PSIsContainer){
     $relative=$item.FullName.Substring($Workspace.Length+1).Replace('\','/')
     if(@($layout.hudSkip) -contains $relative){continue}
     $filesByName[$relative]=[pscustomobject]@{path=$item.FullName;file=$relative;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash}
    }
   }
  }
 }
 $files=@($filesByName.Values|Sort-Object file)
 $zip=[IO.Compression.ZipFile]::Open($Archive,[IO.Compression.ZipArchiveMode]::Create)
 foreach($row in $files){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$row.path,$row.file)|Out-Null}
 foreach($row in $files){if((Get-FileHash -LiteralPath $row.path).Hash -cne $row.sha256){throw '备份期间内容改变，保留失败归档但不可用于恢复'}}
 $entry=$zip.CreateEntry('backup-manifest.json');$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
 try{$writer.Write((@{schema=1;product='ngxz-ya';source=$Workspace;excluded=@((@($layout.hudSkip)|ForEach-Object{$_+': derived live rendering'}));files=@($files|ForEach-Object{@{file=$_.file;sha256=$_.sha256}})}|ConvertTo-Json -Depth 6))}finally{$writer.Dispose()}
 $zip.Dispose();$zip=$null
 @{status='BACKUP_CREATED';archive=$Archive;sha256=(Get-FileHash -LiteralPath $Archive).Hash;files=$files.Count;privacy='包含私人经验、模型和记录，不能公开'}|ConvertTo-Json
}finally{if($zip){$zip.Dispose()};foreach($lock in $locks){$lock.ReleaseMutex();$lock.Dispose()}}
