param([Parameter(Mandatory=$true)][string]$Software,[ValidateSet('Check','Run','Diagnose','Connect','Reconcile')][string]$Action='Check',[string]$TaskFile,[string]$RequestId=([guid]::NewGuid().ToString('N')),[ValidateRange(1,1800)][int]$TimeoutSeconds=120,[switch]$AllowBatch,[switch]$ShowPanel)
$ErrorActionPreference='Stop'
$pkg=$PSScriptRoot
try{
 if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'ENVIRONMENT: Windows PowerShell 5.1 required'}
 if([string]::IsNullOrWhiteSpace($Software) -or $Software.Length -gt 100 -or $Software -match '[\r\n]'){throw 'INPUT: 请给出具体软件名称'}
 $Software=$Software.Trim()
 if($AllowBatch -and $Action -ne 'Run'){throw 'INPUT: -AllowBatch 只适用于明确要求后台执行的 Run'}
 if($Action -eq 'Connect' -and -not $TaskFile){
  @{status='CONNECT_TASK_REQUIRED';connected=$false;live_link=$false;next='先用 -Action Check 检查环境，前台通道登记后用 Connect -TaskFile 本次任务.json 验收'}|ConvertTo-Json
  exit 1
 }
 . (Join-Path $pkg 'YA插件\连接上下文.ps1')
 . (Join-Path $pkg 'YA插件\真实记录.ps1')
 Assert-YaIsolatedPackage $pkg
 $operation=Join-Path (Get-YaPackageHudHome $pkg) 'operation.json'
 if($Action -eq 'Reconcile'){
  $guard=[Threading.Mutex]::new($false,('Local\YASoftwareOperation-'+[YaEvidence]::Identity($pkg)))
  $held=$false
  try{
   try{$held=$guard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
   if(-not $held){throw 'BUSY: original task is still running'}
   $homeDir=Get-YaPackageHudHome $pkg
   $ref=Get-Content -LiteralPath (Join-Path $homeDir 'operation_request.json') -Raw -Encoding UTF8|ConvertFrom-Json
   $state=Get-Content -LiteralPath $ref.state_file -Raw -Encoding UTF8|ConvertFrom-Json
   $job=Split-Path $ref.state_file -Parent
   if($ref.request -cnotmatch '^[a-f0-9]{32}$' -or $state.request -cne $ref.request -or (Split-Path $job -Leaf) -cne $ref.request){throw 'RECOVERY_REQUEST_MISMATCH'}
   $context=Get-Content -LiteralPath (Join-Path $job 'task.json') -Raw -Encoding UTF8|ConvertFrom-Json
   if($context.software -ine $Software -or $context.request -cne $ref.request -or $context.slot -cnotmatch '^[a-z][a-z0-9_-]{0,31}$' -or
     $job -ine (Join-Path ([YaEvidence]::Work($pkg,$context.slot)) $ref.request)){throw 'RECOVERY_TARGET_MISMATCH'}
   $status='EXECUTION_UNKNOWN'
   $receipts=@{}
   foreach($name in @('Execute','Verify')){
    $file=Join-Path $job ($name+'.json')
    if(Test-Path -LiteralPath $file){
     $receipt=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json
     if($receipt.request -ceq $ref.request -and $receipt.nonce -ceq $context.nonce -and $receipt.software_version -ceq $context.software_version){$receipts[$name]=$receipt}
    }
   }
   if($state.status -ceq 'completed'){
    Assert-YaCompletedRequest $ref.state_file
    $status=if($state.mode -ceq 'simulation'){'SIMULATED_COMPLETED'}else{'VERIFIED_COMPLETED'}
   }
   elseif($state.status -ceq 'prepared' -and $state.dispatch_schema -eq 1){$status='NOT_DISPATCHED'}
   elseif($receipts.Execute.status -ceq 'EXECUTED'){
    $status='EXECUTED_AWAITING_VERIFICATION'
    $verifiedFile=Join-Path $job 'verification.json'
    if($receipts.Verify.status -ceq 'READBACK' -and [IO.File]::Exists($verifiedFile)){
     $evidence=Get-Content -LiteralPath $verifiedFile -Raw -Encoding UTF8|ConvertFrom-Json
     if($evidence.request -ceq $ref.request -and $evidence.nonce -ceq $context.nonce -and
        $evidence.mode -ne 'simulation' -and $evidence.verify_sha256 -ceq [YaEvidence]::Hash((Join-Path $job 'Verify.json')) -and
        @($evidence.artifacts).Count -gt 0 -and -not @($evidence.artifacts|Where-Object {
         -not $_.path -or -not [IO.Path]::GetFullPath($_.path).StartsWith($job+'\',[StringComparison]::OrdinalIgnoreCase) -or
         -not [IO.File]::Exists($_.path) -or [YaEvidence]::Hash($_.path) -cne $_.sha256
        }).Count){$status='VERIFIED_AWAITING_RECORD'}
    }
   }
   $session=$null;$channel=$null
   $binding=Join-Path $job 'frontend-session.json'
   if(Test-Path -LiteralPath $binding){
    $session=Get-Content -LiteralPath $binding -Raw -Encoding UTF8|ConvertFrom-Json
    try{
     $io=Join-Path $homeDir 'io'
     $active=[YaEvidence]::Read((Join-Path $io 'link.json'))
     $channel=($session.session -ceq $active['session'] -and [string]$session.pid -ceq [string]$active['pid'] -and
       $session.process_start -ceq $active['process_start'] -and -not [YaEvidence]::CheckCommandChannel($pkg,$io,$active))
    }catch{$channel=$false}
   }
   @{status=$status;request=$ref.request;evidence=$job;receipts=$receipts;session=$session;channel_available=$channel;
     next='保留原请求。执行未知或尚未核验时，先在原软件实例只读检查文档和产物，不重放命令。'}|ConvertTo-Json -Depth 12
   exit 0
  }finally{if($held){$guard.ReleaseMutex()};$guard.Dispose()}
 }
 if($Action -eq 'Diagnose'){
  $state=if(Test-Path -LiteralPath $operation){Get-Content -LiteralPath $operation -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
  $quick=$null;$ref=Join-Path (Get-YaPackageHudHome $pkg) 'quick_request.json'
  if(Test-Path -LiteralPath $ref){$q=Get-Content -LiteralPath $ref -Raw -Encoding UTF8|ConvertFrom-Json;$quick=Get-Content -LiteralPath $q.state_file -Raw -Encoding UTF8|ConvertFrom-Json}
  $io=Join-Path (Get-YaPackageHudHome $pkg) 'io'
  $frontend=@{stage='LINK_MISSING';next='确认目标窗口内有可用桥接后，用 ya_link.ps1 的 prepare=1 发起挑战，取得真实软件回执后再登记'}
  if($state.status -in @('pending','blocked') -or $quick.status -in @('pending','blocked')){
   $frontend=@{stage='RECOVERY_REQUIRED';next='保留现有请求和日志，核对软件状态后再决定是否继续'}
  }elseif(Test-Path -LiteralPath (Join-Path $io 'link.json')){
   try{
    $link=[YaEvidence]::Read((Join-Path $io 'link.json'))
    $frontend.software=$link['soft'];$frontend.slot=$link['slot'];$frontend.pid=$link['pid']
    if($link['state'] -eq 'opened'){
     $frontend.stage='READBACK_PENDING'
     $frontend.reason=$link['evidence_error']
     $frontend.next='核对本次挑战及目标进程的回执，再用原软件名、槽和 PID 运行 ya_link.ps1 登记'
    }elseif($link['state'] -eq 'ok'){
     $reason=[YaEvidence]::CheckCommandChannel($pkg,$io,$link)
     if($reason){
      $frontend.stage='CHANNEL_UNCONFIRMED';$frontend.reason=$reason
      $frontend.next='核对已登记进程、活动文档及进程内桥接，再重新挑战'
     }else{
      $frontend.stage='CHANNEL_VERIFIED'
      $frontend.accepted=[YaEvidence]::HasFrontendAcceptance($pkg,$io,$link)
      $frontend.next='运行带 TaskFile 的 Connect 验收同窗口修改、独立读回和 YA 显示'
      if($frontend.accepted){$frontend.next='复用当前前台会话。每条新操作建立任务并核对软件回读'}
     }
    }
   }catch{
    $frontend.stage='LINK_INVALID';$frontend.reason=$_.Exception.Message
    $frontend.next='核对本工作区的连接登记及原始回执'
   }
  }
  $hudVisible=$false
  try{
   $hud=[YaEvidence]::Read((Join-Path $io 'hud_window.json'))
   $hudProcess=Get-Process -Id ([int]$hud['pid']) -ErrorAction Stop
   $hudVisible=($hud['package_id'] -ceq [YaEvidence]::Identity($pkg) -and
     $hudProcess.StartTime.ToUniversalTime().Ticks.ToString() -ceq $hud['process_start'] -and
     [YaWindow]::InputVisible($hudProcess.Id,[long]$hud['handle']))
  }catch{}
  @{status='DIAGNOSTIC';software=$Software;operation=$state;quick_connection=$quick;file=$operation;frontend=$frontend;hud_visible=$hudVisible;hud_entry='YA插件/show_ya.ps1';next='保留日志和成果，检查是否迟到执行；不要清状态重发'}|ConvertTo-Json -Depth 15;exit 0
 }
 Assert-YaOperation $pkg
 $output=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') ensure ('soft='+$Software))
 if($LASTEXITCODE){throw ($output -join "`n")}
 $slot=([regex]::Match(($output -join "`n"),'(?m)^slot:\s*(\S+)')).Groups[1].Value
 if(-not $slot){throw 'SLOT_CREATION_FAILED'}
 if($Action -in @('Run','Connect')){
  if(-not $TaskFile){throw 'INPUT: Run 需要 Agent 编写的 TaskFile，先读 适配器/说明.md'}
  $invokeArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $pkg '任务执行.ps1'),'-Software',$Software,'-Slot',$slot,'-TaskFile',$TaskFile,'-RequestId',$RequestId,'-TimeoutSeconds',[string]$TimeoutSeconds)
  if($Action -eq 'Connect'){$invokeArgs+='-RequireInteractive'}
  if($AllowBatch){$invokeArgs+='-AllowBatch'}
  & powershell @invokeArgs
  $taskExit=$LASTEXITCODE
  if($taskExit -or $Action -eq 'Run'){exit $taskExit}
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'YA插件\show_ya.ps1') -WithSoftware
  if($LASTEXITCODE){exit $LASTEXITCODE}
  $io=Join-Path (Get-YaPackageHudHome $pkg) 'io';$link=[YaEvidence]::Read((Join-Path $io 'link.json'))
  if($link['slot'] -cne $slot -or [YaEvidence]::CheckCommandChannel($pkg,$io,$link)){throw 'FRONTEND_SESSION_LOST: task passed but current connection is not confirmed'}
  $job=Join-Path ([YaEvidence]::Work($pkg,$slot)) $RequestId
  $stateFile=Join-Path $job 'request.json'
  Assert-YaCompletedRequest $stateFile
  $completed=[YaEvidence]::Read($stateFile)
  $binding=[YaEvidence]::Read((Join-Path $job 'frontend-session.json'))
  if($completed['mode'] -cne 'interactive' -or $completed['request'] -cne $RequestId){throw 'FRONTEND_TASK_REQUIRED'}
  foreach($key in @('session','pid','process_start')){
   if([string]$binding[$key] -cne [string]$link[$key]){throw 'FRONTEND_SESSION_CHANGED: the completed task belongs to a different registration'}
  }
  Write-YaAtomic (Join-Path $io 'frontend-acceptance.json') @{
   package_id=$link['package_id'];slot=$slot;session=$link['session'];pid=$link['pid'];process_start=$link['process_start']
   readback_sha256=$link['readback_sha256'];request=$RequestId;state_sha256=[YaEvidence]::Hash($stateFile)
   verify_sha256=[YaEvidence]::Hash((Join-Path $job 'Verify.json'))
  }
  @{status='CONNECTED_INTERACTIVE';software=$Software;request=$RequestId;live_link=$true;frontend_pid=$link['pid'];process_start=$link['process_start'];channel_available=$true;software_visible=$true;task_verified=$true;hud_visible=$true}|ConvertTo-Json
  exit 0
 }
 # A checked, accepted live session can be handed to the next Agent without rediscovery.
 $io=Join-Path (Get-YaPackageHudHome $pkg) 'io'
 $linkFile=Join-Path $io 'link.json'
 $accepted=$false;$channelAvailable=$null
 if(Test-Path -LiteralPath $linkFile){
  try{
   $link=[YaEvidence]::Read($linkFile)
   $channelAvailable=($link['slot'] -ceq $slot -and $link['soft'] -ieq $Software -and
     -not [YaEvidence]::CheckCommandChannel($pkg,$io,$link))
   $accepted=($channelAvailable -and [YaEvidence]::HasFrontendAcceptance($pkg,$io,$link))
  }catch{}
 }
 $hudVisible=$null
 $softwareVisible=$null
 if($channelAvailable -and [YaWindow]::Desktop() -ceq 'WinSta0\Default'){
  try{
   $process=Get-Process -Id ([int]$link['pid']) -ErrorAction Stop
   $softwareVisible=($process.StartTime.ToUniversalTime().Ticks.ToString() -ceq $link['process_start'] -and
     [YaWindow]::InputVisible($process.Id,[YaWindow]::Find($process.Id).ToInt64()))
  }catch{$softwareVisible=$false}
 }
 if($ShowPanel){
  $panelArgs=@()
  if($accepted){$panelArgs+='-WithSoftware'}
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'YA插件\show_ya.ps1') @panelArgs
  $hudVisible=($LASTEXITCODE -eq 0)
  if($accepted -and $hudVisible){$softwareVisible=$true}
 }
 if($accepted){
  $connected=($hudVisible -eq $true -and $softwareVisible -eq $true)
  @{status=$(if($connected){'CONNECTED_INTERACTIVE'}elseif($null -eq $hudVisible){'CHANNEL_VERIFIED_VISIBILITY_UNCHECKED'}else{'HUD_NOT_VISIBLE'});software=$Software;slot=$slot;workspace=$pkg
    connected=$connected;live_link=$true;channel_available=$true;task_verified=$true;frontend_pid=$link['pid'];software_visible=$softwareVisible;hud_visible=$hudVisible;reused_session=$true
    next=$(if(-not $connected){'保留当前模型，只复验软件和 YA 显示'}else{'用 Run -TaskFile 在当前窗口执行下一任务'})}|ConvertTo-Json
  if($hudVisible -eq $false){exit 1};exit 0
 }
 $catalog=Get-Content -LiteralPath (Join-Path $pkg '适配器\索引.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $candidates=@()
 $versionCandidates=@()
 $nameParts=@($Software -split '[\s._-]+|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])' | Where-Object {$_})
 $namePattern='(?<![A-Za-z0-9])'+(($nameParts|ForEach-Object{[regex]::Escape($_)}) -join '[\s._-]*')+'(?![A-Za-z0-9])'
 $versionHint=[regex]::Match($Software,'(?<![0-9])[0-9]{4}$').Value
 foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')){
  foreach($app in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName})){
   $nameMatched=$nameParts.Count -gt 0 -and $app.DisplayName -match $namePattern
   $versionMatched=$versionHint -and $app.InstallLocation -and
    ($app.DisplayName -match ('(?<![0-9])'+$versionHint+'(?![0-9])') -or
     $app.DisplayVersion -match ('^'+$versionHint.Substring(0,2)+'[.]?'+$versionHint.Substring(2,2)+'(?:[.]|$)'))
   if(-not $nameMatched -and -not $versionMatched){continue}
   $candidate=@{name=$app.DisplayName;version=$app.DisplayVersion;installation=$app.InstallLocation;source='Windows installed-app registration'}
   if($nameMatched){$candidates+=$candidate}else{$versionCandidates+=$candidate}
  }
 }
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') find ('slot='+$slot) q=连接
 if($LASTEXITCODE){throw 'EXPERIENCE_SEARCH_FAILED'}
 $method=Join-Path $pkg ('连接教练\连接经验\'+$slot+'\方法.json')
 $hasMethod=Test-Path -LiteralPath $method
 $bundledMethods=@($catalog.adapters | Where-Object {$_.software -ieq $Software})
 $frontend=@{stage='FRONTEND_ADAPTER_MISSING';next='先定位当前窗口并核对实际版本，优先查看本包工作区内已验证的接入经验；没有适用记录时再按通用接入指南做只读探针'}
 if(-not $hasMethod -and $bundledMethods.Count){
  $frontend=@{stage='BUNDLED_METHOD_RECHECK_REQUIRED';next='先读随包工法并核对本机版本与启动条件；适用才采用。独立示例不能自动替换用户指定的实例。'}
 }
 if($hasMethod){
  try{
   $localMethod=Get-Content -LiteralPath $method -Raw -Encoding UTF8|ConvertFrom-Json
   if($localMethod.mode -eq 'interactive' -and $localMethod.status -eq 'reviewed' -and $localMethod.frontend){
    $frontend=@{stage='FRONTEND_METHOD_RECHECK_REQUIRED';next='核对实际版本，加载桥接并做只读探针，再登记 YA'}
   }elseif($localMethod.mode -eq 'batch'){
    $frontend.next='已有方法仅支持批处理。保留它，先确认目标窗口与前台接口；连接请求不要改走后台'
   }
  }catch{$frontend.next='现有方法文件无法读取，保留文件并检查格式'}
 }
 @{
  status=$(if($hasMethod -or $bundledMethods.Count){'METHOD_AVAILABLE_RECHECK_REQUIRED'}else{'METHOD_RESEARCH_REQUIRED'})
  software=$Software;slot=$slot;workspace=$pkg;hud_visible=$hudVisible;installation_candidates=$candidates;version_only_candidates=$versionCandidates
  installation_next='名称匹配和版本匹配都是候选。先核对候选安装目录中实际可执行文件的产品名与版本，只有版本相同时不得据此启动或登记'
  method=$method;bundled_methods=$bundledMethods;frontend=$frontend;connected=$false;live_link=($channelAvailable -eq $true);channel_available=$channelAvailable;software_visible=$softwareVisible;task_verified=$false
  connection_acceptance='Connect -TaskFile <本次任务JSON>'
  guide='连接教练/通用接入指南.md';next=$frontend.next
  token='未统计（除非另接真实用量源）';savings='待对照'
 }|ConvertTo-Json -Depth 8
 if($hudVisible -eq $false){exit 1}
}catch{@{status='FAIL';error=$_.Exception.Message}|ConvertTo-Json;exit 1}
