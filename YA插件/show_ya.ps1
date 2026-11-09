param([switch]$DesktopHost,[string]$RequestFile,[switch]$WithSoftware,[string]$HudHome)
$ErrorActionPreference='Stop'
$package=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '连接上下文.ps1')
. (Join-Path $PSScriptRoot '真实记录.ps1')
try{
  Assert-YaIsolatedPackage $package
  if($DesktopHost -and $HudHome){$env:YALINK_HUD_HOME=[IO.Path]::GetFullPath($HudHome)}
  $homePath=Get-YaPackageHudHome $package
  $io=Join-Path $homePath 'io'
  $exe=Join-Path $PSHOME 'powershell.exe'
  if(-not $DesktopHost){
    $request=[guid]::NewGuid().ToString('N')
    $directory=Join-Path $io ('hud-show\'+$request)
    $RequestFile=Join-Path $directory 'request.json'
    Write-YaAtomic $RequestFile @{request=$request;package_id=[YaEvidence]::Identity($package);issued_utc=[DateTime]::UtcNow.ToString('o');with_software=[bool]$WithSoftware}
    $startup=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0;WinstationDesktop='WinSta0\Default';CreateFlags=[uint32]0x09000000}
    $command=@($exe,'-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-DesktopHost','-RequestFile',$RequestFile,'-HudHome',$homePath)
    $launch=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=(@($command|ForEach-Object{[YaWindow]::Quote([string]$_)}) -join ' ');CurrentDirectory=$package;ProcessStartupInformation=$startup} -OperationTimeoutSec 15
    if($launch.ReturnValue -ne 0){throw ('HUD_LAUNCH_FAILED: WMI returned '+$launch.ReturnValue+'; no attached fallback was started')}
    $hostPid=[int]$launch.ProcessId
    $resultFile=Join-Path $directory 'result.json';$until=[DateTime]::UtcNow.AddSeconds(35)
    while(-not [IO.File]::Exists($resultFile) -and [DateTime]::UtcNow -lt $until){Start-Sleep -Milliseconds 200}
    if(-not [IO.File]::Exists($resultFile)){throw ('HUD_NOT_VISIBLE: desktop host did not confirm; pid='+$hostPid+'; evidence='+$directory)}
    $result=Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8|ConvertFrom-Json
    if($result.request -cne $request -or $result.host_pid -ne $hostPid -or $result.status -cne 'VISIBLE'){throw ('HUD_NOT_VISIBLE: '+$result.error+'; evidence='+$directory)}
    if($WithSoftware -and $result.software_visible -ne $true){throw 'SOFTWARE_NOT_USER_VISIBLE: display host did not confirm the registered software'}
    $result|ConvertTo-Json -Depth 6;exit 0
  }
  if([YaWindow]::Desktop() -cne 'WinSta0\Default'){throw 'HUD_INTERACTIVE_DESKTOP_REQUIRED'}
  $RequestFile=[IO.Path]::GetFullPath($RequestFile)
  if(-not $RequestFile.StartsWith(([IO.Path]::GetFullPath($io)+'\hud-show\'),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $RequestFile -Leaf) -cne 'request.json'){throw 'INVALID_SHOW_REQUEST_PATH'}
  $pending=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8|ConvertFrom-Json
  if($pending.package_id -cne [YaEvidence]::Identity($package) -or $pending.request -cnotmatch '^[a-f0-9]{32}$' -or (Split-Path (Split-Path $RequestFile -Parent) -Leaf) -cne $pending.request -or ([DateTime]::UtcNow-[DateTime]::Parse($pending.issued_utc).ToUniversalTime()).TotalSeconds -gt 60){throw 'INVALID_SHOW_REQUEST'}
  $name=Get-YaHudInstanceName $PSScriptRoot $homePath
  $guard=[Threading.Mutex]::new($false,($name+'-Launch'));$held=$false;$ready=$null
  try{
    $held=$guard.WaitOne(0);if(-not $held){throw 'HUD_BUSY: another display request is active'}
    $software=$null
    if($pending.with_software){
      $software=[YaEvidence]::Read((Join-Path $io 'link.json'))
      if([YaEvidence]::CheckCommandChannel($package,$io,$software)){throw 'SOFTWARE_CHANNEL_NOT_CONFIRMED: preserve the software session'}
      $softwarePid=[int]$software['pid']
      $softwareVisible=$false
      for($attempt=0;$attempt -lt 3;$attempt++){
        $window=[YaWindow]::Find($softwarePid)
        if([YaWindow]::InputVisible($softwarePid,$window.ToInt64()) -or [YaWindow]::Front($softwarePid)){$softwareVisible=$true;break}
        Start-Sleep -Milliseconds 300
      }
      if(-not $softwareVisible){throw 'SOFTWARE_NOT_USER_VISIBLE: preserve the software session; do not restart it'}
    }
    $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,($name+'-Show-Visible'))
    [void]$ready.Reset();Write-YaAtomic (Join-Path $io 'hud_show_request.json') $pending
    $hud=Join-Path $PSScriptRoot 'ya_hud.ps1'
    $args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$hud,'-Show')
    $showDirectory=Split-Path $RequestFile -Parent
    $showProcess=Start-Process -FilePath $exe -ArgumentList (@($args|ForEach-Object{[YaWindow]::Quote([string]$_)}) -join ' ') -WorkingDirectory $package -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $showDirectory 'hud.stdout.log') -RedirectStandardError (Join-Path $showDirectory 'hud.stderr.log')
    [void]$showProcess.Handle;$showPid=$showProcess.Id;$shown=$false;$showUntil=[DateTime]::UtcNow.AddSeconds(22)
    try{
      while([DateTime]::UtcNow -lt $showUntil){if($ready.WaitOne(100)){$shown=$true;break};if($showProcess.HasExited -and $showProcess.ExitCode -ne 0){throw ('HUD_START_FAILED: exit='+$showProcess.ExitCode+'; inspect '+(Join-Path $showDirectory 'hud.stderr.log'))}}
    }finally{$showProcess.Dispose()}
    if(-not $shown){throw ('HUD_NOT_VISIBLE: no fresh user-desktop window confirmation; launcher pid='+$showPid+'; logs='+$showDirectory+'; close an obsolete panel manually if it owns this package')}
    $proof=Get-Content -LiteralPath (Join-Path $io 'hud_window.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $process=Get-Process -Id $proof.pid -ErrorAction Stop
    if($proof.request -cne $pending.request -or $proof.package_id -cne $pending.package_id -or $proof.desktop -cne 'WinSta0\Default' -or $process.StartTime.ToUniversalTime().Ticks.ToString() -cne $proof.process_start -or -not [YaWindow]::InputVisible([int]$proof.pid,[long]$proof.handle)){throw 'HUD_NOT_VISIBLE: actual process/window does not match this request'}
    $result=@{status='VISIBLE';request=$pending.request;host_pid=$PID;pid=$proof.pid;process_start=$proof.process_start;handle=$proof.handle;desktop=$proof.desktop;verified_utc=$proof.verified_utc}
    if($software){$window=[YaWindow]::Find([int]$software['pid']);if(-not [YaWindow]::InputVisible([int]$software['pid'],$window.ToInt64())){throw 'SOFTWARE_NOT_USER_VISIBLE: YA is visible but the registered software is not'};$result['software_pid']=$software['pid'];$result['software_handle']=$window.ToInt64();$result['software_visible']=$true}
  }finally{if($ready){$ready.Dispose()};if($held){$guard.ReleaseMutex()};$guard.Dispose()}
  Write-YaAtomic (Join-Path (Split-Path $RequestFile -Parent) 'result.json') $result
  exit 0
}catch{
  if($DesktopHost -and $pending -and $RequestFile){try{Write-YaAtomic (Join-Path (Split-Path $RequestFile -Parent) 'result.json') @{status='FAIL';request=$pending.request;host_pid=$PID;error=$_.Exception.Message}}catch{}}
  Write-Output ('HUD_NOT_VISIBLE: '+$_.Exception.Message);exit 1
}
