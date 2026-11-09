param([Parameter(Mandatory=$true)][string]$Context)
$ErrorActionPreference='Stop'
$package=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $package '适配器\运行工具.ps1')
$c=Get-Content -LiteralPath $Context -Raw -Encoding UTF8|ConvertFrom-Json
$local=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'freecad.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script=Join-Path $package '适配器\FreeCAD\reader.py'
if((Get-FileHash -LiteralPath $script).Hash -cne $local.reader_sha256){throw 'FREECAD_READER_CHANGED'}
$env:FREECAD_USER_HOME=$c.directory
$env:FREECAD_USER_DATA=$c.directory
$raw=Join-Path $c.directory 'freecad-native.json'
$stdin=Join-Path $c.directory 'freecad.stdin'
if(Test-Path -LiteralPath $raw){throw 'FREECAD_REFUSE_OLD_READBACK'}
$encode={param($value) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))}
$cmd="import base64, json, runpy; from pathlib import Path; get=lambda s:base64.b64decode(s).decode('utf-8'); report=runpy.run_path(get('$( & $encode $script )'))['measure'](get('$( & $encode $Context )')); Path(get('$( & $encode $raw )')).write_text(json.dumps(report),encoding='utf-8'); exit()"
[IO.File]::WriteAllText($stdin,$cmd+[Environment]::NewLine,[Text.Encoding]::ASCII)
$run=Invoke-YaNativeProcess -FilePath $local.reader -Arguments @('-c','-u','reader-user.cfg','-s','reader-system.cfg','--log-file','native-freecad.log') -Directory $c.directory -Name native_freecad -StandardInput $stdin -TimeoutSeconds ([Math]::Max(1,[int]$c.timeout_seconds-5))
$data=Get-Content -LiteralPath $raw -Raw -Encoding UTF8|ConvertFrom-Json
if($data.pid -ne $run.pid -or [IO.Path]::GetFullPath($data.model) -ine [IO.Path]::GetFullPath($c.model) -or $data.version -cne $c.software_version){throw 'FREECAD_WRONG_NATIVE_REOPEN'}
$items=@($data.measurements.PSObject.Properties | ForEach-Object {@{name=$_.Name;value=$_.Value}})
Write-YaReadback -Context $c -Measurements $items -Artifacts @($c.model,$raw,$run.stdout,$run.stderr) -Source independent_software_reopen -ReaderPid $run.pid -ModelSha256 (Get-FileHash -LiteralPath $c.model).Hash