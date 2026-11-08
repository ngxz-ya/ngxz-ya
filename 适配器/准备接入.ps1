param([Parameter(Mandatory=$true)][string]$Software,[ValidateSet('New','Check')][string]$Action='New')
$ErrorActionPreference='Stop'
$pkg=Split-Path $PSScriptRoot -Parent
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
. (Join-Path $pkg 'YA插件\真实记录.ps1')
try{
  Assert-YaIsolatedPackage $pkg;Assert-YaOperation $pkg
  $answer=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') ensure ('soft='+$Software))
  if($LASTEXITCODE){throw ($answer -join "`n")}
  $slot=[regex]::Match(($answer -join "`n"),'(?m)^slot:\s*(\S+)').Groups[1].Value
  if(-not $slot){throw 'SOFTWARE_SLOT_REQUIRED'}
  $local=Join-Path $pkg ('连接教练\连接经验\'+$slot)
  if($Action -eq 'New'){
    foreach($name in @('driver.ps1','reader.ps1','reader.settings.json','方法.草稿.json')){if(Test-Path -LiteralPath (Join-Path $local $name)){throw 'REFUSE_OVERWRITE: existing local method is preserved; use -Action Check'}}
    $work=Join-Path ([YaEvidence]::Work($pkg,$slot)) ('preparation-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($local)|Out-Null;[IO.Directory]::CreateDirectory($work)|Out-Null
    $driver=@'
param([string]$Action,[string]$Context)
$ErrorActionPreference='Stop'
$pkg=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '适配器\前台驱动.ps1') -Action $Action -Context $Context
exit $LASTEXITCODE
'@
    $reader=@'
param([string]$Context)
$ErrorActionPreference='Stop'
$pkg=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $pkg '适配器\运行工具.ps1')
try{
 $c=Get-Content -LiteralPath $Context -Raw -Encoding UTF8|ConvertFrom-Json
 $settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reader.settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not $settings.executable -or -not [IO.File]::Exists($settings.executable)){throw 'READER_IMPLEMENTATION_REQUIRED: configure a reviewed real independent reader first'}
 $data=Join-Path $c.directory 'reader-measurements.json'
 if(Test-Path -LiteralPath $data){throw 'REFUSE_OLD_MEASUREMENTS'}
 $args2=@($settings.arguments|ForEach-Object{([string]$_).Replace('{model}',[string]$c.model).Replace('{output}',$data)})
 $seconds=if($c.timeout_seconds){[Math]::Max(1,[int]$c.timeout_seconds-5)}else{90}
 $run=Invoke-YaNativeProcess -FilePath $settings.executable -Arguments $args2 -Directory $c.directory -Name independent_reader -TimeoutSeconds $seconds
 $items=Get-Content -LiteralPath $data -Raw -Encoding UTF8|ConvertFrom-Json
 Write-YaReadback -Context $c -Measurements @($items) -Artifacts @($c.model,$data,$run.stdout,$run.stderr,(Join-Path $c.directory 'independent_reader.process.json')) -Source independent_software_reopen -ReaderPid $run.pid -ModelSha256 (Get-FileHash -LiteralPath $c.model).Hash
 exit 0
}catch{Write-Output ('READER_FAILED: '+$_.Exception.Message);exit 1}
'@
    [IO.File]::WriteAllText((Join-Path $local 'driver.ps1'),$driver,[Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $local 'reader.ps1'),$reader,[Text.UTF8Encoding]::new($true))
    Write-YaAtomic (Join-Path $local 'reader.settings.json') @{executable='';arguments=@('{model}','{output}');note='Configure a reviewed program that actually reopens the model and writes a measured name/value JSON array. No expected values are supplied.'}
    Write-YaAtomic (Join-Path $local '方法.草稿.json') @{schema=1;software=$Software;software_version='';interface='';mode='interactive';status='draft';sources=@();license_review='';safety_review='';driver='driver.ps1';driver_sha256=(Get-FileHash -LiteralPath (Join-Path $local 'driver.ps1')).Hash;frontend=@{bridge_sha256='';reader='reader.ps1';reader_sha256=(Get-FileHash -LiteralPath (Join-Path $local 'reader.ps1')).Hash;extension=''};preparation_work=$work}
  }
  $files=@(Get-ChildItem -LiteralPath $local -File -Filter '*.ps1'|ForEach-Object{Assert-YaPowerShellFile $_.FullName;@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
  $taskId=''
  if($Action -eq 'New'){
    $entry=Join-Path $pkg 'YA插件\本包命令.ps1'
    $flow=$null;$flowFile=Join-Path $pkg '经验库\流程.json'
    if(Test-Path -LiteralPath $flowFile){$flow=Get-Content -LiteralPath $flowFile -Raw -Encoding UTF8|ConvertFrom-Json}
    if($flow.current -and $flow.current.status -in @('进行中','自检通过')){
      if($flow.current.slot -cne $slot){throw 'BUSY_OTHER_TASK: preserve the current task; finish or hand it over before preparing another software'}
      $taskId=$flow.current.id
    }else{
      $opened=@(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry task_open ('slot='+$slot) tag=connection_preparation ('title=准备连接 '+$Software))
      if($LASTEXITCODE){throw ('TASK_PREPARATION_FAILED: '+($opened -join "`n"))}
      $taskId=[regex]::Match(($opened -join "`n"),'(?m)^task:\s*(\S+)').Groups[1].Value
      $draft=Get-Content -LiteralPath (Join-Path $local '方法.草稿.json') -Raw -Encoding UTF8|ConvertFrom-Json
      $draft|Add-Member -NotePropertyName preparation_task -NotePropertyValue $taskId
      Write-YaAtomic (Join-Path $local '方法.草稿.json') $draft
    }
    if(-not $taskId){throw 'TASK_ID_MISSING: preserve generated files and inspect task output'}
    $searched=@(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry exp_recall ('slot='+$slot) ('task='+$taskId) q=连接)
    if($LASTEXITCODE){throw ('EXPERIENCE_SEARCH_FAILED: '+($searched -join "`n"))}
    $general=@(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry exp_search slot=generic q=连接)
    if($LASTEXITCODE){throw ('GENERAL_SEARCH_FAILED: '+($general -join "`n"))}
  }
  @{status='SCAFFOLD_CHECKED_NOT_CONNECTED';slot=$slot;local=$local;task=$taskId;files=$files;next='Review the actual software API and reader implementation; complete method provenance and real tests. A draft is not a registered method or verified experience.'}|ConvertTo-Json -Depth 8
  exit 0
}catch{Write-Output ('PREPARATION_FAILED: '+$_.Exception.Message);exit 1}
