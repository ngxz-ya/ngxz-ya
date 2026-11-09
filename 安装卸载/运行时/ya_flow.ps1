# 连接教练、任务自检、调用与 TOKEN 登记。
# 由 ya.ps1 点源。不启动、不探测任何机械软件。Windows PowerShell 5.1。

function Get-YaNow {
  return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff')
}

function Get-YaObjProp($Obj, [string]$Name) {
  if ($null -eq $Obj) { return $null }
  if ($Obj -is [System.Collections.IDictionary]) {
    if (-not $Obj.Contains($Name)) { return $null }
    return $Obj[$Name]
  }
  $p = $Obj.PSObject.Properties[$Name]
  if (-not $p) { return $null }
  return $p.Value
}

function Get-YaTokenValue($Obj) {
  $p = Get-YaObjProp $Obj 'token'
  if ($null -eq $p) { return $null }
  $t = Repair-YaLine ([string]$p)
  if (-not $t -or $t -notmatch '^\d+$') { return $null }
  $n = [int64]0
  if (-not [int64]::TryParse($t, [ref]$n)) { return $null }
  # 登记口上限是 2000000000。更大的数读不进整数，不当成已登记，也不让总览中断。
  if ($n -gt 2000000000) { return $null }
  return [int]$n
}

function Format-YaToken($Value) {
  if ($null -eq $Value) { return '未统计' }
  return [string]$Value
}

function Test-YaFlag($Value) {
  if ($Value -is [bool]) { return $Value }
  $t = [string]$Value
  return ($t -eq 'True' -or $t -eq 'true' -or $t -eq '1')
}

function New-YaChecks {
  $items = @(
    @{ id = 'search'; title = '先检索再生成' },
    @{ id = 'compare'; title = '结果已对照' },
    @{ id = 'draft'; title = '未把草稿当完成' },
    @{ id = 'claim'; title = '未把未过关软件说成已接通' },
    @{ id = 'inspect'; title = '检验项逐条过关' }
  )
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($it in $items) {
    [void]$list.Add([ordered]@{ id = $it.id; title = $it.title; pass = $false; note = '' })
  }
  return ,$list
}

function Convert-YaTask($Obj) {
  if ($null -eq $Obj) { return $null }
  if ($Obj -is [string]) { return $null }
  $checks = New-Object System.Collections.Generic.List[object]
  foreach ($c in (Get-YaItems (Get-YaObjProp $Obj 'checks'))) {
    [void]$checks.Add([ordered]@{
        id    = (Get-YaTextProp $c 'id')
        title = (Get-YaTextProp $c 'title')
        pass  = (Test-YaFlag (Get-YaObjProp $c 'pass'))
        note  = (Get-YaTextProp $c 'note')
      })
  }
  if ($checks.Count -eq 0) { $checks = New-YaChecks }
  $events = New-Object System.Collections.Generic.List[object]
  foreach ($e in (Get-YaItems (Get-YaObjProp $Obj 'events'))) {
    [void]$events.Add([ordered]@{
        time = (Get-YaTextProp $e 'time')
        name = (Get-YaTextProp $e 'name')
        note = (Get-YaTextProp $e 'note')
      })
  }
  return [ordered]@{
    id        = (Get-YaTextProp $Obj 'id')
    title     = (Get-YaTextProp $Obj 'title')
    slot      = (Get-YaTextProp $Obj 'slot')
    tag       = (Get-YaTextProp $Obj 'tag')
    retrieved = (Test-YaFlag (Get-YaObjProp $Obj 'retrieved'))
    status    = (Get-YaTextProp $Obj 'status')
    complete  = (Test-YaFlag (Get-YaObjProp $Obj 'complete'))
    checks    = $checks
    events    = $events
  }
}

function Read-YaFlow([string]$Lib) {
  $o = Read-YaJsonFile (Join-Path $Lib '流程.json')
  $hist = New-Object System.Collections.Generic.List[object]
  foreach ($h in (Get-YaItems (Get-YaObjProp $o 'history'))) {
    $task = Convert-YaTask $h
    if ($task) { [void]$hist.Add($task) }
  }
  return @{
    note    = (Get-YaTextProp $o '说明')
    current = (Convert-YaTask (Get-YaObjProp $o 'current'))
    history = $hist
  }
}

function Write-YaFlowState([string]$Lib, $State) {
  $note = [string]$State.note
  if (-not $note) { $note = '进行中的任务和最近记录。自检未过不能报完成。' }
  $doc = [ordered]@{
    version = 1
    '说明'  = $note
    current = $State.current
    history = $State.history
  }
  Write-YaJsonFile (Join-Path $Lib '流程.json') $doc
}

function Add-YaEvent($Task, [string]$Name, [string]$Note) {
  [void]$Task['events'].Add([ordered]@{
      time = (Get-YaNow)
      name = $Name
      note = (Repair-YaLine $Note)
    })
  while ($Task['events'].Count -gt 30) { $Task['events'].RemoveAt(0) }
}

function ConvertTo-YaFitInt([string]$Text) {
  # 放得进 32 位的整数（含负数）仍保留。读不了或超出 32 位按 0，避免检索闸把整段命令打中断。
  $t = Repair-YaLine $Text
  if (-not $t -or $t -notmatch '^-?\d+$') { return 0 }
  $n = [int64]0
  if (-not [int64]::TryParse($t, [ref]$n)) { return 0 }
  if ($n -lt [int32]::MinValue -or $n -gt [int32]::MaxValue) { return 0 }
  return [int]$n
}

function Read-YaGate([string]$Lib) {
  $o = Read-YaJsonFile (Join-Path $Lib '检索闸.json')
  $hits = ConvertTo-YaFitInt (Get-YaTextProp $o 'hits')
  $consumed = $true
  if ($null -ne (Get-YaObjProp $o 'consumed')) { $consumed = Test-YaFlag (Get-YaObjProp $o 'consumed') }
  return @{
    slot     = (Get-YaTextProp $o 'slot')
    tag      = (Get-YaTextProp $o 'tag')
    query    = (Get-YaTextProp $o 'query')
    hits     = $hits
    time     = (Get-YaTextProp $o 'time')
    consumed = $consumed
  }
}

function Write-YaGate([string]$Lib, $Gate) {
  $doc = [ordered]@{
    version  = 1
    '说明'   = '最近一次检索。写入草稿前必须先检索，且槽要一致。用过一次就要重新检索。'
    slot     = [string]$Gate.slot
    tag      = [string]$Gate.tag
    query    = [string]$Gate.query
    hits     = (ConvertTo-YaFitInt ([string]$Gate.hits))
    time     = [string]$Gate.time
    consumed = [bool]$Gate.consumed
  }
  Write-YaJsonFile (Join-Path $Lib '检索闸.json') $doc
}

function Read-YaUsage([string]$Lib) {
  $o = Read-YaJsonFile (Join-Path $Lib '消耗.json')
  $slots = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems (Get-YaObjProp $o 'slots'))) {
    $calls = ConvertTo-YaCount (Get-YaTextProp $row 'calls')
    [void]$slots.Add([ordered]@{
        id    = (Get-YaTextProp $row 'id')
        calls = $calls
        token = (Get-YaTokenValue $row)
        note  = (Get-YaTextProp $row 'note')
      })
  }
  $cross = ConvertTo-YaCount (Get-YaTextProp $o 'cross_calls')
  return @{
    note        = (Get-YaTextProp $o '说明')
    cross_calls = $cross
    slots       = $slots
  }
}

