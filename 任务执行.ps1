param([Parameter(Mandatory=$true)][string]$Software,[Parameter(Mandatory=$true)][string]$Slot,[Parameter(Mandatory=$true)][string]$TaskFile,[string]$RequestId=([guid]::NewGuid().ToString('N')),[ValidateRange(1,1800)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$pkg=$PSScriptRoot
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
. (Join-Path $pkg 'YA插件\真实记录.ps1')
. (Join-Path $pkg '安装卸载\运行时\ya_slots.ps1')
$held=$false;$owns=$false;$runtimeHeld=$false;$oldNonce=$env:YALINK_OPERATION
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
function Worker([string]$Action){
 if((Get-FileHash -LiteralPath $driver).Hash -cne $driverHash -or (Get-FileHash -LiteralPath $methodFile).Hash -cne $methodHash){throw 'METHOD_CHANGED_DURING_TASK'}
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
  return $reply
 }finally{$child.Dispose()}
}
try{
 Assert-YaIsolatedPackage $pkg
 if($RequestId -cnotmatch '^[a-f0-9]{32}$' -or -not (Test-YaSlotId $Slot) -or $Slot -in @('all','generic')){throw 'INPUT: invalid request or software slot'}
 $plan=Get-Content -LiteralPath $TaskFile -Raw -Encoding UTF8|ConvertFrom-Json
 if($plan.schema -ne 1 -or -not $plan.objective -or -not $plan.title -or @($plan.steps).Count -lt 1 -or @($plan.expected).Count -lt 1 -or -not $plan.applicability -or -not $plan.recovery){throw 'INPUT: task requires objective,title,steps,expected,applicability,recovery'}
 if($plan.steps.Count -gt 20 -or $plan.title.Length -gt 200){throw 'INPUT: task too large'}
 $category=if($plan.category){[string]$plan.category}else{'招式'}
 if($category -notin @('招式','坑','零件方案')){throw 'INPUT: category must be 招式,坑,零件方案'}
 foreach($step in $plan.steps){if([string]::IsNullOrWhiteSpace($step.description)){throw 'INPUT: each step needs a method description'}}
 $names=@{};foreach($expected in $plan.expected){if(-not $expected.name -or $null -eq $expected.value -or $names.ContainsKey($expected.name)){throw 'INPUT: expected measurements need unique names and values'};$names[$expected.name]=$true}
 $methodFile=Join-Path $pkg ('连接教练\连接经验\'+$Slot+'\方法.json')
 $method=Get-Content -LiteralPath $methodFile -Raw -Encoding UTF8|ConvertFrom-Json
 $methodHash=(Get-FileHash -LiteralPath $methodFile).Hash
 if($method.schema -ne 1 -or $method.software -ine $Software -or -not $method.software_version -or -not $method.interface -or -not $method.sources -or -not $method.license_review -or -not $method.safety_review -or $method.status -ne 'reviewed'){throw 'METHOD_REVIEW_REQUIRED: record provenance, license, safety, software/version and reviewed status'}
 if($method.mode -notin @('batch','interactive','simulation')){throw 'INPUT: mode must be batch, interactive or simulation'}
 if($method.driver -notmatch '^[a-zA-Z0-9_-]+\.ps1$'){throw 'INVALID_DRIVER: use a local reviewed script basename'}
 $driver=Join-Path (Split-Path $methodFile -Parent) $method.driver
 $driverHash=(Get-FileHash -LiteralPath $driver).Hash
 if($driverHash -cne $method.driver_sha256){throw 'METHOD_CHANGED: review changed code before running'}
 $held=$guard.WaitOne(0);if(-not $held){throw 'BUSY: another software task owns this workspace'}
 $runtimeHeld=$runtimeGuard.WaitOne(0);if(-not $runtimeHeld){throw 'BUSY: experience state is being updated'}
 Assert-YaOperation $pkg
 $lib=Initialize-YaLibrary $pkg;$resolved=Resolve-YaSlot $lib $Slot
 if($resolved.slot.title -ine $Software){throw 'WRONG_SOFTWARE_SLOT'}
 $work=[YaEvidence]::Work($pkg,$Slot);$job=Join-Path $work $RequestId;$stateFile=Join-Path $job 'request.json'
 $planHash=(Get-FileHash -LiteralPath $TaskFile).Hash
 if(Test-Path -LiteralPath $stateFile){
  $old=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json
  if($old.plan_hash -cne $planHash -or $old.driver_hash -cne $driverHash -or $old.method_hash -cne $methodHash){throw 'REQUEST_CONFLICT'}
  if($old.status -ne 'completed'){throw 'RECOVERY_REQUIRED: existing incomplete request'}
  foreach($artifact in $old.artifacts){if(-not [IO.File]::Exists($artifact.path) -or (Get-FileHash -LiteralPath $artifact.path).Hash -cne $artifact.sha256){throw 'EVIDENCE_CHANGED'}}
  @{status=$(if($old.mode -eq 'simulation'){'SIMULATED'}elseif($old.mode -eq 'batch'){'VERIFIED_BATCH'}else{'VERIFIED_EXECUTION'});cached=$true;request=$RequestId;mode=$old.mode;live_link=$false}|ConvertTo-Json;exit 0
 }
 $nonce=[guid]::NewGuid().ToString('N');$env:YALINK_OPERATION=$nonce
 Write-YaAtomic $stateFile @{status='prepared';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash}
 Write-YaAtomic (Join-Path (Get-YaPackageHudHome $pkg) 'operation_request.json') @{request=$RequestId;state_file=$stateFile}
 Write-YaAtomic $operation @{status='pending';request=$RequestId;nonce=$nonce;owner_pid=$PID;owner_start=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString();time=[DateTime]::UtcNow.ToString('o')}
 $owns=$true
 $runtimeGuard.ReleaseMutex();$runtimeHeld=$false
 $null=Runtime @('task_open',('slot='+$Slot),('tag='+$RequestId),('title='+$plan.title))
 $flowId=(Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8|ConvertFrom-Json).current.id
 $null=Runtime @('exp_recall',('slot='+$Slot),('tag='+$RequestId),('q='+$plan.title))
 $used=@()
 foreach($use in @($plan.used_experiences)){
  if(-not $use){continue}
  if(Test-Path -LiteralPath (Join-Path (Split-Path $pkg -Parent) '迁移待核验.json')){throw 'MIGRATION_REVALIDATION_REQUIRED: read old methods as guidance, revalidate in this environment before claiming reuse'}
  if(-not $use.reason -or -not $use.applicability_check -or @($use.steps).Count -eq 0){throw 'INPUT: explain how each old method applies to this task and which steps use it'}
  $record=Read-YaJsonFile (Get-YaFormalFile $resolved.dir $use.id)
  if($record.lifecycle -eq 'withdrawn' -or -not $record.independently_verified -or $record.context.software_version -cne $method.software_version -or $record.context.interface -cne $method.interface){throw 'EXPERIENCE_REVALIDATION_REQUIRED'}
  foreach($e in $record.context.artifacts){if(-not [IO.File]::Exists($e.path) -or (Get-FileHash -LiteralPath $e.path).Hash -cne $e.sha256){throw 'EXPERIENCE_EVIDENCE_CHANGED'}}
  foreach($n in $use.steps){if($n -isnot [int] -or $n -lt 0 -or $n -ge $plan.steps.Count){throw 'INPUT: experience step index out of range'}}
  $null=Runtime @('exp_get',('slot='+$Slot),('id='+$use.id))
  $used+=@{id=$use.id;reason=$use.reason;applicability_check=$use.applicability_check;steps=$use.steps;sha256=(Get-FileHash -LiteralPath (Get-YaFormalFile $resolved.dir $use.id)).Hash}
 }
 $contextFile=Join-Path $job 'task.json'
 Write-YaAtomic $contextFile @{schema=1;request=$RequestId;nonce=$nonce;software=$Software;software_version=$method.software_version;interface=$method.interface;directory=$job;plan=$plan;used_experiences=$used;driver_sha256=$driverHash}
 $check=Worker 'Check';if($check.status -ne 'READY'){throw 'SOFTWARE_NOT_READY'}
 Write-YaAtomic $stateFile @{status='dispatched';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash}
 $executed=Worker 'Execute'
 $verified=Worker 'Verify'
 if($verified.status -ne 'READBACK' -or @($verified.measurements).Count -eq 0){throw 'INDEPENDENT_READBACK_MISSING'}
 $proof=@()
 foreach($expected in $plan.expected){
  $actual=@($verified.measurements|Where-Object {$_.name -ceq $expected.name})
  if($actual.Count -ne 1){throw ('MISSING_MEASUREMENT: '+$expected.name)}
  if($null -ne $expected.tolerance){
   $target=0.0;$value=0.0;$tolerance=0.0
   foreach($v in @($expected.value,$actual[0].value,$expected.tolerance)){if(-not [double]::TryParse([string]$v,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or [double]::IsNaN($value) -or [double]::IsInfinity($value)){throw 'INVALID_MEASUREMENT'}}
   $target=[double]$expected.value;$value=[double]$actual[0].value;$tolerance=[double]$expected.tolerance
   if($tolerance -lt 0 -or [Math]::Abs($target-$value) -gt $tolerance){throw ('RESULT_MISMATCH: '+$expected.name)}
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
 $context=@{task=$flowId;request=$RequestId;software=$Software;software_version=$method.software_version;interface=$method.interface;parameters=$plan.parameters;artifacts=$artifacts;job=$job;driver_hash=$driverHash;plan_hash=$planHash;used_experiences=$used;source_review=$method.sources;outcome='success'}
 $recipe=@{schema=1;title=$plan.title;objective=$plan.objective;conditions=@{slot=$Slot;software=$Software;version=$method.software_version;interface=$method.interface;parameters=$plan.parameters};steps=@($plan.steps|ForEach-Object {$_.description});verification=@{check='独立适配器进程重新读取软件结果，由核心与执行前目标逐项比较';evidence=@($artifacts.path);claimed_result='verified task readback'};recovery=$plan.recovery;applicability=$plan.applicability;source='本次任务、适配器原始日志、独立读取与核心对照'}
 $recipeFile=Join-Path $job 'method-record.json';Write-YaAtomic $recipeFile $recipe
 $draft=Runtime @('exp_done',('slot='+$Slot),('tag='+$RequestId),('c='+$category),('record='+$recipeFile))
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
 $eventKind=if($method.mode -eq 'simulation'){'validation_simulated'}else{'experience_verified'}
 Add-YaActualEvent $pkg $eventKind @{task=$flowId;request=$RequestId;slot=$Slot;experience=$saved.id;context=$context;reused_experience=$(if($used.Count){$used[0].id}else{''});used_experiences=$used;verification=$full.verification_state;elapsed_ms=([DateTime]::UtcNow-$started).TotalMilliseconds;mode=$method.mode}
 Write-YaAtomic (Join-Path (Split-Path $methodFile -Parent) '连接验证.json') @{software=$Software;version=$method.software_version;driver_hash=$driverHash;mode=$method.mode;verified=($method.mode -ne 'simulation');request=$RequestId;evidence=$job;time=[DateTime]::UtcNow.ToString('o');live_link=$false}
 foreach($name in @('search','compare','draft','claim','inspect')){$null=Runtime @('step_check',('item='+$name),'pass=1','note=本次软件独立回读与执行前验收值比较通过')}
 $null=Runtime @('step_finish');$null=Runtime @('step_accept','note=工具验收通过；不替代生产工程审查')
 Write-YaAtomic $stateFile @{status='completed';request=$RequestId;plan_hash=$planHash;driver_hash=$driverHash;method_hash=$methodHash;experience=$saved.id;artifacts=$artifacts;mode=$method.mode;used_experiences=$used}
 Write-YaAtomic $operation @{status='completed';request=$RequestId;time=[DateTime]::UtcNow.ToString('o')}
 @{status=$(if($method.mode -eq 'simulation'){'SIMULATED'}elseif($method.mode -eq 'batch'){'VERIFIED_BATCH'}else{'VERIFIED_EXECUTION'});request=$RequestId;experience=$saved.id;mode=$method.mode;live_link=$false;token='未统计（除非另接真实用量源）';savings='待对照';evidence=$job}|ConvertTo-Json -Depth 8
}catch{
 $errorText=$_.Exception.Message
 if($owns){
  try{
   Write-YaAtomic (Join-Path $job 'failure.json') @{request=$RequestId;error=$errorText;time=[DateTime]::UtcNow.ToString('o');status='unresolved';plan=$plan}
   Add-YaActualEvent $pkg 'reference_failed' @{task=$RequestId;slot=$Slot;error=$errorText;directory=$job}
   $null=Runtime @('exp_recall',('slot='+$Slot),('tag='+$RequestId),('q='+$plan.title))
   $failureRecipe=@{schema=1;title=('待排查：'+$plan.title);objective=$plan.objective;conditions=@{slot=$Slot;software=$Software;version=$method.software_version;interface=$method.interface;parameters=$plan.parameters};steps=@('查看本次原始执行和独立回读日志','核对软件是否迟到执行，未经核查不重复操作');verification=@{check='尚未找到并验证修复方式';evidence=@((Join-Path $job 'failure.json'));claimed_result='FAIL: '+$errorText};recovery='保留请求状态、日志和模型，人工核查；解决后另记恢复证据';applicability=$plan.applicability;source='本次真实失败；原因和解决办法仍待查证'}
   $failureRecipeFile=Join-Path $job 'pitfall-draft.json';Write-YaAtomic $failureRecipeFile $failureRecipe
   $null=Runtime @('exp_done',('slot='+$Slot),('tag='+$RequestId),'c=坑',('record='+$failureRecipeFile))
   $null=Runtime @('step_hand','note=执行失败，保留现场和待排查坑草稿')
  }catch{}
  try{Write-YaAtomic $operation @{status='blocked';request=$RequestId;error=$errorText;state_file=$stateFile;time=[DateTime]::UtcNow.ToString('o')}}catch{}
 }
 @{status='FAIL';error=$errorText;operation=$operation;next='保留状态与软件结果；不自动清 blocked，不自动重发'}|ConvertTo-Json;exit 1
}finally{if($runtimeHeld){$runtimeGuard.ReleaseMutex()};if($held){$guard.ReleaseMutex()};$runtimeGuard.Dispose();$guard.Dispose();$env:YALINK_OPERATION=$oldNonce}
