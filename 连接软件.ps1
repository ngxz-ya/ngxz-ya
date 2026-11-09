param([Parameter(Mandatory=$true)][string]$Software,[ValidateSet('Check','Run','Diagnose','Connect')][string]$Action='Check',[string]$TaskFile,[string]$RequestId=([guid]::NewGuid().ToString('N')),[ValidateRange(1,1800)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$pkg=$PSScriptRoot
try{
 if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'ENVIRONMENT: Windows PowerShell 5.1 required'}
 if([string]::IsNullOrWhiteSpace($Software) -or $Software.Length -gt 100 -or $Software -match '[\r\n]'){throw 'INPUT: 请给出具体软件名称'}
 $Software=$Software.Trim()
 . (Join-Path $pkg 'YA插件\连接上下文.ps1')
 . (Join-Path $pkg 'YA插件\真实记录.ps1')
 Assert-YaIsolatedPackage $pkg
 $operation=Join-Path (Get-YaPackageHudHome $pkg) 'operation.json'
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
 if($Action -eq 'Run' -or ($Action -eq 'Connect' -and $TaskFile)){
  if(-not $TaskFile){throw 'INPUT: Run 需要 Agent 编写的 TaskFile，先读 适配器/说明.md'}
  $invokeArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $pkg '任务执行.ps1'),'-Software',$Software,'-Slot',$slot,'-TaskFile',$TaskFile,'-RequestId',$RequestId,'-TimeoutSeconds',[string]$TimeoutSeconds)
  if($Action -eq 'Connect'){$invokeArgs+='-RequireInteractive'}
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
  @{status='CONNECTED_INTERACTIVE';software=$Software;request=$RequestId;live_link=$true;frontend_pid=$link['pid'];process_start=$link['process_start'];hud_visible=$true}|ConvertTo-Json
  exit 0
 }
 $candidates=@()
 foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')){
  foreach($app in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -and $_.DisplayName -match ('(?<![A-Za-z0-9])'+[regex]::Escape($Software)+'(?![A-Za-z0-9])')})){
   $candidates+=@{name=$app.DisplayName;version=$app.DisplayVersion;installation=$app.InstallLocation;source='Windows installed-app registration; candidate, not verified interface'}
  }
 }
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') find ('slot='+$slot) q=连接
 if($LASTEXITCODE){throw 'EXPERIENCE_SEARCH_FAILED'}
 $method=Join-Path $pkg ('连接教练\连接经验\'+$slot+'\方法.json')
 $hasMethod=Test-Path -LiteralPath $method
 @{status=$(if($hasMethod){'METHOD_AVAILABLE_RECHECK_REQUIRED'}else{'METHOD_RESEARCH_REQUIRED'});software=$Software;slot=$slot;installation_candidates=$candidates;method=$method;connected=$false;live_link=$false;connection_acceptance='Connect -TaskFile <本次任务JSON>';next=@('先读本机连接卡和已有经验，核对软件版本与条件','前台未连接或 YA 未显示时先运行 -Action Diagnose','缺方法时由Agent查合法官方接口或开源方案；记录来源、许可与安全审查','先读连接教练/通用接入指南.md，再用适配器/准备接入.ps1生成规范文件；草稿不代表已连接','前台连接验收用 -Action Connect -TaskFile；只做后台任务才用 Run；失败保留证据','图形软件支持时打开其可见窗口与本次成果；窗口展示和实时连接单独核验');token='未统计（除非另接真实用量源）';savings='待对照'}|ConvertTo-Json -Depth 8
}catch{@{status='FAIL';error=$_.Exception.Message}|ConvertTo-Json;exit 1}
