# 安装 YA 工具包的运行目录。可重复执行。
# 只复制脚本、写下用户环境变量、核对经验槽。
# 不启动机械软件，不改软件安装目录，不写厂商启动项。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\安装卸载\安装.ps1"
param([switch]$PackageOnly)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$SrcRuntime = Join-Path $PSScriptRoot '运行时'
$Package = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
. (Join-Path $Package 'YA插件\连接上下文.ps1') -PathsOnly
Assert-YaIsolatedPackage $Package
if(-not $PackageOnly){throw 'ISOLATED_INSTALL_ONLY: 隔离包安装必须使用 -PackageOnly，禁止修改用户全局安装。'}
$log = New-Object System.Collections.Generic.List[string]
function Say([string]$m) { [void]$log.Add($m); Write-Output $m }

function Read-State([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

try {
  Say '=== YA 工具包 安装 ==='
  if (-not (Test-Path -LiteralPath (Join-Path $SrcRuntime 'ya.ps1'))) { throw ('缺少运行脚本: ' + $SrcRuntime) }
  if (-not (Test-Path -LiteralPath (Join-Path $Package '经验库\槽位.json'))) { throw ('缺少经验槽配置: ' + (Join-Path $Package '经验库\槽位.json')) }

  . (Join-Path $SrcRuntime 'ya_slots.ps1')
  $lib = Initialize-YaLibrary $Package
  Say ('经验库: ' + $lib)

  . (Join-Path $Package 'YA插件\连接上下文.ps1')
  $yaDir=Join-Path (Get-YaPackageHudHome $Package) '安装'
  Say ('准备写入运行目录: '+$yaDir)
  if (-not (Test-Path -LiteralPath $yaDir)) { New-Item -ItemType Directory -Path $yaDir | Out-Null }
  Say ('运行目录: ' + $yaDir)

  $copied = @('ya.ps1', 'ya_slots.ps1', 'ya_flow.ps1', 'ya_panel.ps1')
  foreach ($name in $copied) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $SrcRuntime $name))
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $start = 0
    if ($hasBom) { $start = 3 }
    $text = (New-Object Text.UTF8Encoding $false).GetString($bytes, $start, $bytes.Length - $start)
    [IO.File]::WriteAllText((Join-Path $yaDir $name), $text, (New-Object Text.UTF8Encoding $true))
    Say ('  已复制 ' + $name)
  }
  $utf8 = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText((Join-Path $yaDir 'package_root.txt'), $Package, $utf8)
  [IO.File]::WriteAllText((Join-Path $yaDir 'library_path.txt'), $lib, $utf8)

  $statePath = Join-Path $yaDir 'install_state.json'
  $old = Read-State $statePath
  $envRows = New-Object System.Collections.Generic.List[object]
  foreach ($pair in @(
      @{ name = 'YALINK_HOME'; value = $yaDir },
      @{ name = 'YALINK_PACKAGE'; value = $Package }
    )) {
    if($PackageOnly){continue}
    $had = $false
    $previous = ''
    $kept = $false
    if ($old -and $old.env) {
      foreach ($row in @($old.env)) {
        if ([string]$row.name -eq $pair.name -and $row.set) {
          $had = [bool]$row.had
          $previous = [string]$row.previous
          $kept = $true
        }
      }
    }
    if (-not $kept) {
      $cur = [Environment]::GetEnvironmentVariable($pair.name, 'User')
      if ($cur) { $had = $true; $previous = $cur }
    }
    [Environment]::SetEnvironmentVariable($pair.name, $pair.value, 'User')
    [void]$envRows.Add([ordered]@{
        name     = $pair.name
        set      = $true
        had      = $had
        previous = $previous
      })
    Say ('  用户环境变量 ' + $pair.name + '=' + $pair.value)
  }

  $generated = @('package_root.txt', 'library_path.txt', 'install_state.json', 'install.log')
  $state = [ordered]@{
    version   = 1
    time      = (Get-Date).ToString('s')
    home      = $yaDir
    package   = $Package
    library   = $lib
    copied    = $copied
    generated = $generated
    env       = $envRows
  }
  if(-not $old -or $old.version -ne 1 -or $old.home -ine $yaDir -or $old.package -ine $Package -or
     $old.library -ine $lib -or ($old.copied -join ',') -cne ($copied -join ',') -or ($old.generated -join ',') -cne ($generated -join ',')){
    Write-YaJsonFile $statePath $state
  }

  Say '不探测、不修改任何机械软件，也不读取本机装了哪些软件。'
  Say ''
  Say '自检:'
  $check = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $yaDir 'ya.ps1') self_check 2>&1
  foreach ($line in @($check)) { Say ('  ' + [string]$line) }
  if ($LASTEXITCODE -ne 0) { throw '装好后的自检没有通过。' }

  Say ''
  if($PackageOnly){Say '下一步: 看 使用说明.txt。卸掉本包安装用 安装卸载\卸载.ps1 -PackageOnly'}
  else{Say '下一步: 看 使用说明.txt。卸掉旧式全局安装用 安装卸载\卸载.ps1'}
  Say 'RESULT: OK'
  $log | Set-Content -LiteralPath (Join-Path $yaDir 'install.log') -Encoding UTF8
  exit 0
}
catch {
  Say ('ERROR: ' + $_.Exception.Message)
  Say 'RESULT: FAIL'
  try {
    $yaDirTry=$yaDir
    if (Test-Path -LiteralPath $yaDirTry) {
      $log | Set-Content -LiteralPath (Join-Path $yaDirTry 'install.log') -Encoding UTF8
    }
  } catch { }
  exit 1
}
