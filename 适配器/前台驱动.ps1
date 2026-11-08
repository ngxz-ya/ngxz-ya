param([Parameter(Mandatory=$true)][ValidateSet('Check','Execute','Verify')][string]$Action,
      [Parameter(Mandatory=$true)][string]$Context)
$ErrorActionPreference='Stop'
$pkg=Split-Path $PSScriptRoot -Parent
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
. (Join-Path $pkg 'YA插件\真实记录.ps1')
try {
 Assert-YaIsolatedPackage $pkg
 $c=Get-Content -LiteralPath $Context -Raw -Encoding UTF8|ConvertFrom-Json
 if($c.request -cnotmatch '^[a-f0-9]{32}$' -or $c.nonce -cnotmatch '^[a-f0-9]{32}$' -or $c.slot -cnotmatch '^[a-z][a-z0-9_-]{0,31}$'){throw 'INVALID_TASK_CONTEXT'}
 $local=Join-Path $pkg ('连接教练\连接经验\'+$c.slot)
 $method=Get-Content -LiteralPath (Join-Path $local '方法.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $f=$method.frontend
 if($method.mode -ne 'interactive' -or $method.software_version -cne $c.software_version -or $f.bridge_sha256 -cnotmatch '^[A-F0-9]{64}$' -or $f.extension -cnotmatch '^[a-z0-9]{1,10}$' -or $f.reader -cnotmatch '^[A-Za-z0-9_-]+\.ps1$'){throw 'FRONTEND_METHOD_REQUIRED'}
 $reader=Join-Path $local $f.reader
 if((Get-FileHash -LiteralPath $reader).Hash -cne $f.reader_sha256){throw 'READER_CHANGED_REVIEW_REQUIRED'}
 $io=Join-Path (Get-YaPackageHudHome $pkg) 'io'
 $link=[YaEvidence]::Read((Join-Path $io 'link.json'))
 if($link['slot'] -cne $c.slot -or [YaEvidence]::CheckCommandChannel($pkg,$io,$link)){throw 'FRONTEND_SESSION_REQUIRED'}
 $bindingFile=Join-Path $c.directory 'frontend-session.json'
 $model=Join-Path $c.directory ('model.'+$f.extension)
 if($Action -eq 'Check') {
  Write-YaAtomic $bindingFile @{session=$link['session'];pid=$link['pid'];process_start=$link['process_start'];bridge_sha256=$f.bridge_sha256}
 } else {
  $binding=Get-Content -LiteralPath $bindingFile -Raw -Encoding UTF8|ConvertFrom-Json
  if($binding.session -cne $link['session'] -or [string]$binding.pid -cne [string]$link['pid'] -or $binding.process_start -cne $link['process_start'] -or $binding.bridge_sha256 -cne $f.bridge_sha256){throw 'FRONTEND_SESSION_CHANGED'}
 }
 if($Action -eq 'Verify') {
  $executed=Get-Content -LiteralPath (Join-Path $c.directory 'Execute.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if(-not [IO.File]::Exists($model) -or (Get-FileHash -LiteralPath $model).Hash -cne $executed.saved_sha256){throw 'SAVED_MODEL_MISSING_OR_CHANGED'}
  # The independent reader receives the actual saved file, never expected measurements or task parameters.
  $inputFile=Join-Path $c.directory 'reader-input.json'
  Write-YaAtomic $inputFile @{request=$c.request;nonce=$c.nonce;software_version=$c.software_version;directory=$c.directory;model=$model;model_sha256=$executed.saved_sha256;frontend_pid=$link['pid']}
  & powershell -NoProfile -ExecutionPolicy Bypass -File $reader -Context $inputFile
  if($LASTEXITCODE){throw 'INDEPENDENT_READER_FAILED'}
  $reply=Get-Content -LiteralPath (Join-Path $c.directory 'Verify.json') -Raw -Encoding UTF8|ConvertFrom-Json
  $readerPid=0
  if($reply.status -cne 'READBACK' -or $reply.source -cne 'independent_software_reopen' -or -not [int]::TryParse([string]$reply.reader_pid,[ref]$readerPid) -or $readerPid -le 0 -or $readerPid -eq [int]$link['pid'] -or $reply.model_sha256 -cne $executed.saved_sha256 -or $reply.request -cne $c.request -or $reply.nonce -cne $c.nonce -or $reply.software_version -cne $c.software_version){throw 'INDEPENDENT_REOPEN_EVIDENCE_REQUIRED'}
  if((Get-FileHash -LiteralPath $model).Hash -cne $executed.saved_sha256){throw 'MODEL_CHANGED_DURING_VERIFY'}
  if(@($reply.artifacts) -notcontains $model){throw 'SAVED_MODEL_ARTIFACT_REQUIRED'}
 } else {
  $proof=[YaEvidence]::Read((Join-Path ([YaEvidence]::Work($pkg,$c.slot)) ($link['session']+'\readback.json')))
  $message=New-Object 'Collections.Generic.Dictionary[string,object]'
  foreach($pair in @{protocol='ngxz-ya/frontend-task/1';action=$Action;request=$c.request;nonce=$c.nonce}.GetEnumerator()){$message[$pair.Key]=$pair.Value}
  if($Action -eq 'Execute'){$message['parameters']=$c.plan.parameters;$message['steps']=@($c.plan.steps);$message['output_path']=$model}
  $message=[System.Web.Script.Serialization.JavaScriptSerializer]::new().DeserializeObject((ConvertTo-Json -InputObject $message -Depth 30 -Compress))
  $budget=[Math]::Max(1000,([int]$c.timeout_seconds*1000)-5000)
  $result=[YaEvidence]::SendMessage([string]$proof['probe_pipe'],[int]$link['pid'],[string]$link['process_start'],$message,$budget)
  if($result['ok'] -ne $true -or $result['software_version'] -cne $c.software_version -or $result['bridge_sha256'] -cne $f.bridge_sha256){throw ('FRONTEND_REPLY_FAILED: '+[string]$result['error'])}
  if($Action -eq 'Check' -and $result['status'] -cne 'READY'){throw 'FRONTEND_NOT_READY'}
  if($Action -eq 'Execute'){
   if($result['status'] -cne 'EXECUTED' -or [string]$result['saved_file'] -ine $model -or -not [IO.File]::Exists($model) -or (Get-Item -LiteralPath $model).Length -eq 0){throw 'SOFTWARE_SAVE_REQUIRED'}
   $result['saved_sha256']=(Get-FileHash -LiteralPath $model).Hash
  }
  Write-YaAtomic (Join-Path $c.directory ($Action+'.json')) $result
 }
 $now=[YaEvidence]::Read((Join-Path $io 'link.json'))
 if($now['session'] -cne $link['session'] -or [YaEvidence]::CheckCommandChannel($pkg,$io,$now)){throw 'FRONTEND_SESSION_CHANGED'}
 Write-Output ('RESULT: '+$Action+' OK');exit 0
} catch { Write-Output ('error: '+$_.Exception.Message);Write-Output 'RESULT: FAIL';exit 1 }
