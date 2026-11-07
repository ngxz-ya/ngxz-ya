# 维护者参考实验：真实官方 Journal 批处理，不宣称交互式快连已验收。
param([Parameter(Mandatory=$true)][string]$JournalExe,[Parameter(Mandatory=$true)][string]$OutputDirectory,[double]$Length=20,[ValidateRange(1,600)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$pkg=Split-Path $PSScriptRoot -Parent
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
Assert-YaIsolatedPackage $pkg
. (Join-Path $pkg 'YA插件\真实记录.ps1')
. (Join-Path $pkg '安装卸载\运行时\ya_slots.ps1')
if ([double]::IsNaN($Length) -or [double]::IsInfinity($Length) -or $Length -lt 1 -or $Length -gt 1000) { throw '长度限 1～1000 mm' }
if (-not (Test-Path -LiteralPath $JournalExe)) { throw '缺少合法安装的官方 Journal' }
$slot='reference-nx10'; $entry=Join-Path $pkg 'YA插件\本包命令.ps1'
function Call-Runtime([string[]]$Arguments) {
  $lines=@(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry @Arguments)
  $lines | Write-Host
  $ErrorActionPreference='Stop'
  if ($LASTEXITCODE -ne 0) { throw ('运行时拒绝：'+($Arguments -join ' ')) }
  return ($lines -join "`n")
}
$id=[guid]::NewGuid().ToString('N')
$dir=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $id
[IO.Directory]::CreateDirectory($dir)|Out-Null
$source=Join-Path $PSScriptRoot '真实实体参考.cs'
Copy-Item -LiteralPath $source -Destination (Join-Path $dir 'probe.cs')
$executorHash=(Get-FileHash -LiteralPath $source).Hash+':'+(Get-FileHash -LiteralPath $PSCommandPath).Hash
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg '连接教练\连接经验\经验分存.ps1') ensure soft=NX10参考 slot=$slot
if ($LASTEXITCODE -ne 0) { throw '专属槽不可用' }
$null=Call-Runtime @('task_open',"slot=$slot",'tag=参数实体',"title=真实参数实体 $Length mm")
$taskId=(Get-Content -LiteralPath (Join-Path $pkg '经验库\流程.json') -Raw -Encoding UTF8 | ConvertFrom-Json).current.id
$softwareVersion=(Get-Item -LiteralPath $JournalExe).VersionInfo.FileVersion
$null=Call-Runtime @('exp_search',"slot=$slot",'q=参数实体')
$null=Call-Runtime @('exp_recall',"slot=$slot",'tag=参数实体','q=参数实体')
$lib=Join-Path $pkg '经验库';$resolved=Resolve-YaSlot $lib $slot
$index=Read-YaIndex $resolved.dir
$prior=$null
foreach($row in (Get-YaItems $index.entries)) {
  $candidate=Read-YaJsonFile (Get-YaFormalFile $resolved.dir $row.id)
  if ($candidate.independently_verified -and (Test-Path -LiteralPath $candidate.context.model) -and (Get-FileHash -LiteralPath $candidate.context.model).Hash -ceq $candidate.context.model_sha256 -and $candidate.context.software_version -eq $softwareVersion -and $candidate.context.executor_hash -eq $executorHash -and $candidate.context.applicability -eq 'length=1..1000 mm; width=12 mm; height=14 mm; NX10 official Journal') {
    $null=Call-Runtime @('exp_get',"slot=$slot",('id='+$row.id))
    $prior=$row.id; break
  }
}
$lengthText=$Length.ToString([Globalization.CultureInfo]::InvariantCulture)
$started=[DateTime]::UtcNow
$oldPath=$env:PATH; $oldBase=$env:UGII_BASE_DIR; $oldRoot=$env:UGII_ROOT_DIR
try {
  $env:UGII_ROOT_DIR=(Split-Path $JournalExe -Parent)+'\';$env:UGII_BASE_DIR=Split-Path $env:UGII_ROOT_DIR.TrimEnd('\') -Parent
  $env:PATH=$env:UGII_ROOT_DIR+';'+$env:PATH
  function Invoke-OfficialJournal([string]$Mode) {
    $name=if($Mode){'verify'}else{'execute'}
    $stdout=Join-Path $dir ($name+'.stdout.log');$stderr=Join-Path $dir ($name+'.stderr.log')
    $arguments=@(('"'+(Join-Path $dir 'probe.cs')+'"'),'-args',('"'+$dir+'"'),$lengthText)
    if($Mode){$arguments+=$Mode}
    $child=Start-Process -FilePath $JournalExe -WorkingDirectory (Split-Path $JournalExe -Parent) -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    [void]$child.Handle
    Write-YaAtomic (Join-Path $dir ($name+'.process.json')) @{pid=$child.Id;start=$child.StartTime.ToUniversalTime().ToString('o');request=$id;stage=$name}
    try {
      if(-not $child.WaitForExit($TimeoutSeconds*1000)){throw ('EXECUTION_UNKNOWN: timeout; software pid='+$child.Id+' may still execute. Do not resend.')}
      $child.WaitForExit()
      $exitCode=$child.ExitCode
      $text=[IO.File]::ReadAllText($stdout)+[IO.File]::ReadAllText($stderr)
      [IO.File]::WriteAllText((Join-Path $dir ($name+'.log')),$text,[Text.UTF8Encoding]::new($true))
      $marker=if($Mode){'INDEPENDENT_GEOMETRY_PASS'}else{'ACTUAL_GEOMETRY_PASS'}
      if($exitCode -ne 0 -or $text -notmatch $marker){throw ('OFFICIAL_API_FAILED: stage='+$name+' exit='+$exitCode+'; inspect '+$dir)}
    } finally {$child.Dispose()}
  }
  Invoke-OfficialJournal ''
  Invoke-OfficialJournal 'verify'
} catch {
  $failure=$_.Exception.Message
  Add-YaActualEvent $pkg 'reference_failed' @{task=$taskId;slot=$slot;error=$failure;directory=$dir}
  $null=Call-Runtime @('step_hand',('note='+$failure))
  throw
} finally { $env:PATH=$oldPath;$env:UGII_BASE_DIR=$oldBase;$env:UGII_ROOT_DIR=$oldRoot }
$model=Join-Path $dir ('block-'+$lengthText+'.prt')
$readback=Get-Content -LiteralPath (Join-Path $dir 'verify.log') -Raw
$measure=([regex]::Match($readback,'INDEPENDENT_READBACK ([^\r\n]+)')).Groups[1].Value.Split(',')
$actualLength=[double]::Parse($measure[0],[Globalization.CultureInfo]::InvariantCulture)
$context=[ordered]@{task=$taskId; software='NX'; software_version=(Get-Item -LiteralPath $JournalExe).VersionInfo.FileVersion; interface='NXOpen Journal'; parameters=@{length=$Length;width=12;height=14;unit='mm'}; model_input="create 10x12x14 then edit length to $lengthText"; steps=@('create parameter block','edit length expression','update geometry','save','reopen in independent software process','measure bounds'); outcome='success'; recovery='failed attempts retain logs; no overwrite'; applicability='length=1..1000 mm; width=12 mm; height=14 mm; NX10 official Journal'; executor_hash=$executorHash; model=$model; model_sha256=(Get-FileHash -LiteralPath $model).Hash; execute_log=(Join-Path $dir 'execute.log'); verify_log=(Join-Path $dir 'verify.log')}
$recipeFile=Join-Path $dir 'method-record.json'
$recipe=[ordered]@{schema=1;title='参数实体：表达式修改并独立回读';objective='根据任务参数创建实体，修改允许变化的尺寸并独立核对保存结果';conditions=@{slot=$slot;software=$context.software;version=$context.software_version;interface=$context.interface;parameters=$context.parameters};steps=@('确认这是独立测试文档，禁止覆盖用户原文件','创建初始参数实体，再修改长度表达式并更新几何','保存后用另一个软件进程重开，读取实际尺寸并按容差比较');verification=@{check='独立重开保存模型，检查实体数量及三个方向尺寸';evidence=@($context.execute_log,$context.verify_log,$context.model);claimed_result='本次独立软件读回通过'};recovery=$context.recovery;applicability=$context.applicability;source='本次官方接口执行和独立软件回读；每个任务保留自己的证据'}
Write-YaAtomic $recipeFile $recipe
$draftText=Call-Runtime @('exp_done',"slot=$slot",'tag=参数实体','c=招式',('record='+$recipeFile),'k=参数实体')
$draftId=([regex]::Match($draftText,'(?m)^(?:id|draft):\s*(\S+)')).Groups[1].Value
if (-not $draftId) { throw '未获得草稿编号' }
$guard=New-Object Threading.Mutex($false,('Local\YARuntime-'+[YaEvidence]::Identity($pkg)));$held=$false
try {
  try {$held=$guard.WaitOne(10000)} catch [Threading.AbandonedMutexException] {$held=$true}
  if(-not $held){throw '经验库忙'}
  $saved=Publish-YaDraft $resolved.dir $slot $draftId '通过官方Journal创建参数实体；修改长度表达式后更新几何；保存并在另一软件进程重开测量。只适用于记录的接口、参数边界与执行器版本。' @(@{name='length';expected=$Length;actual=$actualLength;tolerance=0.001;unit='mm'},@{name='width';expected=12;actual=[double]::Parse($measure[1],[Globalization.CultureInfo]::InvariantCulture);tolerance=0.001;unit='mm'},@{name='height';expected=14;actual=[double]::Parse($measure[2],[Globalization.CultureInfo]::InvariantCulture);tolerance=0.001;unit='mm'}) $context
  $file=Get-YaFormalFile $resolved.dir $saved.id
  $full=Read-YaJsonFile $file
  $full.verification_state='independent_software_readback';$full.independently_verified=$true
  Write-YaJsonFile $file $full
} finally {if($held){$guard.ReleaseMutex()};$guard.Dispose()}
Add-YaActualEvent $pkg 'experience_verified' @{task=$taskId;slot=$slot;experience=$saved.id;context=$context;elapsed_ms=([DateTime]::UtcNow-$started).TotalMilliseconds;reused_experience=$prior;verification='independent_software_readback';mode='official_journal_batch'}
foreach($check in @('search','compare','draft','claim','inspect')){$null=Call-Runtime @('step_check',"item=$check",'pass=1','note=官方软件执行及独立新进程几何回读通过')}
$null=Call-Runtime @('step_finish');$null=Call-Runtime @('step_accept','note=参考实验自动几何验收；包级结果仍待用户人工验收')
Write-YaAtomic (Join-Path $dir 'result.json') @{task=$taskId;experience=$saved.id;reused_experience=$prior;context=$context;mode='official_journal_batch';live_link_verified=$false}
Write-Output ('result: '+(Join-Path $dir 'result.json'))
