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
  @{status='DIAGNOSTIC';software=$Software;operation=$state;file=$operation;next='保留日志和成果，检查是否迟到执行；不要清状态重发'}|ConvertTo-Json -Depth 10;exit 0
 }
 Assert-YaOperation $pkg
 $output=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') ensure ('soft='+$Software))
 if($LASTEXITCODE){throw ($output -join "`n")}
 $slot=([regex]::Match(($output -join "`n"),'(?m)^slot:\s*(\S+)')).Groups[1].Value
 if(-not $slot){throw 'SLOT_CREATION_FAILED'}
 if($Action -eq 'Run'){
  if(-not $TaskFile){throw 'INPUT: Run 需要 Agent 编写的 TaskFile，先读 适配器/说明.md'}
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '任务执行.ps1') -Software $Software -Slot $slot -TaskFile $TaskFile -RequestId $RequestId -TimeoutSeconds $TimeoutSeconds
  exit $LASTEXITCODE
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
 @{status=$(if($hasMethod){'METHOD_AVAILABLE_RECHECK_REQUIRED'}else{'METHOD_RESEARCH_REQUIRED'});software=$Software;slot=$slot;installation_candidates=$candidates;method=$method;connected=$false;live_link=$false;next=@('先读本机连接卡和已有经验，核对软件版本与条件','缺方法时由Agent查合法官方接口或开源方案；记录来源、许可与安全审查','按适配器/说明.md创建本机方法与非破坏性任务；不得由Agent编造软件成功回执','用 -Action Run -TaskFile 执行并独立读取验证；失败保留证据并人工接管','图形软件支持时打开其可见窗口与本次成果；窗口展示和实时连接单独核验');token='未统计（除非另接真实用量源）';savings='待对照'}|ConvertTo-Json -Depth 8
}catch{@{status='FAIL';error=$_.Exception.Message}|ConvertTo-Json;exit 1}
