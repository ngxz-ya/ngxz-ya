# Dot-source from a reviewed local adapter; this file contains no software-specific code.
$yaToolsPackage=Split-Path $PSScriptRoot -Parent
. (Join-Path $yaToolsPackage 'YA插件\连接上下文.ps1')
. (Join-Path $yaToolsPackage 'YA插件\真实记录.ps1')
function Invoke-YaNativeProcess {
  param([Parameter(Mandatory=$true)][string]$FilePath,[string[]]$Arguments=@(),[Parameter(Mandatory=$true)][string]$Directory,[ValidatePattern('^[A-Za-z0-9_-]{1,50}$')][string]$Name='native',[ValidateRange(1,1800)][int]$TimeoutSeconds=120,[string]$StandardInput)
  Assert-YaIsolatedPackage $yaToolsPackage
  Assert-YaOperation $yaToolsPackage
  $FilePath=[IO.Path]::GetFullPath($FilePath);$Directory=[IO.Path]::GetFullPath($Directory)
  if(-not [IO.File]::Exists($FilePath) -or -not [IO.Directory]::Exists($Directory)){throw 'NATIVE_INPUT: executable and task directory must exist'}
  $out=Join-Path $Directory ($Name+'.stdout.log');$err=Join-Path $Directory ($Name+'.stderr.log');$meta=Join-Path $Directory ($Name+'.process.json')
  foreach($file in @($out,$err,$meta)){if(Test-Path -LiteralPath $file){throw 'NATIVE_REFUSE_OVERWRITE: preserve previous process evidence'}}
  $start=@{FilePath=$FilePath;WorkingDirectory=$Directory;WindowStyle='Hidden';PassThru=$true;RedirectStandardOutput=$out;RedirectStandardError=$err}
  if($Arguments.Count){$start.ArgumentList=(@($Arguments|ForEach-Object {[YaWindow]::Quote([string]$_)}) -join ' ')}
  if($StandardInput){$start.RedirectStandardInput=$StandardInput}
  $child=Start-Process @start
  [void]$child.Handle
  $record=@{pid=$child.Id;start=$child.StartTime.ToUniversalTime().ToString('o');executable=$FilePath;stdout=$out;stderr=$err;status='running'}
  Write-YaAtomic $meta $record
  try{
    if(-not $child.WaitForExit($TimeoutSeconds*1000)){$record.status='unknown';Write-YaAtomic $meta $record;throw ('NATIVE_TIMEOUT_UNKNOWN: pid='+$child.Id+' may still execute; do not retry or kill')}
    $child.WaitForExit();$record.status='exited';$record['exit_code']=$child.ExitCode;Write-YaAtomic $meta $record
    if($child.ExitCode -ne 0){throw ('NATIVE_FAILED: exit='+$child.ExitCode+'; inspect '+$err)}
    return [pscustomobject]$record
  }finally{$child.Dispose()}
}
function Write-YaReadback {
  param([Parameter(Mandatory=$true)]$Context,[Parameter(Mandatory=$true)][object[]]$Measurements,[Parameter(Mandatory=$true)][string[]]$Artifacts,[string]$Source,[int]$ReaderPid,[string]$ModelSha256)
  $plain=@($Measurements|ForEach-Object {[pscustomobject]@{name=[string]$_.name;value=$_.value}})
  Assert-YaMeasurements $plain
  $reply=@{request=$Context.request;nonce=$Context.nonce;software_version=$Context.software_version;status='READBACK';measurements=$plain;artifacts=@($Artifacts)}
  if($Source){$reply.source=$Source;$reply.reader_pid=$ReaderPid;$reply.model_sha256=$ModelSha256}
  Write-YaAtomic (Join-Path $Context.directory 'Verify.json') $reply
}

function Start-YaDetachedGui {
  param([Parameter(Mandatory=$true)][string]$FilePath,[string[]]$Arguments=@(),[string]$Directory)
  Assert-YaIsolatedPackage $yaToolsPackage
  Assert-YaOperation $yaToolsPackage
  $FilePath=[IO.Path]::GetFullPath($FilePath)
  if(-not $Directory){$Directory=[IO.Path]::GetDirectoryName($FilePath)}
  $Directory=[IO.Path]::GetFullPath($Directory)
  if(-not [IO.File]::Exists($FilePath)){throw 'GUI_START: executable missing'}
  # Breaks away from the Agent job object so teardown cannot kill the target software.
  return [YaWindow]::LaunchInteractive($FilePath, @($Arguments), $Directory)
}
