param([string]$DesktopSession)
$ErrorActionPreference='Stop'
$package=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $package 'YA插件\连接上下文.ps1')
. (Join-Path $package 'YA插件\真实记录.ps1')
Assert-YaIsolatedPackage $package
$homePath=Get-YaPackageHudHome $package
$io=Join-Path $homePath 'io'
$tools=Join-Path (Split-Path $package -Parent) 'OpenCAD'
$binary=Join-Path $tools 'software\FreeCAD_1.1.4-Windows-x86_64-py311\bin'
$gui=Join-Path $binary 'FreeCAD.exe'
$cmd=Join-Path $binary 'FreeCADCmd.exe'
$entry=Join-Path $package 'YA插件\ya_link.ps1'
$work=[YaEvidence]::Work($package,'freecad')
$version='1.1.4'
$pending=Join-Path $tools 'launch.json'
$userConfig=Join-Path $tools 'user.cfg'
function Read-Json([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
if($DesktopSession){
 $state=Read-Json $pending
 if($state.status -cne 'starting' -or $state.session -cne $DesktopSession -or $DesktopSession -cnotmatch '^[a-f0-9]{32}$'){throw 'OPEN_CAD_SESSION_MISMATCH'}
 $session=Join-Path $tools $DesktopSession
 $result=Join-Path $session 'desktop.json'
 try{
  if(Test-Path -LiteralPath (Join-Path $session 'process.json')){throw 'OPEN_CAD_SESSION_ALREADY_STARTED'}
  if([YaWindow]::Desktop() -cne 'WinSta0\Default'){throw 'OPEN_CAD_DESKTOP_REQUIRED'}
  $nativeSession=$session
  if($session -match '[^\x20-\x7E]'){
   $base=$env:LOCALAPPDATA
   if(-not $base -or $base -match '[^\x20-\x7E]'){$base=$env:TEMP}
   if(-not $base -or $base -match '[^\x20-\x7E]'){throw 'OPEN_CAD_ASCII_START_PATH_REQUIRED: use a workspace with an ASCII path'}
   $alias=Join-Path $base ('YALink\OpenCAD\'+$DesktopSession)
   [IO.Directory]::CreateDirectory((Split-Path $alias -Parent))|Out-Null
   if(Test-Path -LiteralPath $alias){throw 'OPEN_CAD_START_ALIAS_EXISTS'}
   New-Item -ItemType Junction -Path $alias -Target $tools | Out-Null
   $nativeSession=Join-Path $alias $DesktopSession
  }
  $env:YA_FREECAD_SESSION=$nativeSession
  $env:FREECAD_USER_HOME=$nativeSession
  $env:FREECAD_USER_DATA=$nativeSession
  $argv=@('-u','..\user.cfg','-s','system.cfg','--log-file','freecad.log','FrontProbe.FCMacro')
  $app=Start-Process -FilePath $gui -ArgumentList (@($argv|ForEach-Object{[YaWindow]::Quote($_)}) -join ' ') -WorkingDirectory $nativeSession -PassThru -RedirectStandardOutput (Join-Path $session 'stdout.log') -RedirectStandardError (Join-Path $session 'stderr.log')
  [void]$app.Handle
  Write-YaAtomic (Join-Path $session 'process.json') @{pid=$app.Id;start=$app.StartTime.ToUniversalTime().Ticks.ToString();native_directory=$nativeSession}
  $readyPath=Join-Path $session 'bridge-ready.json'
  $deadline=[DateTime]::UtcNow.AddSeconds(75)
  while(-not [IO.File]::Exists($readyPath) -and -not $app.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
  if(-not [IO.File]::Exists($readyPath) -or $app.HasExited){throw 'OPEN_CAD_GUI_OR_BRIDGE_NOT_READY'}
  $ready=Read-Json $readyPath
  if($ready.pid -ne $app.Id -or $ready.version -cne $version -or $ready.bridge_sha256 -cne $state.bridge_sha256){throw 'OPEN_CAD_WRONG_PROCESS_OR_VERSION'}
  if(-not [YaWindow]::Front($app.Id)){throw 'OPEN_CAD_WINDOW_NOT_VISIBLE'}
  $target=@('soft=FreeCAD','slot=freecad',('pid='+$app.Id))
  $prepare=@(& $entry @target prepare=1)
  $prepareCode=$LASTEXITCODE
  $prepare|Set-Content -LiteralPath (Join-Path $session 'prepare.log') -Encoding UTF8
  if($prepareCode -ne 2){throw 'OPEN_CAD_CHALLENGE_FAILED'}
  $challenge=Read-Json (Join-Path $io 'challenge.json')
  $proof=Join-Path (Join-Path $work $challenge.session) 'readback.json'
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while(-not [IO.File]::Exists($proof) -and -not $app.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 150}
  if(-not [IO.File]::Exists($proof) -or -not [YaWindow]::Front($app.Id)){throw 'OPEN_CAD_READBACK_MISSING'}
  $registered=@(& $entry @target)
  $registerCode=$LASTEXITCODE
  $registered|Set-Content -LiteralPath (Join-Path $session 'register.log') -Encoding UTF8
  if($registerCode){throw 'OPEN_CAD_REGISTRATION_FAILED'}
  Write-YaAtomic $result @{ok=$true;pid=$app.Id}
 }catch{Write-YaAtomic $result @{ok=$false;error=$_.Exception.Message};exit 1}
 exit 0
}

Assert-YaOperation $package
$linkPath=Join-Path $io 'link.json'
if(Test-Path -LiteralPath $linkPath){
 $link=[YaEvidence]::Read($linkPath)
 if(-not [YaEvidence]::CheckCommandChannel($package,$io,$link)){
  if($link['slot'] -cne 'freecad'){throw 'OPEN_CAD_OTHER_SOFTWARE_ACTIVE: preserve the registered session'}
  if([YaEvidence]::HasFrontendAcceptance($package,$io,$link)){
   & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'YA插件\show_ya.ps1') -WithSoftware
   if($LASTEXITCODE){exit $LASTEXITCODE}
   @{status='CONNECTED_INTERACTIVE';live_link=$true;reused_session=$true;next='用 Run 和任务文件修改当前模型'}|ConvertTo-Json
   exit 0
  }
 }
}
if(Test-Path -LiteralPath $pending){
 $previous=Read-Json $pending
 if($previous.status -cne 'completed'){throw 'OPEN_CAD_REVIEW_PREVIOUS_LAUNCH: preserve OpenCAD/launch.json and its session logs'}
 $previousApp=Get-Process -Id $previous.pid -ErrorAction SilentlyContinue
 if($previousApp -and $previousApp.StartTime.ToUniversalTime().Ticks.ToString() -ceq $previous.process_start){throw 'OPEN_CAD_PREVIOUS_WINDOW_STILL_OPEN: preserve the existing document'}
}
[IO.Directory]::CreateDirectory($tools)|Out-Null
if(-not [IO.File]::Exists($userConfig)){
 [IO.File]::WriteAllText($userConfig,'<?xml version="1.0" encoding="UTF-8"?><FCParameters><FCParamGroup Name="Root"><FCParamGroup Name="BaseApp"><FCParamGroup Name="Preferences"><FCParamGroup Name="General"><FCText Name="Language">Chinese (Simplified)</FCText></FCParamGroup></FCParamGroup></FCParamGroup></FCParamGroup></FCParameters>',[Text.UTF8Encoding]::new($false))
}
function Get-VerifiedDownload([string]$Name,[string]$Url,[string]$Hash){
 $file=Join-Path $tools $Name
 if(-not [IO.File]::Exists($file)){
  $tmp=$file+'.partial'
  if(Test-Path -LiteralPath $tmp){throw ('OPEN_CAD_INCOMPLETE_DOWNLOAD: '+$tmp)}
  & curl.exe -fLsS --connect-timeout 20 --max-time 420 --output $tmp $Url
  if($LASTEXITCODE -or (Get-FileHash -LiteralPath $tmp).Hash -ine $Hash){throw ('OPEN_CAD_DOWNLOAD_OR_HASH_FAILED: '+$Name)}
  [IO.File]::Move($tmp,$file)
 }
 if((Get-FileHash -LiteralPath $file).Hash -ine $Hash){throw ('OPEN_CAD_HASH_MISMATCH: '+$Name)}
 return $file
}
$verifiedMarker=Join-Path $tools 'verified-1.1.4.json'
if(-not [IO.File]::Exists($verifiedMarker)){
 $archive=Get-VerifiedDownload 'FreeCAD-1.1.4.7z' 'https://github.com/FreeCAD/FreeCAD/releases/download/1.1.4/FreeCAD_1.1.4-Windows-x86_64-py311.7z?download=1' '4828741FC91EE37FAFCDB97A1ABACB18B04BA451AC4372D9FF7A7349B36F4D6D'
 $extractor=Get-VerifiedDownload '7zr-26.06.exe' 'https://github.com/ip7z/7zip/releases/download/26.06/7zr.exe' 'E80DB2DAD715A6C5ADABE292D31ED54E11F4E9B99CA349827B50573B175891BC'
 $destination=Join-Path $tools 'software'
 if(Test-Path -LiteralPath $destination){throw 'OPEN_CAD_INCOMPLETE_EXTRACTION: preserve the previous directory'}
 [IO.Directory]::CreateDirectory($destination)|Out-Null
 . (Join-Path $package '适配器\运行工具.ps1')
 $null=Invoke-YaNativeProcess -FilePath $extractor -Arguments @('x',$archive,('-o'+$destination),'-y') -Directory $tools -Name extract -TimeoutSeconds 300
 if(-not [IO.File]::Exists($gui) -or -not [IO.File]::Exists($cmd)){throw 'OPEN_CAD_BINARIES_MISSING'}
 Write-YaAtomic $verifiedMarker @{gui=(Get-FileHash -LiteralPath $gui).Hash;reader=(Get-FileHash -LiteralPath $cmd).Hash}
}
$verified=Read-Json $verifiedMarker
if((Get-FileHash -LiteralPath $gui).Hash -cne $verified.gui -or (Get-FileHash -LiteralPath $cmd).Hash -cne $verified.reader){throw 'OPEN_CAD_BINARIES_CHANGED'}
$local=Join-Path $package '连接教练\连接经验\freecad'
$methodFiles=@('driver.ps1','verify.ps1','freecad.json','方法.json')
$existing=@($methodFiles | Where-Object {Test-Path -LiteralPath (Join-Path $local $_)})
[IO.Directory]::CreateDirectory($local)|Out-Null
$driver=@"
param(`$Action,`$Context)
`$pkg=Split-Path (Split-Path (Split-Path `$PSScriptRoot -Parent) -Parent) -Parent
& (Join-Path `$pkg '适配器\前台驱动.ps1') -Action `$Action -Context `$Context
exit `$LASTEXITCODE
"@
$driverFile=Join-Path $local 'driver.ps1';$readerFile=Join-Path $local 'verify.ps1'
$bridge=Join-Path $PSScriptRoot 'bridge.py'
$bridgeHash=(Get-FileHash -LiteralPath $bridge).Hash
$readerHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'reader.py')).Hash
if($existing.Count){
 if($existing.Count -ne $methodFiles.Count){throw 'OPEN_CAD_INCOMPLETE_METHOD'}
 $current=Read-Json (Join-Path $local '方法.json')
 $config=Read-Json (Join-Path $local 'freecad.json')
 if($current.software -cne 'FreeCAD' -or $current.software_version -cne $version -or $current.frontend.bridge_sha256 -cne $bridgeHash -or $config.reader -ine $cmd -or $config.reader_sha256 -cne $readerHash -or [IO.File]::ReadAllText($driverFile) -cne $driver -or (Get-FileHash -LiteralPath $readerFile).Hash -cne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'read.ps1')).Hash){throw 'OPEN_CAD_EXISTING_METHOD: preserve the user method'}
}else{
 [IO.File]::WriteAllText($driverFile,$driver,[Text.UTF8Encoding]::new($true))
 [IO.File]::Copy((Join-Path $PSScriptRoot 'read.ps1'),$readerFile,$false)
Write-YaAtomic (Join-Path $local 'freecad.json') @{reader=$cmd;reader_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'reader.py')).Hash}
Write-YaAtomic (Join-Path $local '方法.json') @{schema=1;software='FreeCAD';software_version=$version;interface='FreeCAD Python / frontend-task/1';mode='interactive';status='reviewed';sources=@('https://github.com/FreeCAD/FreeCAD/releases/tag/1.1.4','ngxz-ya bundled connector');license_review='Original connector and separately downloaded upstream software';safety_review='Dedicated document, bounded dimensions and local user-only channel';driver='driver.ps1';driver_sha256=(Get-FileHash -LiteralPath $driverFile).Hash;frontend=@{bridge_sha256=$bridgeHash;reader='verify.ps1';reader_sha256=(Get-FileHash -LiteralPath $readerFile).Hash;extension='fcstd'}}
}
$id=[guid]::NewGuid().ToString('N')
$session=Join-Path $tools $id
[IO.Directory]::CreateDirectory($session)|Out-Null
[IO.File]::Copy($bridge,(Join-Path $session 'FrontProbe.FCMacro'),$false)
Write-YaAtomic (Join-Path $session 'bridge-config.json') @{io=$io;work=$work}
Write-YaAtomic $pending @{status='starting';session=$id;bridge_sha256=$bridgeHash}
$exe=Join-Path $PSHOME 'powershell.exe'
$argv=@($exe,'-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-DesktopSession',$id)
$startup=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0;WinstationDesktop='WinSta0\Default';CreateFlags=[uint32]0x09000000}
$launch=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=(@($argv|ForEach-Object{[YaWindow]::Quote($_)}) -join ' ');CurrentDirectory=$session;ProcessStartupInformation=$startup} -OperationTimeoutSec 15
if($launch.ReturnValue){throw 'OPEN_CAD_DESKTOP_LAUNCH_FAILED'}
$result=Join-Path $session 'desktop.json'
$deadline=[DateTime]::UtcNow.AddSeconds(130)
while(-not [IO.File]::Exists($result) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
if(-not [IO.File]::Exists($result)){throw ('OPEN_CAD_DESKTOP_TIMEOUT: '+$session)}
$desktop=Read-Json $result
if(-not $desktop.ok){throw ($desktop.error+'; evidence='+$session)}
$plan=Join-Path $session 'first-task.json'
$measures=@(@{name='length';value=20;tolerance=0.001},@{name='width';value=12;tolerance=0.001},@{name='height';value=14;tolerance=0.001},@{name='body_count';value=1})
Write-YaAtomic $plan @{schema=1;title='FreeCAD 参数化长方体';keywords=@('长方体','方块','尺寸修改');objective='在独立前台文档中更新参数化方块，保存并独立核对实际尺寸';parameters=@{length=20;width=12;height=14};steps=@(@{action='set_box';description='修改方块的长宽高并保存独立快照'});expected=$measures;applicability='本适配器的独立 Part::Box 文档，尺寸 1–1000 mm';recovery='保留窗口和本次日志；未知结果不重发'}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package '连接软件.ps1') -Software FreeCAD -Action Connect -TaskFile $plan
$code=$LASTEXITCODE
if($code -eq 0){
 $process=Read-Json (Join-Path $session 'process.json')
 Write-YaAtomic $pending @{status='completed';session=$id;pid=$process.pid;process_start=$process.start;bridge_sha256=$bridgeHash}
}
exit $code