function Write-YaUsage([string]$Lib, $Usage) {
  $slots = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $Usage.slots)) {
    $raw = $null
    if ($row -is [System.Collections.IDictionary]) { $raw = $row['calls'] } else { $raw = Get-YaObjProp $row 'calls' }
    $calls = ConvertTo-YaCount ([string]$raw)
    $id = ''
    $note = ''
    if ($row -is [System.Collections.IDictionary]) {
      $id = [string]$row['id']
      $note = [string]$row['note']
    } else {
      $id = Get-YaTextProp $row 'id'
      $note = Get-YaTextProp $row 'note'
    }
    [void]$slots.Add([ordered]@{
        id    = $id
        calls = $calls
        token = (Get-YaTokenValue $row)
        note  = $note
      })
  }
  $note = [string]$Usage.note
  if (-not $note) { $note = '各槽调用次数，和使用者自行登记的 TOKEN。没有登记就显示未统计。本包不读任何软件，也不把估算当成账单。' }
  $doc = [ordered]@{
    version     = 1
    '说明'      = $note
    cross_calls = (ConvertTo-YaCount ([string]$Usage.cross_calls))
    slots       = $slots
  }
  Write-YaJsonFile (Join-Path $Lib '消耗.json') $doc
}

function Remove-YaUsageSlot([string]$Lib, [string]$Id) {
  if (-not $Id -or $Id -eq 'all') { return $false }
  $usage = Read-YaUsage $Lib
  $keep = New-Object System.Collections.Generic.List[object]
  $removed = $false
  foreach ($row in (Get-YaItems $usage.slots)) {
    if ([string]$row['id'] -eq $Id) { $removed = $true }
    else { [void]$keep.Add($row) }
  }
  if (-not $removed) { return $false }
  $usage.slots = $keep
  Write-YaUsage $Lib $usage
  return $true
}

function Next-YaCount([int]$Value) {
  # 已经到 32 位顶上就停住。再加一会先变成更大的数，写回时按读不了收成 0。
  if ($Value -ge [int32]::MaxValue) { return [int32]::MaxValue }
  if ($Value -lt 0) { return 1 }
  return ($Value + 1)
}

function Add-YaCall([string]$Lib, [string]$SlotId) {
  $usage = Read-YaUsage $Lib
  if ($SlotId -eq 'all') {
    $usage.cross_calls = Next-YaCount ([int]$usage.cross_calls)
  } else {
    $found = $false
    foreach ($row in (Get-YaItems $usage.slots)) {
      if ([string]$row['id'] -eq $SlotId) {
        $row['calls'] = Next-YaCount ([int]$row['calls'])
        $found = $true
        break
      }
    }
    if (-not $found) {
      [void]$usage.slots.Add([ordered]@{ id = $SlotId; calls = 1; token = $null; note = '' })
    }
  }
  Write-YaUsage $Lib $usage
}

function Set-YaToken([string]$Lib, [string]$SlotId, [string]$Token, [string]$Note) {
  if (Test-YaCrossSlotWord $SlotId) { throw 'all 只能用来跨槽检索，不能登记 TOKEN。请写 usage_set slot=具体槽 token=数字。具体槽用 slot_list 看，不要把 all 当成槽。' }
  if (-not (Test-YaSlotId $SlotId)) { throw 'usage_set 的 slot 不合法。' }
  Resolve-YaSlot $Lib $SlotId | Out-Null
  $tokenValue = $null
  $raw = (Repair-YaLine $Token)
  if ($raw) {
    if ($raw -notmatch '^\d+$') { throw 'token 只能是非负整数，或留空表示未统计。' }
    if ([int64]$raw -gt 2000000000) { throw 'token 太大。' }
    $tokenValue = [int]$raw
  }
  $note = Repair-YaLine $Note
  if ($note.Length -gt 200) { throw '用量备注最长 200 字。' }
  Assert-YaClean $note
  $usage = Read-YaUsage $Lib
  $found = $false
  foreach ($row in (Get-YaItems $usage.slots)) {
    if ([string]$row['id'] -eq $SlotId) {
      $row['token'] = $tokenValue
      if ($note) { $row['note'] = $note }
      $found = $true
      break
    }
  }
  if (-not $found) {
    [void]$usage.slots.Add([ordered]@{ id = $SlotId; calls = 0; token = $tokenValue; note = $note })
  }
  Write-YaUsage $Lib $usage
  return @{ token = $tokenValue; note = $note }
}

function Convert-YaPending($Obj) {
  $steps = New-Object System.Collections.Generic.List[object]
  foreach ($s in (Get-YaItems (Get-YaObjProp $Obj 'steps'))) {
    $n = 0
    $raw = Get-YaTextProp $s 'step'
    if ($raw -match '^\d+$') { $n = [int]$raw }
    [void]$steps.Add([ordered]@{
        step = $n
        note = (Get-YaTextProp $s 'note')
        time = (Get-YaTextProp $s 'time')
      })
  }
  return [ordered]@{
    id    = (Get-YaTextProp $Obj 'id')
    title = (Get-YaTextProp $Obj 'title')
    steps = $steps
  }
}

function Read-YaLinks([string]$Lib) {
  $o = Read-YaJsonFile (Join-Path $Lib '已挂清单.json')
  $linked = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems (Get-YaObjProp $o 'linked'))) {
    [void]$linked.Add([ordered]@{
        id    = (Get-YaTextProp $row 'id')
        title = (Get-YaTextProp $row 'title')
        time  = (Get-YaTextProp $row 'time')
        task  = (Get-YaTextProp $row 'task')
      })
  }
  $pending = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems (Get-YaObjProp $o 'pending'))) {
    [void]$pending.Add((Convert-YaPending $row))
  }
  $failed = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems (Get-YaObjProp $o 'failed'))) {
    $n = 0
    $raw = Get-YaTextProp $row 'step'
    if ($raw -match '^\d+$') { $n = [int]$raw }
    [void]$failed.Add([ordered]@{
        id    = (Get-YaTextProp $row 'id')
        title = (Get-YaTextProp $row 'title')
        step  = $n
        note  = (Get-YaTextProp $row 'note')
        time  = (Get-YaTextProp $row 'time')
      })
  }
  return @{
    note    = (Get-YaTextProp $o '说明')
    linked  = $linked
    pending = $pending
    failed  = $failed
  }
}

function Write-YaLinks([string]$Lib, $Links) {
  $note = [string]$Links.note
  if (-not $note) { $note = '只收三步闸全部过关的软件。开了经验槽或写了草稿都不算已挂。本包不探测本机装了什么软件。' }
  while ($Links.failed.Count -gt 50) { $Links.failed.RemoveAt(0) }
  $doc = [ordered]@{
    version = 1
    '说明'  = $note
    linked  = $Links.linked
    pending = $Links.pending
    failed  = $Links.failed
  }
  Write-YaJsonFile (Join-Path $Lib '已挂清单.json') $doc
}

