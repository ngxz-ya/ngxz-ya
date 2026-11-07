param([Parameter(Mandatory=$true)][string]$Software,[ValidateSet('Check','Install','Test','Diagnose')][string]$Action='Check',[double]$Length=20,[string]$RequestId=([guid]::NewGuid().ToString('N')),[ValidateRange(1,600)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch { }
$pkg=$PSScriptRoot
$guard=$null;$held=$false;$operationPath='';$statePath='';$ownsOperation=$false
$oldOperation=$env:YALINK_OPERATION
try {
  if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') { throw 'ENVIRONMENT: use Windows PowerShell 5.1 (powershell.exe), .NET Framework and an interactive Windows desktop for the panel.' }
  if($RequestId -cnotmatch '^[a-f0-9]{32}$') { throw 'INPUT: RequestId must be 32 lower-case hexadecimal characters.' }
  if([double]::IsNaN($Length) -or [double]::IsInfinity($Length) -or $Length -lt 1 -or $Length -gt 1000) { throw 'INPUT: Length must be 1..1000 mm.' }
  $catalog=Get-Content -LiteralPath (Join-Path $pkg '适配器\索引.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($catalog.schema -ne 1) { throw 'ADAPTER_SCHEMA_UNSUPPORTED' }
  $matches=@($catalog.adapters | Where-Object {$_.aliases -contains $Software.Trim()})
  if($matches.Count -ne 1) {
    [ordered]@{status='UNSUPPORTED';software=$Software;live_link=$false;next='No registered adapter. Agent may investigate public official APIs or licensed open-source methods; do not report connection success.'} | ConvertTo-Json
    exit 2
  }
  $adapter=$matches[0]
  $driver=[IO.Path]::GetFullPath((Join-Path (Join-Path $pkg '适配器') $adapter.driver))
  if(-not $driver.StartsWith(([IO.Path]::GetFullPath((Join-Path $pkg '适配器'))+'\'),[StringComparison]::OrdinalIgnoreCase)) {throw 'INVALID_ADAPTER_PATH'}
  . $driver
  $environment=Get-YaAdapterEnvironment $adapter
  $revision=(@($adapter.sources | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $pkg $_)).Hash }) -join ':')
  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  . (Join-Path $pkg 'YA插件\真实记录.ps1')
  $hudHome=Get-YaPackageHudHome $pkg
  $operationPath=Join-Path $hudHome 'operation.json'
  if($Action -eq 'Diagnose') {
    $operation=if(Test-Path -LiteralPath $operationPath){Get-Content $operationPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
    [ordered]@{status='DIAGNOSTIC';environment=$environment;operation=$operation;live_link=$false;next='For blocked/pending runs inspect raw logs, model hashes and process IDs. Do not clear state or retry automatically.'}|ConvertTo-Json -Depth 12
    exit 0
  }
  if($Action -eq 'Check' -or $environment.status -ne 'READY') {
    [ordered]@{status=$environment.status;adapter=$adapter.id;mode=$adapter.mode;live_link=$false;os=[Environment]::OSVersion.VersionString;powershell=$PSVersionTable.PSVersion.ToString();environment=$environment;capabilities=$adapter.capabilities;token='未统计（未挂本次真实用量源）';savings='待对照';license='Runtime feature authorization is checked only by actual official API execution.'}|ConvertTo-Json -Depth 10
    if($environment.status -eq 'READY'){exit 0}else{exit 2}
  }
  $guard=New-Object Threading.Mutex($false,('Local\YASoftwareOperation-'+[YaEvidence]::Identity($pkg)))
  try {$held=$guard.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
  if(-not $held){throw 'BUSY: another software operation owns this package.'}
  $runtimeGuard=New-Object Threading.Mutex($false,('Local\YARuntime-'+[YaEvidence]::Identity($pkg)))
  $runtimeHeld=$false
  try {
    try{$runtimeHeld=$runtimeGuard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$runtimeHeld=$true}
    if(-not $runtimeHeld){throw 'BUSY: runtime state is being updated.'}
    Assert-YaOperation $pkg
    $identity=[YaEvidence]::Identity($pkg)
    $work=[YaEvidence]::Work($pkg,[string]$adapter.slot)
    $statePath=Join-Path (Join-Path $work $RequestId) 'request.json'
    if(Test-Path -LiteralPath $statePath) {
      $previous=Get-Content $statePath -Raw -Encoding UTF8|ConvertFrom-Json
      if($previous.length -ne $Length -or $previous.adapter -ne $adapter.id -or $previous.revision -cne $revision -or $previous.software_version -cne $environment.installation.version){throw 'REQUEST_CONFLICT: same ID with different input.'}
      if($previous.status -eq 'completed' -and (Test-Path -LiteralPath $previous.result)) {
        $result=Get-Content $previous.result -Raw -Encoding UTF8|ConvertFrom-Json
        if((Get-FileHash -LiteralPath $result.context.model).Hash -ne $result.context.model_sha256){throw 'EVIDENCE_CHANGED: do not reuse cached success.'}
        [ordered]@{status='VERIFIED_BATCH';cached=$true;request=$RequestId;result=$previous.result;live_link=$false}|ConvertTo-Json
        exit 0
      }
      throw 'RECOVERY_REQUIRED: request already dispatched or incomplete; no automatic rerun.'
    }
    $nonce=[guid]::NewGuid().ToString('N');$env:YALINK_OPERATION=$nonce
    Write-YaAtomic $operationPath @{status='pending';request=$RequestId;nonce=$nonce;owner_pid=$PID;owner_start=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString();adapter=$adapter.id;length=$Length;time=[DateTime]::UtcNow.ToString('o')}
    $ownsOperation=$true
  } finally {if($runtimeHeld){$runtimeGuard.ReleaseMutex()};$runtimeGuard.Dispose()}
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '安装卸载\安装.ps1') -PackageOnly
  if($LASTEXITCODE -ne 0){throw 'INSTALL_FAILED: inspect installation log.'}
  if($Action -eq 'Install') {
    Write-YaAtomic $operationPath @{status='completed';request=$RequestId;time=[DateTime]::UtcNow.ToString('o')}
    [ordered]@{status='INSTALLED';adapter=$adapter.id;live_link=$false}|ConvertTo-Json
    exit 0
  }
  Write-YaAtomic $statePath @{status='dispatched';adapter=$adapter.id;revision=$revision;software_version=$environment.installation.version;length=$Length;request=$RequestId;time=[DateTime]::UtcNow.ToString('o')}
  $transcript=Join-Path (Split-Path $statePath -Parent) 'task.log'
  $execution=Invoke-YaAdapterTask $pkg $environment $work $Length $TimeoutSeconds
  $resultLines=@($execution.lines)
  $code=$execution.exit_code
  [IO.File]::WriteAllLines($transcript,[string[]]$resultLines,[Text.UTF8Encoding]::new($true))
  if($code -ne 0){throw ('EXECUTION_OR_STORAGE_FAILED: '+$transcript)}
  $resultFile=([regex]::Match(($resultLines -join "`n"),'(?m)^result:\s*(.+)$')).Groups[1].Value.Trim()
  if(-not $resultFile -or -not (Test-Path -LiteralPath $resultFile)){throw 'RESULT_MISSING'}
  Write-YaAtomic $statePath @{status='completed';adapter=$adapter.id;revision=$revision;software_version=$environment.installation.version;length=$Length;request=$RequestId;result=$resultFile;time=[DateTime]::UtcNow.ToString('o')}
  Write-YaAtomic $operationPath @{status='completed';request=$RequestId;result=$resultFile;time=[DateTime]::UtcNow.ToString('o')}
  [ordered]@{status='VERIFIED_BATCH';adapter=$adapter.id;request=$RequestId;result=$resultFile;live_link=$false;mode=$adapter.mode;token='未统计（除非另挂本次真实用量）';savings='待对照'}|ConvertTo-Json -Depth 8
} catch {
  $reason=$_.Exception.Message
  if($ownsOperation){try{Write-YaAtomic $operationPath @{status='blocked';request=$RequestId;error=$reason;state_file=$statePath;time=[DateTime]::UtcNow.ToString('o')}}catch{}}
  [ordered]@{status='FAIL';error=$reason;operation=$operationPath;live_link=$false;next='Use -Action Diagnose. Do not erase evidence or automatically repeat an uncertain operation.'}|ConvertTo-Json -Depth 6
  exit 1
} finally {
  $env:YALINK_OPERATION=$oldOperation
  if($held){$guard.ReleaseMutex()};if($guard){$guard.Dispose()}
}
