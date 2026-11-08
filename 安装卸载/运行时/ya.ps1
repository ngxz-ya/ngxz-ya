# YA 命令。不启动机械软件，也不把「开了槽」说成已经接通。
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\安装卸载\运行时\ya.ps1" help
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'ya_slots.ps1')
. (Join-Path $PSScriptRoot 'ya_flow.ps1')

function Read-YaArgs([string[]]$Items) {
  $map = @{}
  foreach ($kv in @($Items)) {
    if (-not $kv) { continue }
    $i = $kv.IndexOf('=')
    if ($i -lt 1) { throw ('参数要写成 名字=值 ：' + (Format-YaShown $kv)) }
    $map[$kv.Substring(0, $i)] = $kv.Substring($i + 1)
  }
  return $map
}

function Get-YaArg($Map, [string]$Name) {
  if ($Map.ContainsKey($Name)) { return [string]$Map[$Name] }
  return ''
}

function Write-YaLines($Lines) {
  foreach ($line in (Get-YaItems $Lines)) {
    if ($null -ne $line -and [string]$line -ne '') { Write-Output ([string]$line) }
  }
}

function Write-YaHelp {
  @(
    'status              装卸、当前槽、已挂数量',
    'self_check          核对包、经验槽和教练文件。不代表软件已接通',
    'overview            一处看全部分槽：已挂、经验条数、调用、TOKEN。side 行未核对、进程号读不了或槽号对不上时按 0',
    'panel snapshot=1    打开总览面板。snapshot=1 只打印面板上的数',
    'slot_list | slot_add id= title= | slot_use id= | slot_remove id=',
    'skill_search q= max=       查少量通用候选方法，不执行、不提升可信状态',
    'skill_get id=              读取一张通用方法全文',
    'slot_remove id=all to=具体槽   误建的 all 有条目时先迁走。不要了用 drop=1',
    'exp_search q= slot= tag= [task=]    先检索，要写 q= 或 tag=。tag是经验过滤，task只关联当前任务。全文用 exp_get',
    'exp_recall q= slot= tag= [task=]    同检索。有命中先按 get 行读，没有命中才可以生成',
    'exp_get id= slot=           读一条。全文前有 tags:。slot=all 不能调取',
    'exp_done c= t= k= tag= m= [record=本次方法JSON]   先检索再写草稿，保留结构化方法。slot=all不能写',
    'exp_save id= verified=1     没有 verified=1 不进索引。slot=all 不能入库',
    'exp_drop id= slot=          只丢掉还没入库的一份草稿。不删槽，不删已入库条目',
    'exp_hold id= slot=          已入库又含禁止写入的词：清出索引或按全文改回。不打出正文',
    'coach_start id= title=      打开三步闸。底槽 generic 和 id=all 都不能当目标',
    'coach_step id= step=1|2|3 note=',
    'coach_fail id= step= note=  失败留记录，不进已挂',
    'link_list',
    'task_open slot= tag= title=  slot=all 不能开任务',
    'step_check item=search|compare|draft|claim|inspect pass=0|1',
    'step_finish             五项都过才 complete: yes。已经通过的不再改时间',
    'step_accept | step_reject note= | step_hand note=',
    'task_status',
    'usage_set slot= token= note=   token 留空表示未登记。slot=all 不能登记'
  ) | ForEach-Object { Write-Output $_ }
}

function Format-YaPreview([string]$Text) {
  $t = Repair-YaLine $Text
  if (-not $t) { return 'none' }
  if ($t.Length -gt 80) { return ($t.Substring(0, 80) + '…') }
  return $t
}

function Format-YaStoredTags([string]$File) {
  try { $obj = Read-YaJsonFile $File }
  catch { return 'none' }
  $tags = Get-YaItems (ConvertTo-YaKeywordList $obj.tags)
  if ($tags.Count -eq 0) { return 'none' }
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($one in $tags) {
    $t = [string]$one
    if ($t) { [void]$parts.Add($t) }
  }
  if ($parts.Count -eq 0) { return 'none' }
  return ($parts -join ',')
}

function Test-YaReservedActive([string]$Lib, [string]$SlotArg) {
  if (Test-YaCrossSlotWord $SlotArg) { return $true }
  if (Repair-YaLine $SlotArg) { return $false }
  $cfg = Read-YaSlots $Lib
  return (Test-YaCrossSlotWord (Get-YaTextProp $cfg 'active'))
}

function Format-YaReservedHold() {
  return ('它误存在保留名 all 里，不能当槽读写。' + (Get-YaReservedClearHint))
}

function Get-YaPlaceSplit([string]$Lib, [string]$Id) {
  $real = New-Object System.Collections.Generic.List[object]
  $reserved = $false
  foreach ($p in (Get-YaItems (Find-YaEntryPlaces $Lib $Id))) {
    if (Test-YaCrossSlotWord ([string]$p.id)) { $reserved = $true }
    else { [void]$real.Add($p) }
  }
  return @{ reserved = $reserved; real = $real }
}