function Initialize-YaFlow([string]$Lib) {
  $noteLink = '只收三步闸全部过关的软件。开了经验槽或写了草稿都不算已挂。本包不探测本机装了什么软件。'
  $noteUse = '各槽调用次数，和使用者自行登记的 TOKEN。没有登记就显示未统计。本包不读任何软件，也不把估算当成账单。'
  $noteTag = '任务标签倒排。条目仍按软件槽分文件存放。检索先定槽，再用标签收窄。'
  $noteGate = '最近一次检索。写入草稿前必须先检索，且槽要一致。用过一次就要重新检索。'
  $noteFlow = '进行中的任务和最近记录。自检未过不能报完成。'
  $empty = New-Object System.Collections.Generic.List[object]
  $path = Join-Path $Lib '已挂清单.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-YaJsonFile $path ([ordered]@{ version = 1; '说明' = $noteLink; linked = $empty; pending = $empty; failed = $empty })
  }
  $path = Join-Path $Lib '消耗.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-YaJsonFile $path ([ordered]@{ version = 1; '说明' = $noteUse; cross_calls = 0; slots = $empty })
  }
  $path = Join-Path $Lib '任务标签.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-YaJsonFile $path ([ordered]@{ version = 1; '说明' = $noteTag; tags = $empty })
  }
  $path = Join-Path $Lib '检索闸.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-YaJsonFile $path ([ordered]@{
        version = 1; '说明' = $noteGate; slot = ''; tag = ''; query = ''; hits = 0; time = ''; consumed = $true
      })
  }
  $path = Join-Path $Lib '流程.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-YaJsonFile $path ([ordered]@{ version = 1; '说明' = $noteFlow; current = $null; history = $empty })
  }
  Read-YaLinks $Lib | Out-Null
  Read-YaUsage $Lib | Out-Null
  Read-YaGate $Lib | Out-Null
  Read-YaFlow $Lib | Out-Null
  Read-YaJsonFile (Join-Path $Lib '任务标签.json') | Out-Null
}

function Get-YaHudHome {
  foreach ($scope in @('Process', 'User')) {
    $p = [Environment]::GetEnvironmentVariable('YALINK_HUD_HOME', $scope)
    if ($p) { return $p }
  }
  $local = Join-Path $env:LOCALAPPDATA 'YAHud'
  if ($local -match '[^\x00-\x7F]') { return (Join-Path $env:ProgramData 'YAHud') }
  return $local
}

function Read-YaLinkRegistration {
  $path = Join-Path (Get-YaHudHome) 'io\link.json'
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Read-YaJsonFile $path) } catch { return $null }
}

function ConvertTo-YaCount([string]$Text) {
  $t = Repair-YaLine $Text
  if (-not $t -or $t -notmatch '^\d+$') { return 0 }
  $n = [int64]0
  if (-not [int64]::TryParse($t, [ref]$n)) { return 0 }
  if ($n -lt 0 -or $n -gt [int32]::MaxValue) { return 0 }
  return [int]$n
}

function ConvertTo-YaPid([string]$Text) {
  # 登记里的 pid 可能大于有符号 32 位。直接转 int 会让总览整段失败。读不了就当没有进程。
  $n = ConvertTo-YaCount $Text
  if ($n -le 0) { return 0 }
  return $n
}

function Resolve-YaRegisteredSlot([string]$Lib, [string]$Raw) {
  # 只认本包槽位里的软件槽。大小写不同仍对上。generic、all、对不上的名字都不算软件侧。
  $name = (Repair-YaLine $Raw).ToLowerInvariant()
  if (-not $name -or $name -eq 'generic' -or (Test-YaCrossSlotWord $name)) { return '' }
  if (-not (Test-YaSlotId $name)) { return '' }
  $cfg = Read-YaSlots $Lib
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if ([string]$s.id -eq $name) { return $name }
  }
  return ''
}

function Test-YaForegroundPid([int]$ProcessId) {
  # 只核对登记里已经写下的 pid。不扫描本机装了什么软件，也不去连。
  if ($ProcessId -le 0) { return $false }
  try {
    $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    if ($proc.HasExited) { return $false }
    try { if (-not $proc.Responding) { return $false } } catch { return $false }
    if (-not ('YaSideGate.Win' -as [type])) {
      Add-Type -Namespace YaSideGate -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);'
    }
    $mw = $proc.MainWindowHandle
    if ($mw -eq [IntPtr]::Zero) { return $false }
    return [bool][YaSideGate.Win]::IsWindowVisible($mw)
  } catch { return $false }
}

function Get-YaSoftwareSide([string]$Lib) {
  $link = Read-YaLinkRegistration
  $connected = $false
  $slot = ''
  $entries = 0
  $drafts = 0
  $calls = 0
  if ($null -ne $link) {
    $state = [string](Get-YaTextProp $link 'state')
    $pidNum = ConvertTo-YaPid ([string](Get-YaTextProp $link 'pid'))
    $live = ($state -eq 'ok') -and (Test-YaForegroundPid $pidNum)
    $slotTry = ''
    if ($live) { $slotTry = Resolve-YaRegisteredSlot $Lib ([string](Get-YaTextProp $link 'slot')) }
    if ($slotTry) {
      $connected = $true
      $slot = $slotTry
      $cfg = Read-YaSlots $Lib
      $found = $null
      foreach ($s in (Get-YaItems $cfg.slots)) {
        if ([string]$s.id -eq $slotTry) { $found = $s; break }
      }
      if ($null -ne $found) {
        $dir = Get-YaSlotDir $Lib $found
        if (Test-Path -LiteralPath (Join-Path $dir '索引.json')) {
          $counts = Get-YaCounts $dir
          $entries = [int]$counts.entries
          $drafts = [int]$counts.drafts
        }
        $usage = Read-YaUsage $Lib
        foreach ($u in (Get-YaItems $usage.slots)) {
          if ([string]$u['id'] -eq $slotTry) {
            $calls = [int]$u['calls']
            break
          }
        }
      }
    }
  }
  return @{
    connected = $connected
    slot      = $slot
    entries   = $entries
    drafts    = $drafts
    calls     = $calls
  }
}

