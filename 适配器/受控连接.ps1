# A separate worker preserves adapter closures; only this owned PowerShell worker is stopped on timeout.
$script:YaQuickContext=$null
function Initialize-YaQuickWorker([string]$Path){
  $root=Join-Path (Get-YaPackageHudHome $pkg) 'quick'
  $Path=[IO.Path]::GetFullPath($Path)
  if(-not $Path.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $Path -Leaf) -cne 'worker.json'){throw 'INVALID_QUICK_WORKER'}
  $c=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
  $owner=Get-Process -Id $c.owner_pid -ErrorAction Stop
  if($c.request -cnotmatch '^[a-f0-9]{32}$' -or (Split-Path (Split-Path $Path -Parent) -Leaf) -cne $c.request -or $c.package_id -cne [YaEvidence]::Identity($pkg) -or $owner.StartTime.ToUniversalTime().Ticks.ToString() -cne $c.owner_start -or (Get-FileHash -LiteralPath $c.script).Hash -cne $c.script_hash){throw 'INVALID_QUICK_WORKER_IDENTITY'}
  $script:YaQuickContext=$c
  $env:YALINK_QUICK_WORKER=$c.request
}
function Set-YaQuickStage([string]$Stage,[string]$Work='',[int]$SoftwarePid=0){
  if(-not $script:YaQuickContext){return}
  $c=$script:YaQuickContext;$owner=Get-Process -Id $c.owner_pid -ErrorAction SilentlyContinue
  if(-not $owner -or $owner.StartTime.ToUniversalTime().Ticks.ToString() -cne $c.owner_start){throw 'QUICK_OWNER_GONE: preserve software; do not continue'}
  Write-YaAtomic $c.progress @{request=$c.request;stage=$Stage;started_utc=[DateTime]::UtcNow.ToString('o');work=$Work;software_pid=$SoftwarePid}
}
function Invoke-YaQuickWorker {
  param([string]$Script,[string[]]$Arguments,[ValidateRange(1,1800)][int]$WaitSeconds)
  $guard=[Threading.Mutex]::new($false,('Local\YAQuick-'+[YaEvidence]::Identity($pkg)))
  $held=$false;$child=$null;$record=$null;$stateFile=$null
  try{
    $held=$guard.WaitOne(0);if(-not $held){throw 'BUSY: another quick connection is active'}
    Assert-YaOperation $pkg
    $request=[guid]::NewGuid().ToString('N');$homePath=Get-YaPackageHudHome $pkg
    $directory=Join-Path $homePath ('quick\'+$request);[IO.Directory]::CreateDirectory($directory)|Out-Null
    $stateFile=Join-Path $directory 'status.json';$contextFile=Join-Path $directory 'worker.json'
    $stdout=Join-Path $directory 'stdout.log';$stderr=Join-Path $directory 'stderr.log'
    $record=@{request=$request;status='pending';dispatched=$false;owner_pid=$PID;owner_start=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString();stage='starting';started_utc=[DateTime]::UtcNow.ToString('o')}
    $context=@{request=$request;package_id=[YaEvidence]::Identity($pkg);owner_pid=$record.owner_pid;owner_start=$record.owner_start;script=$Script;script_hash=(Get-FileHash -LiteralPath $Script).Hash;progress=(Join-Path $directory 'progress.json')}
    Write-YaAtomic $contextFile $context;Write-YaAtomic $stateFile $record
    Write-YaAtomic (Join-Path $homePath 'quick_request.json') @{request=$request;state_file=$stateFile}
    $args2=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Script)+$Arguments+('_worker='+$contextFile)
    $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (@($args2|ForEach-Object{[YaWindow]::Quote([string]$_)}) -join ' ') -WorkingDirectory $pkg -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    [void]$child.Handle;$record.worker_pid=$child.Id;$record.worker_start=$child.StartTime.ToUniversalTime().Ticks.ToString();Write-YaAtomic $stateFile $record
    $total=[Diagnostics.Stopwatch]::StartNew();$expired=$false;$lastStage=''
    while(-not $child.HasExited){
      $progress=$null
      if(Test-Path -LiteralPath $context.progress){$progress=Get-Content -LiteralPath $context.progress -Raw -Encoding UTF8|ConvertFrom-Json;if($progress.request -cne $request){throw 'QUICK_PROGRESS_IDENTITY_CHANGED'}}
      if($progress){
        if($progress.stage -in @('launch','startup','window','probe','proof','registration')){$record.dispatched=$true}
        if($progress.stage -cne $lastStage){$lastStage=$progress.stage;$record.stage=$lastStage;$record.progress=$progress;Write-YaAtomic $stateFile $record;[Console]::WriteLine(('stage: '+$lastStage+'; evidence='+$directory))}
        if($progress.stage -in @('adapter','probe') -and ([DateTime]::UtcNow-[DateTime]::Parse($progress.started_utc).ToUniversalTime()).TotalSeconds -gt $WaitSeconds){$expired=$true;break}
      }
      if($total.Elapsed.TotalSeconds -gt (5*$WaitSeconds+90)){$expired=$true;break}
      Start-Sleep -Milliseconds 200
    }
    if(Test-Path -LiteralPath $context.progress){
      $finalProgress=Get-Content -LiteralPath $context.progress -Raw -Encoding UTF8|ConvertFrom-Json
      if($finalProgress.request -cne $request){throw 'QUICK_PROGRESS_IDENTITY_CHANGED'}
      $record.progress=$finalProgress;$record.stage=$finalProgress.stage
      if($finalProgress.stage -in @('launch','startup','window','probe','proof','registration')){$record.dispatched=$true}
    }
    if($expired){
      $record.status=if($record.dispatched){'blocked'}else{'failed'};$record.error='QUICK_TIMEOUT_UNKNOWN: preserve software and evidence; do not retry'
      Write-YaAtomic $stateFile $record
      if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(3000)}
      $exitCode=1
    }else{
      $child.WaitForExit();$exitCode=$child.ExitCode
      $record.exit_code=$exitCode;$record.status=if($exitCode -eq 0){'completed'}elseif($record.dispatched){'blocked'}else{'failed'}
      if($exitCode -eq 0){$record.receipts=@(@{path=$stdout;sha256=(Get-FileHash -LiteralPath $stdout).Hash},@{path=$stderr;sha256=(Get-FileHash -LiteralPath $stderr).Hash})}
      Write-YaAtomic $stateFile $record
    }
    foreach($path in @($stdout,$stderr)){if(Test-Path -LiteralPath $path){[Console]::Write([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))}}
    if($expired){[Console]::WriteLine($record.error)}
    [Console]::WriteLine(('connection_state: '+$record.status+'; evidence='+$directory))
    return [int]$exitCode
  }catch{
    if($record -and $stateFile){$record.status=if($record.dispatched){'blocked'}else{'failed'};$record.error=$_.Exception.Message;try{Write-YaAtomic $stateFile $record}catch{}}
    throw
  }finally{
    if($child){if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(3000)};$child.Dispose()}
    if($held){$guard.ReleaseMutex()};$guard.Dispose()
  }
}
