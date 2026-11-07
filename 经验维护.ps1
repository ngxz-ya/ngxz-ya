param([Parameter(Mandatory=$true)][string]$Slot,[Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Reason)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'YA插件\连接上下文.ps1')
. (Join-Path $PSScriptRoot 'YA插件\真实记录.ps1')
. (Join-Path $PSScriptRoot '安装卸载\运行时\ya_slots.ps1')
$lock=[Threading.Mutex]::new($false,('Local\YARuntime-'+[YaEvidence]::Identity($PSScriptRoot)));$held=$false
try{
 Assert-YaIsolatedPackage $PSScriptRoot
 if([string]::IsNullOrWhiteSpace($Reason) -or $Reason.Length -gt 2000){throw '请说明为什么停用这条经验'}
 $held=$lock.WaitOne(10000);if(-not $held){throw 'BUSY'}
 Assert-YaOperation $PSScriptRoot
 $slotInfo=Resolve-YaSlot (Join-Path $PSScriptRoot '经验库') $Slot
 $file=Get-YaFormalFile $slotInfo.dir $Id;if(-not $file){throw 'EXPERIENCE_NOT_FOUND'}
 $record=Read-YaJsonFile $file
 $history=Join-Path $slotInfo.dir ('_历史\'+$Id+'-'+[guid]::NewGuid().ToString('N')+'.json')
 Write-YaAtomic $history $record
 $record|Add-Member -NotePropertyName lifecycle -NotePropertyValue withdrawn -Force
 $record|Add-Member -NotePropertyName withdrawal -NotePropertyValue @{reason=$Reason;time=[DateTime]::UtcNow.ToString('o');original=$history} -Force
 $record.independently_verified=$false
 Write-YaJsonFile $file $record
 Add-YaActualEvent $PSScriptRoot 'experience_withdrawn' @{slot=$Slot;experience=$Id;reason=$Reason;history=$history}
 @{status='WITHDRAWN';experience=$Id;note='原方法与证据保留供排查；任务执行器拒绝把它作为可信复用。修正后另行实测生成新记录。'}|ConvertTo-Json
}finally{if($held){$lock.ReleaseMutex()};$lock.Dispose()}