function Get-YaOverview([string]$Lib) {
  $cfg = Read-YaSlots $Lib
  $usage = Read-YaUsage $Lib
  $links = Read-YaLinks $Lib
  $linkedIds = @{}
  foreach ($row in (Get-YaItems $links.linked)) { $linkedIds[[string]$row['id']] = $true }
  $slots = New-Object System.Collections.Generic.List[object]
  $sumE = 0
  $sumC = 0
  $sumT = 0
  $known = 0
  $hasReserved = $false
  $reservedEntries = 0
  $reservedDrafts = 0
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if (Test-YaCrossSlotWord ([string]$s.id)) {
      $hasReserved = $true
      $reservedDir = Get-YaSlotDir $Lib $s
      if (Test-Path -LiteralPath (Join-Path $reservedDir '索引.json')) {
        $reservedCounts = Get-YaCounts $reservedDir
        $reservedEntries = [int]$reservedCounts.entries
        $reservedDrafts = [int]$reservedCounts.drafts
      }
      continue
    }
    $dir = Get-YaSlotDir $Lib $s
    $entries = 0
    $drafts = 0
    if (Test-Path -LiteralPath (Join-Path $dir '索引.json')) {
      $counts = Get-YaCounts $dir
      $entries = [int]$counts.entries
      $drafts = [int]$counts.drafts
    }
    $call = 0
    $token = $null
    $note = ''
    foreach ($u in (Get-YaItems $usage.slots)) {
      if ([string]$u['id'] -eq [string]$s.id) {
        $call = [int]$u['calls']
        $token = Get-YaTokenValue $u
        $note = [string]$u['note']
        break
      }
    }
    $sumE += $entries
    $sumC += $call
    if ($null -ne $token) { $sumT += [int]$token; $known++ }
    [void]$slots.Add(@{
        id      = [string]$s.id
        title   = (Format-YaShown ([string]$s.title))
        linked  = [bool]$linkedIds.ContainsKey([string]$s.id)
        entries = $entries
        drafts  = $drafts
        calls   = $call
        token   = $token
        note    = $note
      })
  }
  return @{
    linked_count  = (Get-YaItems $links.linked).Count
    pending_count = (Get-YaItems $links.pending).Count
    failed_count  = (Get-YaItems $links.failed).Count
    cross_calls   = [int]$usage.cross_calls
    slots         = $slots
    sum_entries   = $sumE
    sum_calls     = ($sumC + [int]$usage.cross_calls)
    sum_token         = $sumT
    token_known       = $known
    slot_count        = $slots.Count
    reserved          = $hasReserved
    reserved_entries  = $reservedEntries
    reserved_drafts   = $reservedDrafts
  }
}

function Format-YaOverview([string]$Lib) {
  $ov = Get-YaOverview $Lib
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('linked: ' + $ov.linked_count)
  [void]$lines.Add('pending: ' + $ov.pending_count)
  [void]$lines.Add('failed: ' + $ov.failed_count)
  [void]$lines.Add('cross_calls: ' + $ov.cross_calls)
  foreach ($s in (Get-YaItems $ov.slots)) {
    $mark = 'no'
    if ($s.linked) { $mark = 'yes' }
    [void]$lines.Add('slot ' + (Format-YaShownId ([string]$s.id)) + ' title=' + $s.title + ' linked=' + $mark + ' entries=' + $s.entries + ' drafts=' + $s.drafts + ' calls=' + $s.calls + ' token=' + (Format-YaToken $s.token))
  }
  if ($ov.reserved) {
    [void]$lines.Add('reserved all entries=' + $ov.reserved_entries + ' drafts=' + $ov.reserved_drafts)
    [void]$lines.Add('note: all 是保留名，不能当槽。' + (Get-YaReservedClearHint))
  }
  $tokenText = '未统计'
  if ([int]$ov.token_known -gt 0) { $tokenText = [string]$ov.sum_token }
  [void]$lines.Add('sum slots=' + $ov.slot_count + ' entries=' + $ov.sum_entries + ' calls=' + $ov.sum_calls + ' token=' + $tokenText + ' token_known=' + $ov.token_known + '/' + $ov.slot_count)
  $side = Get-YaSoftwareSide $Lib
  $sideConn = 'no'
  if ($side.connected) { $sideConn = 'yes' }
  $sideSlot = ''
  if ($side.slot) { $sideSlot = ' slot=' + (Format-YaShownId ([string]$side.slot)) }
  [void]$lines.Add('side connected=' + $sideConn + $sideSlot + ' software_entries=' + $side.entries + ' software_drafts=' + $side.drafts + ' software_calls=' + $side.calls)
  [void]$lines.Add('note: 分槽存放，本命令一处总览。TOKEN 只合计已登记的槽；没登记显示未统计，不当成账单。')
  [void]$lines.Add('note: 软件侧只计已核对的连接：登记 state=ok，且这个 pid 的主窗口还在、能响应、看得见，槽号对得上本包里的软件槽。进程号读不了、槽号对不上、残留登记，都按 0。只是大小写不同则计入那个槽。各槽自己的行仍是台账。读不了的超大 TOKEN 显示未统计。')
  return ,$lines
}

function Get-YaSlotUsage([string]$Lib, [string]$SlotId) {
  $ov = Get-YaOverview $Lib
  if ($SlotId -eq 'all') {
    $token = '未统计'
    if ([int]$ov.token_known -gt 0) { $token = [string]$ov.sum_token }
    return @{ calls = $ov.sum_calls; token = $token }
  }
  foreach ($s in (Get-YaItems $ov.slots)) {
    if ([string]$s.id -eq $SlotId) {
      return @{ calls = [int]$s.calls; token = (Format-YaToken $s.token) }
    }
  }
  return @{ calls = 0; token = '未统计' }
}

function Assert-YaCoachNote([string]$Note) {
  $note = Repair-YaLine $Note
  if ($note.Length -lt 4) { throw '这一步要写至少 4 个字的记录，空话过不了闸。' }
  if ($note.Length -gt 500) { throw '这一步的记录最长 500 字。' }
  Assert-YaClean $note
  return $note
}

function Assert-YaNotAllCoach([string]$Lib, [string]$Id) {
  if (-not (Test-YaCrossSlotWord $Id)) { return }
  $links = Read-YaLinks $Lib
  $pending = New-Object System.Collections.Generic.List[object]
  $removed = $false
  foreach ($row in (Get-YaItems $links.pending)) {
    if (Test-YaCrossSlotWord ([string]$row['id'])) { $removed = $true }
    else { [void]$pending.Add($row) }
  }
  if ($removed) {
    $links.pending = $pending
    Write-YaLinks $Lib $links
  }
  throw 'all 只能用来跨槽检索，不能拿来做三步闸。请换一个软件 id。名为 all 的记录不会进入待过关。'
}

function Assert-YaNotGenericCoach([string]$Lib, [string]$Id) {
  if ($Id -ne 'generic') { return }
  $links = Read-YaLinks $Lib
  $pending = New-Object System.Collections.Generic.List[object]
  $removed = $false
  foreach ($row in (Get-YaItems $links.pending)) {
    if ([string]$row['id'] -eq 'generic') { $removed = $true }
    else { [void]$pending.Add($row) }
  }
  if ($removed) {
    $links.pending = $pending
    Write-YaLinks $Lib $links
  }
  throw 'generic 是底槽，不是待过关的软件。请换一个软件 id。底槽不会进入待过关。'
}

