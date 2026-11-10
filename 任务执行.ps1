param([Parameter(Mandatory=$true)][string]$Software,[Parameter(Mandatory=$true)][string]$Slot,[Parameter(Mandatory=$true)][string]$TaskFile,[string]$RequestId=([guid]::NewGuid().ToString('N')),[ValidateRange(1,1800)][int]$TimeoutSeconds=120,[switch]$RequireInteractive,[switch]$AllowBatch)
$ErrorActionPreference='Stop'
$pkg=$PSScriptRoot
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
. (Join-Path $pkg 'YA插件\真实记录.ps1')
. (Join-Path $pkg '安装卸载\运行时\ya_slots.ps1')
$held=$false;$owns=$false;$runtimeHeld=$false;$oldNonce=$env:YALINK_OPERATION;$sessionGuard=$null;$sessionHeld=$false;$sessionRef=$null
$guard=[Threading.Mutex]::new($false,('Local\YASoftwareOperation-'+[YaEvidence]::Identity($pkg)))
$runtimeGuard=[Threading.Mutex]::new($false,('Local\YARuntime-'+[YaEvidence]::Identity($pkg)))
$operation=Join-Path (Get-YaPackageHudHome $pkg) 'operation.json'
$started=[DateTime]::UtcNow
function Runtime([string[]]$Arguments){
 $lines=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'YA插件\本包命令.ps1') @Arguments)
 $lines|Write-Host
 if($LASTEXITCODE){throw ('RUNTIME_FAILED: '+($Arguments -join ' '))}
 return ($lines -join "`n")
}
function Assert-MethodIdentity {
 if((Get-FileHash -LiteralPath $driver).Hash -cne $driverHash -or (Get-FileHash -LiteralPath $methodFile).Hash -cne $methodHash){throw 'METHOD_CHANGED_DURING_TASK'}
 foreach($dependency in $dependencies){
  if((Get-FileHash -LiteralPath $dependency.path).Hash -cne $dependency.sha256){throw 'METHOD_DEPENDENCY_CHANGED_REVIEW_REQUIRED'}
 }
}
function Worker([string]$Action){
 if($Action -ne 'Execute'){Assert-MethodIdentity}
 $out=Join-Path $job ($Action+'.stdout.log');$err=Join-Path $job ($Action+'.stderr.log')
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$driver+'" -Action '+$Action+' -Context "'+$contextFile+'"'
 $child=Start-Process powershell -WindowStyle Hidden -ArgumentList $args -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 [void]$child.Handle
 Write-YaAtomic (Join-Path $job ($Action+'.process.json')) @{pid=$child.Id;start=$child.StartTime.ToUniversalTime().ToString('o');action=$Action;request=$RequestId;driver_sha256=$driverHash}
 try{
  if(-not $child.WaitForExit($TimeoutSeconds*1000)){throw ('EXECUTION_UNKNOWN: timeout; pid='+$child.Id+' may still execute; do not retry')}
  $child.WaitForExit();if($child.ExitCode -ne 0){throw ('ADAPTER_FAILED: '+$Action+'; inspect '+$out+' and '+$err)}
  $reply=Get-Content -LiteralPath (Join-Path $job ($Action+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
  if($reply.request -cne $RequestId -or $reply.nonce -cne $nonce -or $reply.software_version -cne $method.software_version){throw 'STALE_OR_INCOMPATIBLE_REPLY'}
  Assert-MethodIdentity
  return $reply
 }finally{$child.Dispose()}
}
function Read-YaMeasurementNumber($InputValue) {
 $value=0.0
 if(-not [double]::TryParse([string]$InputValue,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or
   [double]::IsNaN($value) -or [double]::IsInfinity($value)){throw 'INVALID_MEASUREMENT'}
 return $value
}
function CurrentLiveLink {
 if($method.mode -ne 'interactive' -or -not $method.frontend){return $false}
 try{$hudIo=Join-Path (Get-YaPackageHudHome $pkg) 'io';$current=[YaEvidence]::Read((Join-Path $hudIo 'link.json'));return ($current['slot'] -ceq $Slot -and -not [YaEvidence]::CheckCommandChannel($pkg,$hudIo,$current))}catch{return $false}
}
try{
 Assert-YaIsolatedPackage $pkg
 if($RequestId -cnotmatch '^[a-f0-9]{32}$' -or -not (Test-YaSlotId $Slot) -or $Slot -in @('all','generic')){throw 'INPUT: invalid request or software slot'}
 $planHash=(Get-FileHash -LiteralPath $TaskFile).Hash
 $plan=Get-Content -LiteralPath $TaskFile -Raw -Encoding UTF8|ConvertFrom-Json
 if((Get-FileHash -LiteralPath $TaskFile).Hash -cne $planHash){throw 'PLAN_CHANGED_DURING_PREFLIGHT'}
 if($plan.schema -ne 1 -or -not $plan.objective -or -not $plan.title -or @($plan.steps).Count -lt 1 -or @($plan.expected).Count -lt 1 -or -not $plan.applicability -or -not $plan.recovery){throw 'INPUT: task requires objective,title,steps,expected,applicability,recovery'}
 if($plan.steps.Count -gt 20 -or $plan.title.Length -gt 200){throw 'INPUT: task too large'}
 $keywords=Split-YaCommaList ($plan.keywords -join ',')
 Assert-YaExperienceLimits $plan.title '' $keywords @()
 foreach($keyword in $keywords){Assert-YaClean $keyword}
 $recallQuery=if($keywords.Count){$keywords[0]}else{$plan.title}
 $category=if($plan.category){[string]$plan.category}else{'招式'}
 if($category -notin @('招式','坑','零件方案')){throw 'INPUT: category must be 招式,坑,零件方案'}
 foreach($step in $plan.steps){if([string]::IsNullOrWhiteSpace($step.description)){throw 'INPUT: each step needs a method description'}}
 Assert-YaMeasurements $plan.expected
 foreach($expected in $plan.expected){
  if($null -ne $expected.tolerance){
   $null=Read-YaMeasurementNumber $expected.value
   if((Read-YaMeasurementNumber $expected.tolerance) -lt 0){throw 'INPUT: measurement tolerance must be nonnegative'}
  }
 }
 $methodFile=Join-Path $pkg ('连接教练\连接经验\'+$Slot+'\方法.json')
 $methodHash=(Get-FileHash -LiteralPath $methodFile).Hash
 $method=Get-Content -LiteralPath $methodFile -Raw -Encoding UTF8|ConvertFrom-Json
 if($method.schema -ne 1 -or $method.software -ine $Software -or -not $method.software_version -or -not $method.interface -or -not $method.sources -or -not $method.license_review -or -not $method.safety_review -or $method.status -ne 'reviewed'){throw 'METHOD_REVIEW_REQUIRED: record provenance, license, safety, software/version and reviewed status'}
 if($method.mode -notin @('batch','interactive','simulation')){throw 'INPUT: mode must be batch, interactive or simulation'}
 if($RequireInteractive -and $method.mode -ne 'interactive'){throw 'INTERACTIVE_CONNECTION_REQUIRED: Connect requires an interactive frontend method'}
 if($method.mode -eq 'batch' -and -not $AllowBatch){throw 'BATCH_OPT_IN_REQUIRED: 当前方法仅支持后台。用户明确要求后台执行时才使用 Run -AllowBatch'}
 if($method.driver -notmatch '^[a-zA-Z0-9_-]+\.ps1$'){throw 'INVALID_DRIVER: use a local reviewed script basename'}
 $driver=Join-Path (Split-Path $methodFile -Parent) $method.driver
 $driverHash=(Get-FileHash -LiteralPath $driver).Hash
 if($driverHash -cne $method.driver_sha256){throw 'METHOD_CHANGED: review changed code before running'}
 Assert-YaPowerShellFile $driver
 $dependencies=@($method.dependencies | Where-Object {$_})
 if($method.mode -eq 'interactive'){
  if($method.frontend.reader -cnotmatch '^[A-Za-z0-9_-]+\.ps1$'){throw 'FRONTEND_READER_REQUIRED'}
  $reader=Join-Path (Split-Path $methodFile -Parent) $method.frontend.reader
  Assert-YaPowerShellFile $reader
  $dependencies+=@{path=$reader;sha256=$method.frontend.reader_sha256}
 }
 foreach($dependency in $dependencies){
  if(-not [IO.Path]::IsPathRooted([string]$dependency.path) -or $dependency.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'METHOD_DEPENDENCY_REVIEW_REQUIRED'}
 }
 Assert-MethodIdentity
 if($method.mode -eq 'interactive' -and -not $method.frontend){throw 'INTERACTIVE_CONNECTION_REQUIRED: 当前方法没有前台通道配置'}
 if($method.mode -eq 'interactive'){
  $io=Join-Path (Get-YaPackageHudHome $pkg) 'io'
  $linkPath=Join-Path $io 'link.json'
  if(-not [IO.File]::Exists($linkPath)){throw 'INTERACTIVE_CONNECTION_REQUIRED: 当前会话尚未登记可核验的前台通道'}
  $link=[YaEvidence]::Read($linkPath)
  if($link['slot'] -cne $Slot -or [YaEvidence]::CheckCommandChannel($pkg,$io,$link)){throw 'FRONTEND_SESSION_REQUIRED'}
  $sessionGuard=[Threading.Mutex]::new($false,('Local\YAFrontendSession-'+$link['pid']+'-'+$link['process_start']))
  $abandoned=$false
  try{$sessionHeld=$sessionGuard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$sessionHeld=$true;$abandoned=$true}
  if(-not $sessionHeld){throw 'BUSY: another workspace is using this frontend software process'}
  $sessionRef=Join-Path $env:LOCALAPPDATA ('YALink\frontend\'+$link['pid']+'-'+$link['process_start']+'\request.json')
  if(Test-Path -LiteralPath $sessionRef){
   $previous=Get-Content -LiteralPath $sessionRef -Raw -Encoding UTF8|ConvertFrom-Json
   $previousState=Get-Content -LiteralPath $previous.state_file -Raw -Encoding UTF8|ConvertFrom-Json
   if(-not $previous.request -or $previousState.request -cne $previous.request){throw 'RECOVERY_REQUIRED: frontend request identity mismatch'}
   if(-not ($previousState.status -ceq 'prepared' -and $previousState.dispatch_schema -eq 1)){Assert-YaCompletedRequest $previous.state_file}
  }elseif($abandoned){throw 'RECOVERY_REQUIRED: previous frontend owner ended unexpectedly'}
 }
 $held=$guard.WaitOne(0);if(-not $held){throw 'BUSY: another software task owns this workspace'}
 $runtimeHeld=$runtimeGuard.WaitOne(0);if(-not $runtimeHeld){throw 'BUSY: experience state is being updated'}
 Assert-YaOperation $pkg
 $lib=Initialize-YaLibrary $pkg;$resolved=Resolve-YaSlot $lib $Slot
 if($resolved.slot.title -ine $Software){throw 'WRONG_SOFTWARE_SLOT'}
 $work=[YaEvidence]::Work($pkg,$Slot);$job=Join-Path $work $RequestId;$stateFile=Join-Path $job 'request.json'
 if(Test-Path -LiteralPath $stateFile){
  $old=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json
  if($old.plan_hash -cne $planHash -or $old.driver_hash -cne $driverHash -or $old.method_hash -cne $methodHash){throw 'REQUEST_CONFLICT'}
  if($old.status -ne 'completed'){throw 'RECOVERY_REQUIRED: existing incomplete request'}
  Assert-YaCompletedRequest $stateFile
  if($RequireInteractive){$binding=Get-Content -LiteralPath (Join-Path $job 'frontend-session.json') -Raw -Encoding UTF8|ConvertFrom-Json;$active=[YaEvidence]::Read((Join-Path (Join-Path (Get-YaPackageHudHome $pkg) 'io') 'link.json'));if([string]$binding.pid -cne [string]$active['pid'] -or $binding.process_start -cne $active['process_start']){throw 'CACHED_FRONTEND_SESSION_CHANGED: use a new verified task for the current software process'}}
  foreach($artifact in $old.artifacts){if(-not [IO.File]::Exists($artifact.path) -or (Get-FileHash -LiteralPath $artifact.path).Hash -cne $artifact.sha256){throw 'EVIDENCE_CHANGED'}}
  @{status=$(if($old.mode -eq 'simulation'){'SIMULATED'}elseif($old.mode -eq 'batch'){'VERIFIED_BATCH'}else{'VERIFIED_EXECUTION'});cached=$true;request=$RequestId;mode=$old.mode;live_link=(CurrentLiveLink)}|ConvertTo-Json;exit 0
 }
 if($RequireInteractive){
  $shown=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'YA插件\show_ya.ps1') -WithSoftware)
  if($LASTEXITCODE){throw ('FRONTEND_NOT_VISIBLE_BEFORE_EXECUTION: '+($shown -join ' '))}
  $proof=($shown -join [Environment]::NewLine)|ConvertFrom-Json
  $visibleLink=[YaEvidence]::Read($linkPath)
  if($proof.software_visible -ne $true -or [string]$proof.software_pid -cne [string]$link['pid'] -or $visibleLink['session'] -cne $link['session'] -or $visibleLink['process_start'] -cne $link['process_start']){throw 'FRONTEND_SESSION_CHANGED_BEFORE_EXECUTION'}
 }
 if(Test-Path -LiteralPath $job){throw 'REQUEST_CONFLICT: preflight evidence exists; use a new request'}
 $nonce=[guid]::NewGuid().ToString('N');$env:YALINK_OPERATION=$nonce
 $used=@()
 $workspace=Split-Path $pkg -Parent
 $mappingFile=Join-Path $workspace '迁移待核验.json'
 $mapping=if(Test-Path -LiteralPath $mappingFile){Get-Content -LiteralPath $mappingFile -Raw -Encoding UTF8|ConvertFrom-Json}
 foreach($use in @($plan.used_experiences)){
  if(-not $use){continue}
  if(-not $use.reason -or -not $use.applicability_check -or @($use.steps).Count -eq 0){throw 'INPUT: explain how each old method applies to this task and which steps use it'}
  $record=Read-YaJsonFile (Get-YaFormalFile $resolved.dir $use.id)
  if($record.lifecycle -eq 'withdrawn' -or -not $record.independently_verified -or $record.context.software_version -cne $method.software_version -or $record.context.interface -cne $method.interface){throw 'EXPERIENCE_REVALIDATION_REQUIRED'}
  foreach($e in $record.context.artifacts){
   $evidencePath=[IO.Path]::GetFullPath([string]$e.path)
   if($mapping -and $mapping.destination -ieq $workspace){
    foreach($origin in (@($mapping.source)+@($mapping.origins) | Where-Object {$_})){
     $prefix=[IO.Path]::GetFullPath($origin).TrimEnd('\')+'\'
     if($evidencePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
      $evidencePath=Join-Path $workspace $evidencePath.Substring($prefix.Length)
      break
     }
    }
   }
   if(-not [IO.File]::Exists($evidencePath) -or (Get-FileHash -LiteralPath $evidencePath).Hash -cne $e.sha256){throw 'EXPERIENCE_EVIDENCE_CHANGED'}
  }
  foreach($n in $use.steps){if($n -isnot [int] -or $n -lt 0 -or $n -ge $plan.steps.Count){throw 'INPUT: experience step index out of range'}}
  $used+=@{id=$use.id;reason=$use.reason;applicability_check=$use.applicability_check;steps=$use.steps;sha256=(Get-FileHash -LiteralPath (Get-YaFormalFile $resolved.dir $use.id)).Hash}
 }
 $contextFile=Join-Path $job 'task.json'
 Write-YaAtomic $contextFile @{schema=1;request=$RequestId;nonce=$nonce;slot=$Slot;timeout_seconds=$TimeoutSeconds;software=$Software;software_version=$method.software_version;interface=$method.interface;directory=$job;plan=$plan;used_experiences=$used;driver_sha256=$driverHash}
 $check=Worker 'Check';if($check.status -ne 'READY'){throw 'SOFTWARE_NOT_READY'}
 if($RequireInteractive){
  $binding=[YaEvidence]::Read((Join-Path $job 'frontend-session.json'))
  foreach($key in @('session','pid','process_start')){
   if([string]$binding[$key] -cne [string]$link[$key]){throw 'FRONTEND_SESSION_CHANGED_BEFORE_EXECUTION'}
  }
 }
 $runtimeGuard.ReleaseMutex();$runtimeHeld=$false
 $draftPath=Join-Path (Split-Path $methodFile -Parent) '方法.草稿.json'
 if(Test-Path -LiteralPath $draftPath){
  $draft=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8|ConvertFrom-Json
  $preparation=Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($draft.preparation_task -and $preparation.current.id -ceq $draft.preparation_task -and $preparation.current.tag -ceq 'connection_preparation' -and $preparation.current.slot -ceq $Slot -and $preparation.current.status -in @('进行中','自检通过')){$null=Runtime @('step_hand','note=连接准备资料保留，转入正式任务；准备阶段不计工程验收成功')}
 }
 $null=Runtime @('task_open',('slot='+$Slot),('tag='+$RequestId),('title='+$plan.title))
 $flowId=(Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8|ConvertFrom-Json).current.id
 $null=Runtime @('exp_recall',('slot='+$Slot),('task='+$flowId),('q='+$recallQuery),('version='+$method.software_version),('interface='+$method.interface))
 foreach($use in $used){$null=Runtime @('exp_get',('slot='+$Slot),('id='+$use.id))}
 $runtimeHeld=$runtimeGuard.WaitOne(10000);if(-not $runtimeHeld){throw 'BUSY: experience state is being updated'}
 foreach($use in $used){
  if((Get-FileHash -LiteralPath (Get-YaFormalFile $resolved.dir $use.id)).Hash -cne $use.sha256){throw 'EXPERIENCE_CHANGED_BEFORE_DISPATCH'}
 }
 Assert-MethodIdentity
 $currentFlow=Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($currentFlow.current.id -cne $flowId -or $currentFlow.current.tag -cne $RequestId){throw 'TASK_FLOW_CHANGED_BEFORE_DISPATCH'}
 Write-YaAtomic $stateFile @{status='prepared';dispatch_schema=1;request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash}
 Write-YaAtomic (Join-Path (Get-YaPackageHudHome $pkg) 'operation_request.json') @{request=$RequestId;state_file=$stateFile}
 if($sessionRef){
  try{Write-YaAtomic $sessionRef @{request=$RequestId;state_file=$stateFile;package_id=[YaEvidence]::Identity($pkg)}}
  catch{throw ('FRONTEND_GUARD_WRITE_REQUIRED: 跨工作区防止重复执行，需要写入 '+$sessionRef+'；尚未派发。'+$_.Exception.Message)}
 }
 Write-YaAtomic $operation @{status='pending';request=$RequestId;nonce=$nonce;owner_pid=$PID;owner_start=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString();time=[DateTime]::UtcNow.ToString('o')}
 Assert-MethodIdentity
 Write-YaAtomic $stateFile @{status='dispatched';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash}
 $owns=$true
 $phase='EXECUTION_UNKNOWN'
 $runtimeGuard.ReleaseMutex();$runtimeHeld=$false
 $executed=Worker 'Execute'
 if($executed.status -cne 'EXECUTED'){throw 'EXECUTION_RECEIPT_SCHEMA: Execute must return status=EXECUTED'}
 $phase='EXECUTED_AWAITING_VERIFICATION'
 Write-YaAtomic $stateFile @{status='executed';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash}
 $verified=Worker 'Verify'
 Assert-YaMeasurements $verified.measurements
 if($verified.status -ne 'READBACK' -or @($verified.measurements).Count -eq 0){throw 'INDEPENDENT_READBACK_MISSING'}
 $proof=@()
 foreach($expected in $plan.expected){
  $actual=@($verified.measurements|Where-Object {$_.name -ceq $expected.name})
  if($actual.Count -ne 1){throw ('MISSING_MEASUREMENT: '+$expected.name)}
  if($null -ne $expected.tolerance){
   $target=Read-YaMeasurementNumber $expected.value
   $value=Read-YaMeasurementNumber $actual[0].value
   $tolerance=Read-YaMeasurementNumber $expected.tolerance
   if([Math]::Abs($target-$value) -gt $tolerance){throw ('RESULT_MISMATCH: '+$expected.name)}
  }elseif([string]$actual[0].value -cne [string]$expected.value){throw ('RESULT_MISMATCH: '+$expected.name)}
  $proof+=@{name=$expected.name;expected=$expected.value;actual=$actual[0].value;tolerance=$expected.tolerance}
 }
 $artifacts=@()
 foreach($file in @($verified.artifacts)){
  if([string]::IsNullOrWhiteSpace([string]$file)){throw 'INVALID_ARTIFACT: adapter returned an empty evidence path; preserve this request and repair the driver'}
  $path=[IO.Path]::GetFullPath([string]$file)
  if(-not $path.StartsWith($job+'\',[StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($path)){throw 'EVIDENCE_OUTSIDE_CURRENT_TASK'}
  $artifacts+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash}
 }
 if($artifacts.Count -eq 0){throw 'ARTIFACTS_REQUIRED'}
 $phase='VERIFIED_AWAITING_RECORD'
 Write-YaAtomic (Join-Path $job 'verification.json') @{request=$RequestId;nonce=$nonce;mode=$method.mode;verify_sha256=(Get-FileHash -LiteralPath (Join-Path $job 'Verify.json')).Hash;measurements=$proof;artifacts=$artifacts}
 $methodShape=ConvertTo-Json -InputObject @{steps=@($plan.steps);checks=@($plan.expected|ForEach-Object {$_.name});applicability=$plan.applicability;category=$category} -Depth 30 -Compress
 $context=@{used_general_cards=@($plan.used_general_cards|Where-Object{$_}|ForEach-Object{[string]$_.id});method_shape=$methodShape;experience_reason=$plan.experience_reason;task=$flowId;request=$RequestId;software=$Software;software_version=$method.software_version;interface=$method.interface;parameters=$plan.parameters;artifacts=$artifacts;job=$job;driver_hash=$driverHash;plan_hash=$planHash;used_experiences=$used;source_review=$method.sources;outcome='success'}
 $recipe=@{schema=1;title=$plan.title;objective=$plan.objective;conditions=@{slot=$Slot;software=$Software;version=$method.software_version;interface=$method.interface;parameters=$plan.parameters};steps=@($plan.steps|ForEach-Object {$_.description});verification=@{check='独立适配器进程重新读取软件结果，由核心与执行前目标逐项比较';evidence=@($artifacts.path);claimed_result='verified task readback'};recovery=$plan.recovery;applicability=$plan.applicability;source='本次任务、适配器原始日志、独立读取与核心对照'}
 $recipeFile=Join-Path $job 'method-record.json';Write-YaAtomic $recipeFile $recipe
 $sameMethod=$null
 if($method.mode -ne 'simulation' -and $used.Count -eq 1 -and @($used[0].steps|Select-Object -Unique).Count -eq $plan.steps.Count){
  $candidate=Read-YaJsonFile (Get-YaFormalFile $resolved.dir $used[0].id)
  if($candidate.context.method_shape -ceq $methodShape){$sameMethod=$candidate}
 }
 if($sameMethod){
  $full=$sameMethod;$saved=@{id=$sameMethod.id}
 }else{
 $draft=Runtime @('exp_done',('slot='+$Slot),('tag='+$RequestId),('c='+$category),('k='+ ($keywords -join ',')),('record='+$recipeFile))
 $draftId=([regex]::Match($draft,'(?m)^draft:\s*(\S+)')).Groups[1].Value
 if(-not $draftId){throw 'DRAFT_SAVE_FAILED'}
 $full=[pscustomobject]@{verification_state='simulation_only'};$saved=@{id=$draftId}
 if($method.mode -ne 'simulation'){
 $runtimeHeld=$runtimeGuard.WaitOne(10000);if(-not $runtimeHeld){throw 'BUSY: cannot commit experience'}
 $saved=Publish-YaDraft $resolved.dir $Slot $draftId ($recipe.steps -join '; ') $proof $context
 $fullFile=Get-YaFormalFile $resolved.dir $saved.id;$full=Read-YaJsonFile $fullFile
 $full.independently_verified=($method.mode -ne 'simulation');$full.verification_state=$(if($method.mode -eq 'simulation'){'simulation_only'}else{'independent_adapter_readback'});$full|Add-Member -NotePropertyName lifecycle -NotePropertyValue active -Force
 Write-YaJsonFile $fullFile $full
 $runtimeGuard.ReleaseMutex();$runtimeHeld=$false
 }
 }
 $eventKind=if($method.mode -eq 'simulation'){'validation_simulated'}else{'experience_verified'}
 Add-YaActualEvent $pkg $eventKind @{task=$flowId;request=$RequestId;slot=$Slot;experience=$saved.id;context=$context;reused_experience=$(if($used.Count){$used[0].id}else{''});used_experiences=$used;verification=$full.verification_state;elapsed_ms=([DateTime]::UtcNow-$started).TotalMilliseconds;mode=$method.mode}
 Write-YaAtomic (Join-Path (Split-Path $methodFile -Parent) '连接验证.json') @{software=$Software;version=$method.software_version;driver_hash=$driverHash;mode=$method.mode;verified=($method.mode -ne 'simulation');request=$RequestId;evidence=$job;time=[DateTime]::UtcNow.ToString('o');live_link=(CurrentLiveLink)}
 foreach($name in @('search','compare','draft','claim','inspect')){$null=Runtime @('step_check',('item='+$name),'pass=1','note=本次软件独立回读与执行前验收值比较通过')}
 $null=Runtime @('step_finish');$null=Runtime @('step_accept','note=工具验收通过；不替代生产工程审查')
 $receipts=@('task.json','Check.json','Execute.json','Verify.json')|ForEach-Object {@{file=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $job $_)).Hash}}
 Write-YaAtomic $stateFile @{status='completed';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash;experience=$saved.id;artifacts=$artifacts;mode=$method.mode;used_experiences=$used;receipts=@($receipts)}
 $owns=$false
 try{Write-YaAtomic $operation @{status='completed';request=$RequestId;time=[DateTime]::UtcNow.ToString('o')}}
 catch{Write-Warning ('请求已独立核验并保存，运行摘要写入失败。请用 Reconcile 查看原请求。'+$_.Exception.Message)}
 @{status=$(if($method.mode -eq 'simulation'){'SIMULATED'}elseif($method.mode -eq 'batch'){'VERIFIED_BATCH'}else{'VERIFIED_EXECUTION'});request=$RequestId;experience=$saved.id;mode=$method.mode;live_link=(CurrentLiveLink);token='未统计（除非另接真实用量源）';savings='待对照';evidence=$job}|ConvertTo-Json -Depth 8
}catch{
 $errorText=$_.Exception.Message
 if(-not $owns -and $flowId){
  if($runtimeHeld){$runtimeGuard.ReleaseMutex();$runtimeHeld=$false}
  try{
   $flow=Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8|ConvertFrom-Json
   if($flow.current.id -ceq $flowId -and $flow.current.tag -ceq $RequestId){$null=Runtime @('step_hand','note=预检未通过，未派发软件任务')}
  }catch{}
 }
 if($owns){
  try{
   Write-YaAtomic (Join-Path $job 'failure.json') @{request=$RequestId;error=$errorText;time=[DateTime]::UtcNow.ToString('o');status='unresolved';plan=$plan}
   if($method.mode -ne 'simulation'){
    Write-YaAtomic (Join-Path $resolved.dir ('_风险\'+$RequestId+'.json')) @{
     request=$RequestId;title=$plan.title;keywords=$keywords;software_version=$method.software_version;interface=$method.interface
     phase=$phase;status='unresolved';note='发生过执行异常，先核对软件与产物，避免重复操作。'
    }
   }
   Add-YaActualEvent $pkg 'reference_failed' @{task=$RequestId;slot=$Slot;error=$errorText;directory=$job}
   $null=Runtime @('exp_recall',('slot='+$Slot),('task='+$flowId),('q='+$recallQuery),('version='+$method.software_version),('interface='+$method.interface))
   $failureRecipe=@{schema=1;title=('待排查：'+$plan.title);objective=$plan.objective;conditions=@{slot=$Slot;software=$Software;version=$method.software_version;interface=$method.interface;parameters=$plan.parameters};steps=@('查看本次原始执行和独立回读日志','核对软件是否迟到执行，未经核查不重复操作');verification=@{check='尚未找到并验证修复方式';evidence=@((Join-Path $job 'failure.json'));claimed_result='FAIL: '+$errorText};recovery='保留请求状态、日志和模型，人工核查；解决后另记恢复证据';applicability=$plan.applicability;source='本次真实失败；原因和解决办法仍待查证'}
   $failureRecipeFile=Join-Path $job 'pitfall-draft.json';Write-YaAtomic $failureRecipeFile $failureRecipe
   $null=Runtime @('exp_done',('slot='+$Slot),('tag='+$RequestId),'c=坑',('record='+$failureRecipeFile))
   $null=Runtime @('step_hand','note=执行失败，保留现场和待排查坑草稿')
  }catch{}
  try{Write-YaAtomic $operation @{status='blocked';phase=$phase;request=$RequestId;error=$errorText;state_file=$stateFile;time=[DateTime]::UtcNow.ToString('o')}}catch{}
 }
 @{status=$(if($owns){$phase}else{'PRECHECK_FAILED'});error=$errorText;operation=$operation;next=$(if($owns){'保留状态与软件结果，先运行 Reconcile'}else{'尚未派发，修正预检问题后可使用新请求'})}|ConvertTo-Json;exit 1
}finally{if($runtimeHeld){$runtimeGuard.ReleaseMutex()};if($held){$guard.ReleaseMutex()};if($sessionHeld){$sessionGuard.ReleaseMutex()};if($sessionGuard){$sessionGuard.Dispose()};$runtimeGuard.Dispose();$guard.Dispose();$env:YALINK_OPERATION=$oldNonce}
