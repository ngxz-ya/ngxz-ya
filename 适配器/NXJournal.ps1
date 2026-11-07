function Get-YaAdapterEnvironment($Adapter) {
  $roots=New-Object 'Collections.Generic.List[string]'
  foreach($name in @('UGII_BASE_DIR','UGII_ROOT_DIR')) {
    $value=[Environment]::GetEnvironmentVariable($name)
    if($value) { $roots.Add($value) }
  }
  foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    foreach($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match '^(Siemens\s+)?NX\s+10(?:\.|\s|$)'})) {
      if($item.InstallLocation) { $roots.Add([string]$item.InstallLocation) }
    }
  }
  $candidates=@()
  foreach($rootPath in ($roots | Select-Object -Unique)) {
    foreach($relative in @('UGII\run_journal.exe','run_journal.exe')) {
      $exe=Join-Path $rootPath $relative
      if(Test-Path -LiteralPath $exe -PathType Leaf) {
        $version=(Get-Item -LiteralPath $exe).VersionInfo.FileVersion
        $managed=Join-Path (Split-Path $exe -Parent) 'managed'
        $missing=@(@('NXOpen.dll','NXOpen.UF.dll','ManagedLoader.dll') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $managed $_)) })
        $candidates+= [pscustomobject]@{journal=[IO.Path]::GetFullPath($exe);version=$version;missing_dependencies=$missing;compatible=($Adapter.validated_versions -contains $version)}
      }
    }
  }
  $selected=@($candidates | Where-Object {$_.compatible -and $_.missing_dependencies.Count -eq 0} | Sort-Object journal -Unique)
  if($selected.Count -gt 0) { return [ordered]@{status='READY';installation=$selected[0];license='UNKNOWN_UNTIL_OFFICIAL_API_EXECUTION'} }
  if($candidates.Count -gt 0) { return [ordered]@{status='UNVERIFIED_VERSION_OR_MISSING_SDK';candidates=$candidates;next='Use a validated version with its installed official managed API. No SDK binary is supplied.'} }
  return [ordered]@{status='NOT_INSTALLED_OR_NOT_DISCOVERABLE';next='Install the legally licensed target software using its official installer. No matching registry entry or official environment path was found.'}
}

function Invoke-YaAdapterTask([string]$Package,$Environment,[string]$Work,[double]$Length,[int]$TimeoutSeconds) {
  $lines=@(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Package '测试\真实闭环.ps1') -JournalExe $Environment.installation.journal -OutputDirectory $Work -Length $Length -TimeoutSeconds $TimeoutSeconds)
  return @{lines=$lines;exit_code=$LASTEXITCODE}
}