function Start-YaCoach([string]$Lib, [string]$Id, [string]$Title) {
  Assert-YaNotAllCoach $Lib $Id
  if (-not (Test-YaSlotId $Id)) { throw '软件 id 要用小写英文开头，只含小写字母、数字、下划线、连字符，最长 32。' }
  Assert-YaNotGenericCoach $Lib $Id
  $title = Repair-YaLine $Title
  if (-not $title) { throw 'coach_start 需要 title=你自己的软件名。不要点名厂家。' }
  Assert-YaClean $title
  $existed = $false
  try { Add-YaSlot $Lib $Id $title '三步闸进行中' $false }
  catch {
    if ($_.Exception.Message -notlike '槽已存在:*') { throw }
    $existed = $true
  }
  $links = Read-YaLinks $Lib
  $cleared = Clear-YaSameFailed $links $Id
  foreach ($row in (Get-YaItems $links.linked)) {
    if ([string]$row['id'] -eq $Id) {
      if ($cleared -gt 0) { Write-YaLinks $Lib $links }
      return @{ status = 'linked'; id = $Id; title = [string]$row['title']; kept = $existed; cleared = $cleared }
    }
  }
  foreach ($row in (Get-YaItems $links.pending)) {
    if ([string]$row['id'] -eq $Id) {
      if ($cleared -gt 0) { Write-YaLinks $Lib $links }
      return @{ status = 'pending'; id = $Id; title = [string]$row['title']; kept = $true; cleared = $cleared }
    }
  }
  $pending = [ordered]@{
    id    = $Id
    title = $title
    steps = (New-Object System.Collections.Generic.List[object])
  }
  [void]$links.pending.Add($pending)
  Write-YaLinks $Lib $links
  return @{ status = 'started'; id = $Id; title = $title; kept = $existed; cleared = $cleared }
}

function Find-YaPending($Links, [string]$Id) {
  foreach ($row in (Get-YaItems $Links.pending)) {
    if ([string]$row['id'] -eq $Id) { return $row }
  }
  return $null
}

function Find-YaStep($Pending, [int]$Step) {
  foreach ($s in (Get-YaItems $Pending['steps'])) {
    if ([int]$s['step'] -eq $Step) { return $s }
  }
  return $null
}

function Measure-YaCoachStep($Pending, [int]$Step) {
  $n = 0
  $one = $null
  foreach ($s in (Get-YaItems $Pending['steps'])) {
    $rawN = Get-YaTextProp $s 'step'
    if ($rawN -match '^\d+$' -and [int]$rawN -eq $Step) {
      if ($n -eq 0) { $one = $s }
      $n++
    }
  }
  return @{ n = $n; one = $one }
}

function Test-YaStamp([string]$Text) {
  return ($Text -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}$')
}

function Get-YaTaskPassTime($Task) {
  if ($null -eq $Task) { return '' }
  if (-not (Test-YaFlag $Task['complete'])) { return '' }
  $status = [string]$Task['status']
  if ($status -ne '自检通过' -and $status -ne '已验收') { return '' }
  $latest = ''
  foreach ($e in (Get-YaItems $Task['events'])) {
    if ([string]$e['name'] -ne '自检通过') { continue }
    $t = [string]$e['time']
    if (-not (Test-YaStamp $t)) { continue }
    if ($t -gt $latest) { $latest = $t }
  }
  return $latest
}

function Test-YaSlotTaskPassed([string]$Lib, [string]$SlotId, [string]$After) {
  $flow = Read-YaFlow $Lib
  $all = New-Object System.Collections.Generic.List[object]
  if ($flow.current) { [void]$all.Add($flow.current) }
  foreach ($h in (Get-YaItems $flow.history)) { [void]$all.Add($h) }
  foreach ($task in $all) {
    if ([string]$task['slot'] -ne $SlotId) { continue }
    $passTime = Get-YaTaskPassTime $task
    if (-not $passTime) { continue }
    if ($After -and ($passTime -le $After)) { continue }
    return $true
  }
  return $false
}

function Assert-YaRecordedStep($StepObj, [string]$TooShort, [string]$TooLong, [string]$BadTime) {
  $note = Repair-YaLine ([string]$StepObj['note'])
  if ($note.Length -lt 4) { throw $TooShort }
  if ($note.Length -gt 500) { throw $TooLong }
  Assert-YaClean $note
  $time = Repair-YaLine ([string]$StepObj['time'])
  if (-not (Test-YaStamp $time)) { throw $BadTime }
  return $time
}

function Assert-YaCoachChain($Pending, [int]$Step) {
  $time1 = ''
  if ($Step -ge 2) {
    $m1 = Measure-YaCoachStep $Pending 1
    if ([int]$m1['n'] -gt 1) { throw '第 1 步有多条记录，不能走后面的步骤。请把第 1 步再记一次。' }
    if ([int]$m1['n'] -lt 1) { throw '第 1 步还没有记录，不能走后面的步骤。' }
    $time1 = Assert-YaRecordedStep $m1['one'] '第 1 步的记录太短，不能走后面的步骤。请把第 1 步再记一次。' '第 1 步的记录超过 500 字，不能走后面的步骤。请把第 1 步再记一次。' '第 1 步没有合格的时间，不能走后面的步骤。请把第 1 步再记一次。'
  }
  if ($Step -lt 3) { return }
  $m2 = Measure-YaCoachStep $Pending 2
  if ([int]$m2['n'] -gt 1) { throw '第 2 步有多条记录，不能记过关。请把第 2 步再记一次。' }
  if ([int]$m2['n'] -lt 1) { throw '第 2 步还没有记录，不能记过关。' }
  $time2 = Assert-YaRecordedStep $m2['one'] '第 2 步的记录太短，不能记过关。请把第 2 步再记一次。' '第 2 步的记录超过 500 字，不能记过关。请把第 2 步再记一次。' '第 2 步没有合格的时间，不能记过关。请把第 2 步再记一次。'
  if ($time1 -gt $time2) { throw '第 1 步的时间晚于第 2 步，顺序不对。请把第 1 步再记一次，再按顺序记第 2 步。' }
}

function Assert-YaFailPrior($Pending, [int]$Step) {
  if ($Step -eq 1) {
    $seen1 = Measure-YaCoachStep $Pending 1
    if ([int]$seen1['n'] -gt 1) { throw '第 1 步有多条记录，不能记失败。请把第 1 步再记一次。' }
  }
  $time1 = ''
  if ($Step -ge 2) {
    $m1 = Measure-YaCoachStep $Pending 1
    if ([int]$m1['n'] -gt 1) { throw '第 1 步有多条记录，不能记后面的失败。请把第 1 步再记一次。' }
    if ([int]$m1['n'] -lt 1) { throw '第 1 步还没有记录，不能记后面的失败。' }
    $time1 = Assert-YaRecordedStep $m1['one'] '第 1 步的记录太短，不能记后面的失败。请把第 1 步再记一次。' '第 1 步的记录超过 500 字，不能记后面的失败。请把第 1 步再记一次。' '第 1 步没有合格的时间，不能记后面的失败。请把第 1 步再记一次。'
  }
  $m2 = $null
  $check2 = $false
  if ($Step -eq 2) {
    $seen2 = Measure-YaCoachStep $Pending 2
    if ([int]$seen2['n'] -gt 1) { throw '第 2 步有多条记录，不能记失败。请把第 2 步再记一次。' }
    if ([int]$seen2['n'] -eq 1) { $m2 = $seen2; $check2 = $true }
  }
  if ($Step -eq 3) {
    $m2 = Measure-YaCoachStep $Pending 2
    if ([int]$m2['n'] -gt 1) { throw '第 2 步有多条记录，不能把失败记在第 3 步。请把第 2 步再记一次。' }
    if ([int]$m2['n'] -lt 1) { throw '第 2 步还没有记录，不能把失败记在第 3 步。' }
    $check2 = $true
  }
  if (-not $check2) { return }
  $tooShort = '第 2 步的记录太短，不能把失败记在第 3 步。请把第 2 步再记一次。'
  $tooLong = '第 2 步的记录超过 500 字，不能把失败记在第 3 步。请把第 2 步再记一次。'
  $badTime = '第 2 步没有合格的时间，不能把失败记在第 3 步。请把第 2 步再记一次。'
  if ($Step -eq 2) {
    $tooShort = '第 2 步的记录太短，不能记后面的失败。请把第 2 步再记一次。'
    $tooLong = '第 2 步的记录超过 500 字，不能记后面的失败。请把第 2 步再记一次。'
    $badTime = '第 2 步没有合格的时间，不能记后面的失败。请把第 2 步再记一次。'
  }
  $time2 = Assert-YaRecordedStep $m2['one'] $tooShort $tooLong $badTime
  if ($time1 -gt $time2) { throw '第 1 步的时间晚于第 2 步，顺序不对。请把第 1 步再记一次，再按顺序记第 2 步。' }
}