function Join-YaShownIds($Items) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($one in (Get-YaItems $Items)) { [void]$out.Add((Format-YaShownId ([string]$one))) }
  return ($out -join '，')
}

function Format-YaPlaceName($Place) {
  $name = Format-YaShownId ([string]$Place.id)
  $hasFormal = [bool]$Place.formal
  $hasDraft = [bool]$Place.draft
  if ($hasDraft -and -not $hasFormal) { return ($name + '（草稿）') }
  if ($hasDraft -and $hasFormal) { return ($name + '（索引和草稿）') }
  return $name
}

function Format-YaAllGet([string]$Lib, [string]$Id) {
  $head = 'slot=all 只能用来跨槽检索，不能拿来调取。'
  if (-not (Test-YaEntryId $Id)) {
    return ($head + '请写 exp_get id=条目号 slot=具体槽。具体槽用 slot_list 看，不要把 all 当成槽。')
  }
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($places.Count -eq 0) {
    if ($hold) { return ($head + $hold) }
    return ($head + '请先 exp_search slot=all 或 exp_recall slot=all，再按命中行的 get: 去读。get: 里的 slot 是具体槽，不是 all。')
  }
  if ($places.Count -eq 1) {
    $slot = Format-YaShownId ([string]$places[0].id)
    return ($head + '它在槽 ' + (Format-YaPlaceName $places[0]) + '。请用 exp_get id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $hold)
  }
  $bits = New-Object System.Collections.Generic.List[string]
  foreach ($p in $places) { [void]$bits.Add((Format-YaPlaceName $p)) }
  return ($head + '它在这些槽里: ' + ($bits -join '，') + '。请带上具体槽再调取，不要写 slot=all。' + $hold)
}

function Format-YaAllDone([string]$Lib) {
  $slotHint = '具体槽'
  $flow = Read-YaFlow $Lib
  if ($null -ne $flow.current) {
    $sid = Repair-YaLine ([string]$flow.current['slot'])
    if ($sid -and -not (Test-YaCrossSlotWord $sid)) { $slotHint = Format-YaShownId $sid }
  }
  return ('slot=all 只能用来跨槽检索，不能拿来写草稿。请先按目标槽检索，再写 exp_done c=招式 t=一句话 k=关键词 tag=标签 slot=' + $slotHint + '。不要把 all 当成槽。')
}

function Format-YaAllTask([string]$Tag, [string]$Title) {
  $tag = Repair-YaLine $Tag
  $title = Repair-YaLine $Title
  if (-not $tag) { $tag = '标签' }
  if (-not $title) { $title = '要做什么' }
  return ('slot=all 只能用来跨槽检索，不能拿来开任务。请写 task_open slot=具体槽 tag=' + $tag + ' title=' + $title + '。具体槽用 slot_list 看，不要把 all 当成槽。')
}

function Format-YaMissingGet([string]$Lib, [string]$SlotId, [string]$Id) {
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $bits = New-Object System.Collections.Generic.List[string]
  foreach ($p in $places) { [void]$bits.Add((Format-YaPlaceName $p)) }
  $head = '这个槽里没有: ' + (Format-YaShownId $Id) + '。查看的是槽 ' + (Format-YaShownId $SlotId) + '。'
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($bits.Count -eq 0) {
    if ($hold) { return ($head + $hold) }
    return ($head + '其他槽里也没有。可用 slot_list 看有哪些槽。')
  }
  if ($bits.Count -eq 1) {
    $slot = Format-YaShownId ([string]$places[0].id)
    return ($head + '它在槽 ' + $bits[0] + '。请用 exp_get id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $hold)
  }
  return ($head + '它在这些槽里: ' + ($bits -join '，') + '。请带上 slot= 再调取。' + $hold)
}

function Format-YaAllSave([string]$Lib, [string]$Id) {
  $head = 'slot=all 只能用来跨槽检索，不能拿来入库。'
  if (-not (Test-YaEntryId $Id)) {
    return ($head + '请写 exp_save id=草稿号 slot=具体槽。没有 verified=1 不会进索引。不要把 all 当成槽。')
  }
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $draftSlots = New-Object System.Collections.Generic.List[string]
  $indexSlots = New-Object System.Collections.Generic.List[string]
  foreach ($p in $places) {
    $sid = [string]$p.id
    if ([bool]$p.draft) { [void]$draftSlots.Add($sid) }
    if ([bool]$p.formal) { [void]$indexSlots.Add($sid) }
  }
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($draftSlots.Count -eq 0 -and $indexSlots.Count -eq 0) {
    if ($hold) { return ($head + $hold) }
    return ($head + '请写 exp_save id=草稿号 slot=具体槽。具体槽用 slot_list 看，不要把 all 当成槽。')
  }
  if ($draftSlots.Count -eq 1) {
    $slot = Format-YaShownId ([string]$draftSlots[0])
    return ($head + '它在槽 ' + $slot + ' 的草稿里。请用 exp_save id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $hold)
  }
  if ($draftSlots.Count -gt 1) {
    return ($head + '草稿在这些槽里: ' + (Join-YaShownIds $draftSlots) + '。请带上具体槽，不要写 slot=all。' + $hold)
  }
  return ($head + '它已经在槽 ' + (Join-YaShownIds $indexSlots) + ' 的索引里。' + $hold)
}

function Format-YaAllDrop([string]$Lib, [string]$Id) {
  $head = 'slot=all 只能用来跨槽检索，不能拿来丢掉草稿。'
  $tail = '已入库的条目不会被清掉。drop=1 只用来清掉误建的 all。不要把 all 当成槽。'
  if (-not (Test-YaEntryId $Id)) {
    return ($head + '请写 exp_drop id=草稿号 slot=具体槽。' + $tail)
  }
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $draftSlots = New-Object System.Collections.Generic.List[string]
  $indexSlots = New-Object System.Collections.Generic.List[string]
  foreach ($p in $places) {
    $sid = [string]$p.id
    if ([bool]$p.draft) { [void]$draftSlots.Add($sid) }
    if ([bool]$p.formal) { [void]$indexSlots.Add($sid) }
  }
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($draftSlots.Count -eq 1) {
    $slot = Format-YaShownId ([string]$draftSlots[0])
    return ($head + '它在槽 ' + $slot + ' 的草稿里。请用 exp_drop id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $tail + $hold)
  }
  if ($draftSlots.Count -gt 1) {
    return ($head + '草稿在这些槽里: ' + (Join-YaShownIds $draftSlots) + '。请带上具体槽，不要写 slot=all。' + $tail + $hold)
  }
  if ($indexSlots.Count -gt 0) {
    return ($head + '它已经在槽 ' + (Join-YaShownIds $indexSlots) + ' 的索引里。exp_drop 不删已入库的条目。' + $hold)
  }
  if ($hold) { return ($head + $hold) }
  return ($head + '请写 exp_drop id=草稿号 slot=具体槽。' + $tail)
}

function Format-YaAllHold([string]$Lib, [string]$Id) {
  $head = 'slot=all 只能用来跨槽检索，不能拿来清出条目。'
  $tail = '这条只处理已经入库、而且含禁止写入的词的条目。草稿仍用 exp_get 调取。干净的已入库条目不删。'
  if (-not (Test-YaEntryId $Id)) {
    return ($head + '请写 exp_hold id=条目号 slot=具体槽。' + $tail)
  }
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $slots = New-Object System.Collections.Generic.List[string]
  foreach ($p in $places) {
    $sid = [string]$p.id
    if (-not $sid) { continue }
    $seen = $false
    foreach ($old in $slots) {
      if ($old -eq $sid) { $seen = $true }
    }
    if (-not $seen) { [void]$slots.Add($sid) }
  }
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($slots.Count -eq 1) {
    $slot = Format-YaShownId ([string]$slots[0])
    return ($head + '它在槽 ' + $slot + '。请用 exp_hold id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $tail + $hold)
  }
  if ($slots.Count -gt 1) {
    return ($head + '它在这些槽里: ' + (Join-YaShownIds $slots) + '。请带上具体槽，不要写 slot=all。' + $tail + $hold)
  }
  if ($hold) { return ($head + $hold) }
  return ($head + '请写 exp_hold id=条目号 slot=具体槽。' + $tail)
}

function Format-YaMissingDraft([string]$Lib, [string]$SlotId, [string]$Id, [string]$Verb = 'exp_save') {
  $split = Get-YaPlaceSplit $Lib $Id
  $places = Get-YaItems $split.real
  $draftSlots = New-Object System.Collections.Generic.List[string]
  $indexSlots = New-Object System.Collections.Generic.List[string]
  $indexedHere = $false
  foreach ($p in $places) {
    $sid = [string]$p.id
    if ([bool]$p.draft) { [void]$draftSlots.Add($sid) }
    if ([bool]$p.formal) {
      if ($sid -eq $SlotId) { $indexedHere = $true }
      else { [void]$indexSlots.Add($sid) }
    }
  }
  if (-not $Verb) { $Verb = 'exp_save' }
  $head = '没有这份草稿: ' + (Format-YaShownId $Id) + '。'
  $hold = ''
  if ($split.reserved) { $hold = (Format-YaReservedHold) }
  if ($indexedHere) { return ($head + '它已经在这个槽的索引里。' + $hold) }
  if ($draftSlots.Count -eq 1) {
    $slot = Format-YaShownId ([string]$draftSlots[0])
    return ($head + '它在槽 ' + $slot + ' 的草稿里。请用 ' + $Verb + ' id=' + (Format-YaShownId $Id) + ' slot=' + $slot + '。' + $hold)
  }
  if ($draftSlots.Count -gt 1) {
    return ($head + '草稿在这些槽里: ' + (Join-YaShownIds $draftSlots) + '。请带上 slot=，例如 ' + $Verb + ' id=' + (Format-YaShownId $Id) + ' slot=具体槽。' + $hold)
  }
  if ($indexSlots.Count -gt 0) {
    return ($head + '它已经在槽 ' + (Join-YaShownIds $indexSlots) + ' 的索引里。' + $hold)
  }
  if ($hold) { return ($head + $hold) }
  return ($head + '其他槽里也没有。')
}

function Invoke-YaSearch([string]$Lib, $Map, [bool]$Recall) {
  $slotArg = Repair-YaLine (Get-YaArg $Map 'slot')
  if (-not $slotArg) { $slotArg = (Resolve-YaSlot $Lib '').id }
  if (Test-YaCrossSlotWord $slotArg) { $slotArg = 'all' }
  $query = Get-YaArg $Map 'q'
  $tag = Get-YaArg $Map 'tag'
  $taskId = Get-YaArg $Map 'task'
  $gateTag = $tag
  if ($taskId) {
    $flow = Read-YaFlow $Lib
    if (-not $flow.current -or [string]$flow.current.id -cne $taskId -or [string]$flow.current.slot -cne $slotArg -or [string]$flow.current.status -ne '进行中') { throw 'TASK_SEARCH_MISMATCH: task=必须是本槽当前进行中的任务；不是经验标签过滤条件。' }
    $gateTag = [string]$flow.current.tag
  }
  $hits = Search-YaDual $Lib $slotArg $query $tag
  $hitList = Get-YaItems $hits
  $clean = New-Object System.Collections.Generic.List[object]
  $skipped = 0
  foreach ($hit in $hitList) {
    if (Test-YaIndexContentDirty $hit.entry ([string]$hit.slot)) { $skipped++; continue }
    [void]$clean.Add($hit)
  }
  Mark-YaRecalled $Lib $slotArg $gateTag $query $clean.Count
  $usage = Get-YaSlotUsage $Lib $slotArg
  Write-Output ('slot: ' + (Format-YaShownId $slotArg))
  Write-Output ('query: ' + (Repair-YaLine $query))
  Write-Output ('tag: ' + (Repair-YaLine $tag))
  if ($taskId) { Write-Output ('task: ' + $taskId) }
  Write-Output ('hits: ' + $clean.Count)
  foreach ($hit in $clean) {
    $e = $hit.entry
    $id = Format-YaShownId (Get-YaTextProp $e 'id')
    $shownSlot = Format-YaShownId ([string]$hit.slot)
    $line = '- slot=' + $shownSlot + ' id=' + $id + ' c=' + (Get-YaTextProp $e 'c') + ' t=' + (Get-YaTextProp $e 't') + ' f=' + (Format-YaShown (Get-YaTextProp $e 'f'))
    $mark = Repair-YaLine (Get-YaTextProp $e 'm')
    if ($mark) { $line += ' m=' + (Format-YaShown $mark) }
    Write-Output $line
    Write-Output ('  get: exp_get id=' + $id + ' slot=' + $shownSlot)
    Write-Output ('  preview: ' + (Format-YaPreview (Get-YaTextProp $e 't')))
  }
  if ($clean.Count -eq 0) {
    Write-Output 'get: none'
    Write-Output 'preview: none'
  }
  Write-Output ('usage_calls: ' + $usage.calls)
  Write-Output ('usage_token: ' + $usage.token)
  Write-Output ('tag_index: ' + (Join-Path $Lib '任务标签.json'))
  Write-Output 'note: 全文用 get 那一行。检索只给摘要，不贴整段。'
  if ($skipped -gt 0) {
    Write-Output ('note: 有 ' + $skipped + ' 条含禁止写入的词，没有列出来。')
  }
  if ($Recall) {
    Write-Output 'recall: yes'
    if ($clean.Count -gt 0) {
      Write-Output 'next: 有命中先按 get 行 exp_get，沿用那条。确实用不上，才可以生成。'
    } else {
      Write-Output 'next: 没有命中，才可以生成，再写草稿。'
    }
  }
  if (Test-YaCrossSlotWord $slotArg) {
    $reservedSlot = Find-YaReservedSlot $Lib
    if ($null -ne $reservedSlot) {
      $reservedDir = Get-YaSlotDir $Lib $reservedSlot
      $bag = Get-YaReservedBag $reservedDir
      if ([int]$bag.entries -gt 0 -or [int]$bag.drafts -gt 0) {
        Write-Output ('reserved: all entries=' + $bag.entries + ' drafts=' + $bag.drafts)
        Write-Output ('note: 名为 all 的记录是保留名，这些条目不能当普通槽读。' + (Get-YaReservedClearHint))
      }
    }
  }
}

try {
  $argsMap = Read-YaArgs $Rest
  if ($Command -in @('help', '-h', '--help', '/?')) {
    Write-YaHelp
    Write-Output 'RESULT: OK'
    exit 0
  }

  $root = Get-YaPackageRoot
  if(Test-Path -LiteralPath (Join-Path $root 'YA插件\真实记录.ps1')) {
    . (Join-Path $root 'YA插件\连接上下文.ps1')
    . (Join-Path $root 'YA插件\真实记录.ps1')
    Assert-YaOperation $root
  }
  $lib = Initialize-YaLibrary $root
  Initialize-YaFlow $lib
  if($Command -in @('skill_search','skill_get')){
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root '经验库\通用技能库\00_索引\查询.ps1') $Command @Rest
    exit $LASTEXITCODE
  }

  if ($Command -eq 'self_check') {
    foreach ($rel in @(
        '连接教练\说明.md',
        '连接教练\三步闸.md',
        '连接教练\提示模板.md',
        '连接教练\自检清单.md'
      )) {
      $p = Join-Path $root $rel
      if (-not (Test-Path -LiteralPath $p)) { throw ('缺少: ' + $rel) }
      Write-Output ('coach: ' + $rel)
    }
    $cfg = Read-YaSlots $lib
    Write-Output ('package: ' + $root)
    Write-Output ('library: ' + $lib)
    Write-Output ('active: ' + (Format-YaShownId (Get-YaTextProp $cfg 'active')))
    foreach ($s in (Get-YaItems $cfg.slots)) {
      $dir = Initialize-YaSlot $lib $s
      $idx = Read-YaIndex $dir
      foreach ($name in @('招式库', '坑库', '零件方案库')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $name))) { throw ('槽目录缺了: ' + (Join-Path $dir $name)) }
      }
      $suffix = ''
      if (Test-YaCrossSlotWord ([string]$s.id)) { $suffix = ' reserved' }
      Write-Output ('slot ' + (Format-YaShownId ([string]$s.id)) + ' entries=' + (Get-YaItems $idx.entries).Count + $suffix)
    }
    $ov = Get-YaOverview $lib
    Write-Output ('linked: ' + $ov.linked_count)
    Write-Output ('usage_calls: ' + $ov.sum_calls)
    Write-Output 'note: 自检只检查包、经验槽和教练文件，不代表任何机械软件已经接通。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'status') {
    $cfg = Read-YaSlots $lib
    $runtime = ''
    foreach ($scope in @('Process', 'User')) {
      $h = [Environment]::GetEnvironmentVariable('YALINK_HOME', $scope)
      if ($h) { $runtime = $h; break }
    }
    $homeFile = Join-Path $PSScriptRoot 'package_root.txt'
    Write-Output ('package: ' + $root)
    Write-Output ('library: ' + $lib)
    Write-Output ('runtime: ' + $(if ($runtime) { $runtime } else { '(还没装，或当前进程看不见用户环境变量)' }))
    Write-Output ('runtime_copy: ' + $(if (Test-Path -LiteralPath $homeFile) { 'yes' } else { 'no（现在跑的是包内脚本）' }))
    Write-Output ('active: ' + (Format-YaShownId (Get-YaTextProp $cfg 'active')))
    $ov = Get-YaOverview $lib
    Write-Output ('linked: ' + $ov.linked_count)
    Write-Output ('usage_calls: ' + $ov.sum_calls)
    Write-Output 'note: 消耗明细用 overview。已挂只统计三步闸过关，不代表本包探测过你的软件。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'overview') {
    Write-YaLines (Format-YaOverview $lib)
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'panel') {
    $panel = Join-Path $PSScriptRoot 'ya_panel.ps1'
    if (-not (Test-Path -LiteralPath $panel)) { throw ('缺少面板脚本: ' + $panel) }
    $pass = @()
    if ((Get-YaArg $argsMap 'snapshot') -eq '1') { $pass += '-Snapshot' }
    if ((Get-YaArg $argsMap 'uicheck') -eq '1') { $pass += '-UiCheck' }
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $panel @pass
    if ($LASTEXITCODE -ne 0) { throw '面板没有跑完。' }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'slot_list') {
    $cfg = Read-YaSlots $lib
    $active = Get-YaTextProp $cfg 'active'
    foreach ($s in (Get-YaItems $cfg.slots)) {
      $mark = ''
      if ([string]$s.id -eq $active) { $mark = ' active' }
      if (Test-YaCrossSlotWord ([string]$s.id)) { $mark = $mark + ' reserved' }
      Write-Output ('slot ' + (Format-YaShownId ([string]$s.id)) + ' title=' + (Format-YaShown ([string]$s.title)) + $mark)
    }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'slot_add') {
    $id = Get-YaArg $argsMap 'id'
    $use = (Get-YaArg $argsMap 'use') -eq '1'
    Add-YaSlot $lib $id (Get-YaArg $argsMap 'title') (Get-YaArg $argsMap 'note') $use
    Write-Output ('added: ' + (Format-YaShownId $id))
    Write-Output 'note: 开槽只是记账，不是已挂。已挂要走三步闸。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'slot_use') {
    $id = Get-YaArg $argsMap 'id'
    if (-not $id) { throw 'slot_use 需要 id=槽id。' }
    Set-YaActiveSlot $lib $id
    Write-Output ('active: ' + (Format-YaShownId $id))
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'slot_remove') {
    $id = Get-YaArg $argsMap 'id'
    if (-not $id) { throw 'slot_remove 需要 id=槽id。' }
    $to = Repair-YaLine (Get-YaArg $argsMap 'to')
    $dropText = Repair-YaLine (Get-YaArg $argsMap 'drop')
    if ($dropText -and $dropText -ne '1') { throw 'drop 只能是 1，表示清掉误建的 all 槽。' }
    $removed = Remove-YaSlot $lib $id $to ($dropText -eq '1')
    $linksNow = Read-YaLinks $lib
    $rid = [string]$removed.id
    $linkedBefore = $false
    $pendingBefore = $false
    $failedBefore = $false
    foreach ($row in (Get-YaItems $linksNow.linked)) {
      if ([string]$row['id'] -eq $rid) { $linkedBefore = $true; break }
    }
    foreach ($row in (Get-YaItems $linksNow.pending)) {
      if ([string]$row['id'] -eq $rid) { $pendingBefore = $true; break }
    }
    foreach ($row in (Get-YaItems $linksNow.failed)) {
      if ([string]$row['id'] -eq $rid) { $failedBefore = $true; break }
    }
    Remove-YaFlowSlot $lib $rid
    Write-Output ('removed: ' + (Format-YaShownId ([string]$removed.id)))
    if ($removed.reserved) {
      if ($to) {
        Write-Output ('moved_entries: ' + $removed.moved_entries)
        Write-Output ('moved_drafts: ' + $removed.moved_drafts)
        Write-Output ('to: ' + (Format-YaShownId ([string]$removed.to)))
      }
      if ($removed.dropped) {
        Write-Output ('dropped_entries: ' + $removed.dropped_entries)
        Write-Output ('dropped_drafts: ' + $removed.dropped_drafts)
      }
      Write-Output 'note: all 是保留名，这个误建的槽已清掉。跨槽检索仍写 exp_search slot=all。'
    }
    if ($linkedBefore) {
      Write-Output 'note: 这个槽在已挂清单里，删除时已挂记录一并拿掉。'
    }
    if ($pendingBefore) {
      Write-Output 'note: 这个槽在待过关里，删除时待过关记录一并拿掉。'
    }
    if ($failedBefore) {
      Write-Output 'note: 这个槽有失败记录，删除时失败记录一并拿掉。'
    }
    if ($removed.usage_cleared) {
      Write-Output 'note: 这个槽的调用次数和 TOKEN 一并拿掉。同名再开是未登记，调用从 0 开始。'
    }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_search' -or $Command -eq 'exp_recall') {
    Invoke-YaSearch $lib $argsMap ($Command -eq 'exp_recall')
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_get') {
    $slotArg = Get-YaArg $argsMap 'slot'
    $id = Get-YaArg $argsMap 'id'
    if (Test-YaReservedActive $lib $slotArg) { throw (Format-YaAllGet $lib $id) }
    $resolved = Resolve-YaSlot $lib $slotArg
    if (-not $id) { throw 'exp_get 需要 id=条目号。' }
    $file = Get-YaFormalFile $resolved.dir $id
    $where = 'index'
    if (-not $file) {
      $file = Get-YaDraftFile $resolved.dir $id
      if (-not $file) { throw (Format-YaMissingGet $lib $resolved.id $id) }
      $where = 'draft'
    }
    $full = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
    if ($where -eq 'index' -and (Test-YaFileForbidden $file)) {
      throw ('这条经验含禁止写入的词，不能调取。只连接自己已有的合法软件。请用 exp_hold id=' + (Format-YaShownId $id) + ' slot=' + (Format-YaShownId $resolved.id) + ' 清出索引，改回草稿后再改。')
    }
    Add-YaCall $lib $resolved.id
    $usage = Get-YaSlotUsage $lib $resolved.id
    Write-Output ('where: ' + $where)
    Write-Output ('file: ' + (Format-YaShown $file))
    Write-Output ('usage_calls: ' + $usage.calls)
    Write-Output ('usage_token: ' + $usage.token)
    Write-Output ('tags: ' + (Format-YaStoredTags $file))
    Write-Output '-----'
    Write-Output $full
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_done') {
    if (Test-YaReservedActive $lib (Get-YaArg $argsMap 'slot')) { throw (Format-YaAllDone $lib) }
    $resolved = Resolve-YaSlot $lib (Get-YaArg $argsMap 'slot')
    Assert-YaCanGenerate $lib $resolved.id
    Assert-YaDraftTaskTag $lib $resolved.id (Get-YaArg $argsMap 'tag')
    $cat = Get-YaArg $argsMap 'c'
    if (-not $cat) { $cat = '招式' }
    $recipe=$null;$title=Get-YaArg $argsMap 't'
    if(Get-YaArg $argsMap 'record'){
      $recipe=Read-YaRecipe (Get-YaArg $argsMap 'record') $resolved.id
      if($title -and $title -cne $recipe.title){throw 't与经验记录标题不一致'}
      $title=$recipe.title
    }
    $made = New-YaDraft $resolved.dir $resolved.id $cat $title (Get-YaArg $argsMap 'k') (Get-YaArg $argsMap 'm') (Get-YaArg $argsMap 'tag') $recipe
    Consume-YaRecall $lib
    Write-Output ('slot: ' + (Format-YaShownId $resolved.id))
    Write-Output ('draft: ' + (Format-YaShownId $made.id))
    Write-Output ('file: ' + (Format-YaShown $made.path))
    Write-Output 'indexed: no'
    Write-Output 'note: 草稿不进索引。你在自己的软件里验证之后，再 exp_save id=该号 verified=1。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_save') {
    if (Test-YaReservedActive $lib (Get-YaArg $argsMap 'slot')) { throw (Format-YaAllSave $lib (Get-YaArg $argsMap 'id')) }
    $resolved = Resolve-YaSlot $lib (Get-YaArg $argsMap 'slot')
    $id = Get-YaArg $argsMap 'id'
    if (-not $id) { throw 'exp_save 需要 id=草稿号。' }
    if (-not (Get-YaDraftFile $resolved.dir $id)) { throw (Format-YaMissingDraft $lib $resolved.id $id) }
    if ((Get-YaArg $argsMap 'verified') -ne '1') {
      Write-Output ('slot: ' + (Format-YaShownId $resolved.id))
      Write-Output ('id: ' + (Format-YaShownId $id))
      Write-Output 'indexed: no'
      Write-Output 'note: 没有 verified=1，草稿保持原位。本包不代任何机械软件做验证。'
      Write-Output 'RESULT: OK'
      exit 0
    }
    $saved = Publish-YaDraft $resolved.dir $resolved.id $id
    Write-Output ('slot: ' + (Format-YaShownId $resolved.id))
    Write-Output ('id: ' + (Format-YaShownId $saved.id))
    Write-Output ('file: ' + (Format-YaShown $saved.file))
    Write-Output 'indexed: yes'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_drop') {
    $dropped = Remove-YaDraftOnly $lib (Get-YaArg $argsMap 'slot') (Get-YaArg $argsMap 'id')
    Write-Output ('slot: ' + (Format-YaShownId $dropped.slot))
    Write-Output ('dropped: ' + (Format-YaShownId $dropped.id))
    Write-Output 'where: draft'
    Write-Output 'indexed: no'
    Write-Output 'note: 只丢掉这一份还没入库的草稿。槽还在，不删已入库的条目。drop=1 仍只用来清掉误建的 all。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'exp_hold') {
    $held = Hold-YaDirtyEntry $lib (Get-YaArg $argsMap 'slot') (Get-YaArg $argsMap 'id')
    Write-Output ('slot: ' + (Format-YaShownId $held.slot))
    Write-Output ('id: ' + (Format-YaShownId $held.id))
    Write-Output ('action: ' + $held.action)
    Write-Output ('indexed: ' + $held.indexed)
    Write-Output ('where: ' + $held.where)
    Write-Output ('get: exp_get id=' + (Format-YaShownId $held.id) + ' slot=' + (Format-YaShownId $held.slot))
    Write-Output ('note: ' + $held.note)
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'coach_start') {
    $made = Start-YaCoach $lib (Get-YaArg $argsMap 'id') (Get-YaArg $argsMap 'title')
    Write-Output ('id: ' + (Format-YaShownId $made.id))
    Write-Output ('title: ' + (Format-YaShown ([string]$made.title)))
    Write-Output ('status: ' + $made.status)
    if ($made.status -eq 'linked') {
      Write-Output 'linked: yes'
      Write-Output 'note: 这个软件已经在已挂清单里。再跑一次不会把它打回待过关。'
    } elseif ($made.status -eq 'pending') {
      Write-Output 'linked: no'
      Write-Output 'note: 三步闸还在进行中。过关之前不会写入已挂。'
    } else {
      Write-Output 'linked: no'
      Write-Output 'note: 这只是三步闸的起点。过关之前不会写入已挂。'
    }
    if ([int]$made.cleared -gt 0) {
      Write-Output 'note: 这个软件以前的失败记录已拿掉。'
    }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'coach_step') {
    $stepText = Get-YaArg $argsMap 'step'
    if ($stepText -notmatch '^[123]$') { throw 'coach_step 需要 step=1、2 或 3。' }
    $made = Add-YaCoachStep $lib (Get-YaArg $argsMap 'id') ([int]$stepText) (Get-YaArg $argsMap 'note')
    Write-Output ('id: ' + (Format-YaShownId $made.id))
    Write-Output ('step: ' + $made.step)
    Write-Output ('status: ' + $made.status)
    if ($made.linked) { Write-Output 'linked: yes' } else { Write-Output 'linked: no' }
    if ($made.merged) { Write-Output 'note: 重复的这一步已收成一条。' }
    if ($made.dropped) { Write-Output 'note: 这一步重记了，后面的步骤已作废。请按顺序再记。' }
    if ([int]$made.cleared -gt 0) {
      Write-Output 'note: 这个软件以前的失败记录已拿掉。'
    }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'coach_fail') {
    $stepText = Get-YaArg $argsMap 'step'
    if ($stepText -notmatch '^[123]$') { throw 'coach_fail 需要 step=1、2 或 3。' }
    $made = Fail-YaCoach $lib (Get-YaArg $argsMap 'id') ([int]$stepText) (Get-YaArg $argsMap 'note')
    Write-Output ('id: ' + (Format-YaShownId $made.id))
    Write-Output ('step: ' + $made.step)
    Write-Output ('status: ' + $made.status)
    Write-Output 'linked: no'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'link_list') {
    Write-YaLines (Format-YaLinks $lib)
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'task_open') {
    if (Test-YaReservedActive $lib (Get-YaArg $argsMap 'slot')) { throw (Format-YaAllTask (Get-YaArg $argsMap 'tag') (Get-YaArg $argsMap 'title')) }
    $task = Open-YaTask $lib (Get-YaArg $argsMap 'slot') (Get-YaArg $argsMap 'tag') (Get-YaArg $argsMap 'title')
    Write-Output ('task: ' + $task['id'])
    Write-Output ('slot: ' + (Format-YaShownId ([string]$task['slot'])))
    Write-Output ('tag: ' + $task['tag'])
    Write-Output 'status: 进行中'
    Write-Output 'complete: no'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'step_check') {
    $row = Set-YaCheck $lib (Get-YaArg $argsMap 'item') (Get-YaArg $argsMap 'pass') (Get-YaArg $argsMap 'note')
    $mark = '0'
    if ($row.pass) { $mark = '1' }
    Write-Output ('item: ' + $row.id)
    Write-Output ('title: ' + $row.title)
    Write-Output ('pass: ' + $mark)
    Write-Output 'complete: no'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'step_finish') {
    $done = Finish-YaTask $lib
    Write-YaLines $done.lines
    if (-not $done.ok) { throw [string]$done.error }
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'step_accept' -or $Command -eq 'step_reject' -or $Command -eq 'step_hand') {
    $kind = 'accept'
    if ($Command -eq 'step_reject') { $kind = 'reject' }
    if ($Command -eq 'step_hand') { $kind = 'hand' }
    $done = Close-YaTask $lib $kind (Get-YaArg $argsMap 'note')
    Write-Output ('task: ' + $done.id)
    Write-Output ('status: ' + $done.status)
    Write-Output ('complete: ' + $done.complete)
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'task_status') {
    Write-YaLines (Format-YaTask $lib)
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($Command -eq 'usage_set') {
    $set = Set-YaToken $lib (Get-YaArg $argsMap 'slot') (Get-YaArg $argsMap 'token') (Get-YaArg $argsMap 'note')
    Write-Output ('slot: ' + (Format-YaShownId (Get-YaArg $argsMap 'slot')))
    Write-Output ('token: ' + (Format-YaToken $set.token))
    Write-Output 'note: 这个数字只来自你填的用量。本包没有去读任何软件或平台。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  throw ('没有这个命令: ' + $Command + '。可运行 help。')
}
catch {
  Write-Output ('ERROR: ' + $_.Exception.Message)
  Write-Output 'RESULT: FAIL'
  exit 1
}