function Clear-YaSameFailed($Links, [string]$Id) {
  $keep = New-Object System.Collections.Generic.List[object]
  $n = 0
  foreach ($row in (Get-YaItems $Links.failed)) {
    if ([string]$row['id'] -eq $Id) { $n++ }
    else { [void]$keep.Add($row) }
  }
  if ($n -gt 0) { $Links.failed = $keep }
  return $n
}

function Format-YaShown([string]$Text) {
  $t = Repair-YaLine $Text
  if (Test-YaForbidden $t) { return '没有列出来' }
  return $t
}

function Format-YaShownId([string]$Id) {
  return (Format-YaShown $Id)
}

function Add-YaCoachStep([string]$Lib, [string]$Id, [int]$Step, [string]$Note) {
  if ($Step -lt 1 -or $Step -gt 3) { throw 'step 只能是 1、2 或 3。' }
  Assert-YaNotAllCoach $Lib $Id
  Assert-YaNotGenericCoach $Lib $Id
  $note = Assert-YaCoachNote $Note
  $links = Read-YaLinks $Lib
  foreach ($row in (Get-YaItems $links.linked)) {
    if ([string]$row['id'] -eq $Id) { throw '这个软件已经在已挂清单里。' }
  }
  $pending = Find-YaPending $links $Id
  if (-not $pending) { throw '还没有这个软件的三步闸。请先 coach_start。' }
  Assert-YaCoachChain $pending $Step
  if ($Step -eq 3) {
    $step2 = Find-YaStep $pending 2
    $after = Repair-YaLine ([string]$step2['time'])
    if (-not (Test-YaSlotTaskPassed $Lib $Id $after)) {
      throw '小任务自检还没过，或通过时间不晚于第 2 步。请在第 2 步之后 task_open，逐项 step_check，再 step_finish。'
    }
  }
  $steps = New-Object System.Collections.Generic.List[object]
  $replaced = $false
  $dropped = $false
  $merged = $false
  foreach ($s in (Get-YaItems $pending['steps'])) {
    $n = 0
    $rawN = Get-YaTextProp $s 'step'
    if ($rawN -match '^\d+$') { $n = [int]$rawN }
    if ($n -lt 1 -or $n -gt 3) { continue }
    if ($n -gt $Step) { $dropped = $true; continue }
    if ($n -eq $Step) {
      if (-not $replaced) {
        [void]$steps.Add([ordered]@{ step = $Step; note = $note; time = (Get-YaNow) })
        $replaced = $true
      } else {
        $merged = $true
      }
    } else {
      [void]$steps.Add($s)
    }
  }
  if (-not $replaced) {
    [void]$steps.Add([ordered]@{ step = $Step; note = $note; time = (Get-YaNow) })
  }
  $pending['steps'] = $steps
  $cleared = 0
  if ($Step -eq 3) { $cleared = Clear-YaSameFailed $links $Id }
  if ($Step -ne 3) {
    Write-YaLinks $Lib $links
    return @{ status = 'recorded'; id = $Id; step = $Step; linked = $false; dropped = $dropped; merged = $merged; cleared = $cleared }
  }
  $keep = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $links.pending)) {
    if ([string]$row['id'] -ne $Id) { [void]$keep.Add($row) }
  }
  $links.pending = $keep
  [void]$links.linked.Add([ordered]@{
      id    = $Id
      title = [string]$pending['title']
      time  = (Get-YaNow)
      task  = $note
    })
  Write-YaLinks $Lib $links
  return @{ status = 'linked'; id = $Id; step = 3; linked = $true; dropped = $false; merged = $false; cleared = $cleared }
}

function Fail-YaCoach([string]$Lib, [string]$Id, [int]$Step, [string]$Note) {
  if ($Step -lt 1 -or $Step -gt 3) { throw 'step 只能是 1、2 或 3。' }
  Assert-YaNotAllCoach $Lib $Id
  Assert-YaNotGenericCoach $Lib $Id
  $note = Assert-YaCoachNote $Note
  $links = Read-YaLinks $Lib
  $pending = Find-YaPending $links $Id
  if (-not $pending) { throw '没有进行中的三步闸，不能记失败。' }
  Assert-YaFailPrior $pending $Step
  $keep = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $links.pending)) {
    if ([string]$row['id'] -ne $Id) { [void]$keep.Add($row) }
  }
  $links.pending = $keep
  [void]$links.failed.Add([ordered]@{
      id    = $Id
      title = [string]$pending['title']
      step  = $Step
      note  = $note
      time  = (Get-YaNow)
    })
  Write-YaLinks $Lib $links
  return @{ status = 'failed'; id = $Id; step = $Step }
}

function Remove-YaFlowSlot([string]$Lib, [string]$Id) {
  $links = Read-YaLinks $Lib
  $linked = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $links.linked)) {
    if ([string]$row['id'] -ne $Id) { [void]$linked.Add($row) }
  }
  $pending = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $links.pending)) {
    if ([string]$row['id'] -ne $Id) { [void]$pending.Add($row) }
  }
  $failed = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $links.failed)) {
    if ([string]$row['id'] -ne $Id) { [void]$failed.Add($row) }
  }
  $links.linked = $linked
  $links.pending = $pending
  $links.failed = $failed
  Write-YaLinks $Lib $links
  $usage = Read-YaUsage $Lib
  $slots = New-Object System.Collections.Generic.List[object]
  foreach ($row in (Get-YaItems $usage.slots)) {
    if ([string]$row['id'] -ne $Id) { [void]$slots.Add($row) }
  }
  $usage.slots = $slots
  Write-YaUsage $Lib $usage
}

function Test-YaTaskTagHit([string]$Need, [string]$Tag, [string]$Query) {
  $need = (Repair-YaLine $Need).ToLowerInvariant()
  if (-not $need) { return $true }
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($one in (Split-YaCommaList $Tag)) {
    $t = Repair-YaLine ([string]$one)
    if ($t) { [void]$parts.Add($t.ToLowerInvariant()) }
  }
  $queryText = Repair-YaLine $Query
  if ($queryText) {
    foreach ($one in @($queryText.Split([char[]]@(' ', '　', "`t", ',', '，'), [StringSplitOptions]::RemoveEmptyEntries))) {
      $t = Repair-YaLine ([string]$one)
      if ($t) { [void]$parts.Add($t.ToLowerInvariant()) }
    }
  }
  foreach ($p in $parts) {
    if ($p -eq $need) { return $true }
  }
  return $false
}

function Mark-YaRecalled([string]$Lib, [string]$SlotId, [string]$Tag, [string]$Query, [int]$Hits) {
  Write-YaGate $Lib @{
    slot     = $SlotId
    tag      = (Repair-YaLine $Tag)
    query    = (Repair-YaLine $Query)
    hits     = $Hits
    time     = (Get-YaNow)
    consumed = $false
  }
  Add-YaCall $Lib $SlotId
  $flow = Read-YaFlow $Lib
  if ($null -eq $flow.current) { return }
  $cur = $flow.current
  if ([string]$cur['status'] -ne '进行中') { return }
  $match = ($SlotId -eq [string]$cur['slot'])
  $need = [string]$cur['tag']
  if ($match -and $need) {
    if (-not (Test-YaTaskTagHit $need $Tag $Query)) { $match = $false }
  }
  if (-not $match) {
    $changed = $false
    if (Test-YaFlag $cur['retrieved']) {
      $cur['retrieved'] = $false
      $changed = $true
    }
    foreach ($c in (Get-YaItems $cur['checks'])) {
      if ([string]$c['id'] -eq 'search' -and (Test-YaFlag $c['pass'])) {
        $c['pass'] = $false
        $changed = $true
      }
    }
    if ($changed) {
      Add-YaEvent $cur '检索未对上' ('slot=' + $SlotId)
      Write-YaFlowState $Lib $flow
    }
    return
  }
  $cur['retrieved'] = $true
  Add-YaEvent $cur '检索' ('hits=' + $Hits)
  Write-YaFlowState $Lib $flow
}

function Assert-YaDraftTaskTag([string]$Lib, [string]$SlotId, [string]$Tags) {
  $flow = Read-YaFlow $Lib
  if ($null -eq $flow.current) { return }
  if ([string]$flow.current['slot'] -ne $SlotId) { return }
  $need = Repair-YaLine ([string]$flow.current['tag'])
  if (-not $need) { return }
  foreach ($one in (Split-YaCommaList $Tags)) {
    $t = Repair-YaLine $one
    if ($t -and ($t.ToLowerInvariant() -eq $need.ToLowerInvariant())) { return }
  }
  throw ('草稿的任务标签里要有当前任务的标签「' + (Format-YaShown $need) + '」。tag= 和 k= 可以不同，但这个标签要写在 tag= 里。')
}

function Assert-YaCanGenerate([string]$Lib, [string]$SlotId) {
  $gate = Read-YaGate $Lib
  if ($gate.consumed) { throw '先检索再生成。请先对这个槽执行 exp_search 或 exp_recall。' }
  $gateQuery = Repair-YaLine ([string]$gate.query)
  $gateTag = Repair-YaLine ([string]$gate.tag)
  if (-not $gateQuery -and -not $gateTag) { throw '先检索再生成。请先对这个槽执行 exp_search 或 exp_recall，并写上 q= 或 tag=。' }
  if ($gate.slot -ne $SlotId) {
    $msg = '检索的槽和要写入的槽不一致。请先按目标槽检索。'
    if ($gate.slot -eq 'all') { $msg += 'slot=all 只能跨槽查看，不能拿来写草稿。' }
    throw $msg
  }
  $flow = Read-YaFlow $Lib
  if ($null -ne $flow.current) {
    if (-not (Test-YaFlag $flow.current['retrieved'])) { throw '当前任务还没有对上槽和标签的检索。请按任务的槽检索；slot=all 只能跨槽查看，不能代替。' }
    if ([string]$flow.current['slot'] -ne $SlotId) { throw '当前任务的槽和要写入的槽不一致。' }
  }
}

function Consume-YaRecall([string]$Lib) {
  $gate = Read-YaGate $Lib
  $gate.consumed = $true
  Write-YaGate $Lib $gate
}

function Open-YaTask([string]$Lib, [string]$SlotId, [string]$Tag, [string]$Title) {
  $resolved = Resolve-YaSlot $Lib $SlotId
  $title = Repair-YaLine $Title
  if (-not $title) { throw 'task_open 需要 title=这一步要做什么。' }
  if ($title.Length -gt 80) { throw '任务标题最长 80 字。' }
  Assert-YaClean $title
  $tag = Repair-YaLine $Tag
  if ($tag.Length -gt 40) { throw '任务标签最长 40 字。' }
  if ($tag -match ',|，') { throw '一个任务只写一个标签。' }
  Assert-YaClean $tag
  $flow = Read-YaFlow $Lib
  if ($null -ne $flow.current) {
    $status = [string]$flow.current['status']
    if ($status -eq '进行中' -or $status -eq '自检通过') {
      throw '已有没交代的任务。请先 step_accept、step_reject 或 step_hand。'
    }
  }
  $task = [ordered]@{
    id        = ('T' + (Get-Date -Format 'yyyyMMddHHmmss'))
    title     = $title
    slot      = $resolved.id
    tag       = $tag
    retrieved = $false
    status    = '进行中'
    complete  = $false
    checks    = (New-YaChecks)
    events    = (New-Object System.Collections.Generic.List[object])
  }
  Add-YaEvent $task '打开' $title
  $flow.current = $task
  Write-YaFlowState $Lib $flow
  return $task
}

function Find-YaCheck($Task, [string]$Item) {
  $key = (Repair-YaLine $Item).ToLowerInvariant()
  foreach ($c in (Get-YaItems $Task['checks'])) {
    if ([string]$c['id'] -eq $key -or [string]$c['title'] -eq (Repair-YaLine $Item)) { return $c }
  }
  return $null
}

function Set-YaCheck([string]$Lib, [string]$Item, [string]$Pass, [string]$Note) {
  $flow = Read-YaFlow $Lib
  if ($null -eq $flow.current) { throw '没有进行中的任务。请先 task_open。' }
  if ([string]$flow.current['status'] -ne '进行中') { throw '这个任务不在进行中，不能再改自检。要重做就开一个新任务。' }
  $row = Find-YaCheck $flow.current $Item
  if (-not $row) { throw '没有这项自检。可用：search、compare、draft、claim、inspect。' }
  if ($Pass -ne '0' -and $Pass -ne '1') { throw 'pass 只能是 0 或 1。' }
  $note = Repair-YaLine $Note
  if ($note.Length -gt 200) { throw '自检备注最长 200 字。' }
  Assert-YaClean $note
  $ok = ($Pass -eq '1')
  if ($ok -and [string]$row['id'] -eq 'search' -and -not (Test-YaFlag $flow.current['retrieved'])) {
    throw '还没有检索记录，不能把「先检索再生成」勾成通过。'
  }
  $row['pass'] = $ok
  $row['note'] = $note
  $flow.current['complete'] = $false
  Add-YaEvent $flow.current ('自检 ' + $row['id']) ('pass=' + $Pass)
  Write-YaFlowState $Lib $flow
  return @{ id = [string]$row['id']; title = [string]$row['title']; pass = $ok }
}

function Get-YaCheckScore($Task) {
  $need = @('search', 'compare', 'draft', 'claim', 'inspect')
  $passN = 0
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($id in $need) {
    $row = $null
    foreach ($c in (Get-YaItems $Task['checks'])) {
      if ([string]$c['id'] -eq $id) { $row = $c; break }
    }
    $ok = ($null -ne $row -and (Test-YaFlag $row['pass']))
    if ($id -eq 'search' -and -not (Test-YaFlag $Task['retrieved'])) { $ok = $false }
    if ($ok) { $passN++ }
    elseif ($null -ne $row) { [void]$missing.Add([string]$row['title']) }
    else { [void]$missing.Add($id) }
  }
  return @{ pass = $passN; missing = $missing }
}

function Finish-YaTask([string]$Lib) {
  $flow = Read-YaFlow $Lib
  if ($null -eq $flow.current) { throw '没有进行中的任务。' }
  $task = $flow.current
  $status = [string]$task['status']
  if ($status -eq '自检通过') {
    throw '这个任务已经自检通过。通过时间不会更新。要在新的第 2 步之后重做，请先交代这一条，再 task_open。'
  }
  if ($status -ne '进行中') {
    throw '这个任务不在进行中，不能再报完成。请先交代这一条，再 task_open。'
  }
  $score = Get-YaCheckScore $task
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('task: ' + $task['id'])
  [void]$lines.Add('checks: ' + $score.pass + '/5')
  if ([int]$score.pass -lt 5) {
    [void]$lines.Add('missing: ' + ($score.missing -join ','))
    [void]$lines.Add('status: ' + $task['status'])
    [void]$lines.Add('complete: no')
    return @{ ok = $false; lines = $lines; error = '自检未过，禁止报完成。' }
  }
  $task['status'] = '自检通过'
  $task['complete'] = $true
  Add-YaEvent $task '自检通过' '5/5'
  Write-YaFlowState $Lib $flow
  [void]$lines.Add('status: 自检通过')
  [void]$lines.Add('complete: yes')
  [void]$lines.Add('note: 自检已过。请把验收、打回、举手交给人。打回或举手之后不能再报完成。')
  return @{ ok = $true; lines = $lines; error = '' }
}

function Archive-YaTask($State) {
  if ($null -eq $State.current) { return }
  [void]$State.history.Add($State.current)
  while ($State.history.Count -gt 40) { $State.history.RemoveAt(0) }
  $State.current = $null
}

function Close-YaTask([string]$Lib, [string]$Kind, [string]$Note) {
  $flow = Read-YaFlow $Lib
  if ($null -eq $flow.current) { throw '没有进行中的任务。' }
  $task = $flow.current
  $status = [string]$task['status']
  $note = Repair-YaLine $Note
  if ($Kind -eq 'accept') {
    if ($status -ne '自检通过') { throw '自检未过，不能验收。' }
    if ($note.Length -gt 300) { throw '验收备注最长 300 字。' }
    if ($note) { Assert-YaClean $note }
    $task['status'] = '已验收'
    $task['complete'] = $true
    Add-YaEvent $task '验收' $note
  } elseif ($Kind -eq 'reject' -or $Kind -eq 'hand') {
    if ($note.Length -lt 2) { throw '打回和举手都要写原因。' }
    if ($note.Length -gt 300) { throw '原因最长 300 字。' }
    Assert-YaClean $note
    if ($Kind -eq 'reject') {
      $task['status'] = '已打回'
      Add-YaEvent $task '打回' $note
    } else {
      $task['status'] = '已举手'
      Add-YaEvent $task '举手' $note
    }
    $task['complete'] = $false
  } else {
    throw '未知的交代方式。'
  }
  $done = [string]$task['status']
  $complete = Test-YaFlag $task['complete']
  $id = [string]$task['id']
  Archive-YaTask $flow
  Write-YaFlowState $Lib $flow
  $flag = 'no'
  if ($complete) { $flag = 'yes' }
  return @{ id = $id; status = $done; complete = $flag }
}

function Format-YaTask([string]$Lib) {
  $flow = Read-YaFlow $Lib
  $lines = New-Object System.Collections.Generic.List[string]
  if ($null -eq $flow.current) {
    [void]$lines.Add('task: none')
    [void]$lines.Add('complete: no')
    return ,$lines
  }
  $task = $flow.current
  [void]$lines.Add('task: ' + $task['id'])
  [void]$lines.Add('title: ' + (Format-YaShown ([string]$task['title'])))
  [void]$lines.Add('slot: ' + (Format-YaShownId ([string]$task['slot'])))
  [void]$lines.Add('tag: ' + (Format-YaShown ([string]$task['tag'])))
  [void]$lines.Add('status: ' + $task['status'])
  $got = 'no'
  if (Test-YaFlag $task['retrieved']) { $got = 'yes' }
  [void]$lines.Add('retrieved: ' + $got)
  foreach ($c in (Get-YaItems $task['checks'])) {
    $mark = '0'
    if (Test-YaFlag $c['pass']) { $mark = '1' }
    [void]$lines.Add('check ' + $c['id'] + ' pass=' + $mark + ' title=' + (Format-YaShown ([string]$c['title'])))
  }
  $flag = 'no'
  if (Test-YaFlag $task['complete']) { $flag = 'yes' }
  [void]$lines.Add('complete: ' + $flag)
  return ,$lines
}

function Format-YaLinks([string]$Lib) {
  $links = Read-YaLinks $Lib
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('linked: ' + (Get-YaItems $links.linked).Count)
  foreach ($row in (Get-YaItems $links.linked)) {
    [void]$lines.Add('link ' + (Format-YaShownId ([string]$row['id'])) + ' title=' + (Format-YaShown ([string]$row['title'])) + ' time=' + $row['time'])
  }
  [void]$lines.Add('pending: ' + (Get-YaItems $links.pending).Count)
  foreach ($row in (Get-YaItems $links.pending)) {
    $have = @()
    foreach ($s in (Get-YaItems $row['steps'])) { $have += [string]$s['step'] }
    $text = 'none'
    if ($have.Count -gt 0) { $text = ($have -join ',') }
    [void]$lines.Add('pending ' + (Format-YaShownId ([string]$row['id'])) + ' title=' + (Format-YaShown ([string]$row['title'])) + ' steps=' + $text)
  }
  [void]$lines.Add('failed: ' + (Get-YaItems $links.failed).Count)
  foreach ($row in (Get-YaItems $links.failed)) {
    [void]$lines.Add('failed ' + (Format-YaShownId ([string]$row['id'])) + ' title=' + (Format-YaShown ([string]$row['title'])) + ' step=' + $row['step'] + ' note=' + (Format-YaShown ([string]$row['note'])))
  }
  [void]$lines.Add('note: 已挂只收三步闸过关。没有记录就是还没挂上。')
  return ,$lines
}
