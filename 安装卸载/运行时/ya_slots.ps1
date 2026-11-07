# 经验按软件分槽。只读写本包「经验库」，不启动、不探测任何机械软件。
# 由 ya.ps1 点源。Windows PowerShell 5.1。

$script:YaCatDir = @{
  '招式'     = '招式库'
  '坑'       = '坑库'
  '零件方案' = '零件方案库'
}

function Test-YaForbidden([string]$Text) {
  if ([string]::IsNullOrEmpty($Text)) { return $false }
  return [bool]($Text -match '(?i)破解|注册机|盗版|keygen|\bcrack\b')
}

function Assert-YaClean([string]$Text) {
  if (Test-YaForbidden $Text) {
    throw '禁止写入侵权或不合法连接相关内容。只连接自己已有的合法软件。'
  }
}

function Repair-YaLine([string]$Text) {
  if ($null -eq $Text) { return '' }
  return (($Text -replace '[\r\n\t]', ' ').Trim())
}

function Split-YaCommaList([string]$Text) {
  $list = New-Object System.Collections.Generic.List[string]
  $raw = Repair-YaLine $Text
  if (-not $raw) { return ,$list }
  foreach ($one in @($raw.Split([char[]]@(',', '，'), [StringSplitOptions]::RemoveEmptyEntries))) {
    $t = Repair-YaLine ([string]$one)
    if ($t) { [void]$list.Add($t) }
  }
  return ,$list
}

function Escape-YaJson([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
  return $s
}

function ConvertTo-YaJson($v, [int]$indent) {
  $pad = '  ' * $indent
  $padIn = '  ' * ($indent + 1)
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return '"' + (Escape-YaJson $v) + '"' }
  if ($v -is [byte] -or $v -is [int16] -or $v -is [int32] -or $v -is [int64] -or $v -is [decimal] -or $v -is [double] -or $v -is [single]) {
    return ([string]$v)
  }
  if ($v -is [System.Collections.IList]) {
    if ($v.Count -eq 0) { return '[]' }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in $v) { [void]$lines.Add($padIn + (ConvertTo-YaJson $item ($indent + 1))) }
    $nl = "`r`n"
    return ('[' + $nl + ($lines -join (',' + $nl)) + $nl + $pad + ']')
  }
  $pairs = New-Object System.Collections.Generic.List[object]
  if ($v -is [System.Collections.IDictionary]) {
    foreach ($key in $v.Keys) { [void]$pairs.Add(@([string]$key, $v[$key])) }
  } else {
    foreach ($p in $v.PSObject.Properties) { [void]$pairs.Add(@([string]$p.Name, $p.Value)) }
  }
  if ($pairs.Count -eq 0) { return '{}' }
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($pair in $pairs) {
    [void]$lines.Add($padIn + '"' + (Escape-YaJson $pair[0]) + '": ' + (ConvertTo-YaJson $pair[1] ($indent + 1)))
  }
  $nl = "`r`n"
  return ('{' + $nl + ($lines -join (',' + $nl)) + $nl + $pad + '}')
}

function Write-YaJsonFile([string]$Path, $Obj) {
  $packageRoot=Get-YaPackageRoot
  $actualModule=Join-Path $packageRoot 'YA插件\真实记录.ps1'
  if(Test-Path -LiteralPath $actualModule){
    if(-not (Get-Command Assert-YaOperation -ErrorAction SilentlyContinue)){
      . (Join-Path $packageRoot 'YA插件\连接上下文.ps1')
      . $actualModule
    }
    Assert-YaOperation $packageRoot
  }
  $json = (ConvertTo-YaJson $Obj 0).Trim() + "`r`n"
  $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  try {
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $true))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, ($tmp + '.bak')); [IO.File]::Delete($tmp + '.bak') } else { [IO.File]::Move($tmp, $Path) }
  } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

function Read-YaJsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw ('找不到文件: ' + $Path) }
  $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
  try { return ($raw | ConvertFrom-Json) }
  catch { throw ('JSON 读不了: ' + $Path + ' ；' + $_.Exception.Message) }
}

function Get-YaTextProp($Obj, [string]$Name) {
  if ($null -eq $Obj) { return '' }
  if ($Obj -is [System.Collections.IDictionary]) {
    if (-not $Obj.Contains($Name)) { return '' }
    if ($null -eq $Obj[$Name]) { return '' }
    return [string]$Obj[$Name]
  }
  $p = $Obj.PSObject.Properties[$Name]
  if (-not $p -or $null -eq $p.Value) { return '' }
  return [string]$p.Value
}

function Get-YaPackageRoot {
  $marker = Join-Path $PSScriptRoot 'package_root.txt'
  if (Test-Path -LiteralPath $marker) {
    $p = ([IO.File]::ReadAllText($marker, [Text.Encoding]::UTF8)).Trim()
    if ($p.Length -gt 0 -and [int]$p[0] -eq 0xFEFF) { $p = $p.Substring(1).Trim() }
    if ($p -and (Test-Path -LiteralPath $p)) { return [IO.Path]::GetFullPath($p) }
  }
  $parent = Split-Path $PSScriptRoot -Parent
  if ((Split-Path $parent -Leaf) -eq '安装卸载') {
    return [IO.Path]::GetFullPath((Split-Path $parent -Parent))
  }
  foreach ($scope in @('Process', 'User')) {
    $p = [Environment]::GetEnvironmentVariable('YALINK_PACKAGE', $scope)
    if ($p -and (Test-Path -LiteralPath $p)) { return [IO.Path]::GetFullPath($p) }
  }
  throw '找不到本包根目录。请在本包里运行 安装卸载\安装.ps1。'
}

function Get-YaLibrary([string]$Root) {
  $lib = Join-Path $Root '经验库'
  if (-not (Test-Path -LiteralPath $lib)) { throw ('经验库不存在: ' + $lib) }
  $cfg = Join-Path $lib '槽位.json'
  if (-not (Test-Path -LiteralPath $cfg)) { throw ('缺少槽位配置: ' + $cfg) }
  return $lib
}

function Read-YaSlots([string]$Lib) {
  $cfg = Read-YaJsonFile (Join-Path $Lib '槽位.json')
  if (-not $cfg.slots) { throw '槽位.json 里没有 slots。' }
  return $cfg
}

function Write-YaSlots([string]$Lib, $Cfg) {
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($s in (Get-YaItems $Cfg.slots)) {
    [void]$list.Add([ordered]@{
        id    = [string]$s.id
        title = [string]$s.title
        dir   = [string]$s.dir
        note  = (Get-YaTextProp $s 'note')
      })
  }
  $active = Get-YaTextProp $Cfg 'active'
  $doc = [ordered]@{
    version = 1
    active  = $active
    slots   = $list
  }
  Write-YaJsonFile (Join-Path $Lib '槽位.json') $doc
}

function Test-YaSlotId([string]$Id) {
  return ($Id -cmatch '^[a-z][a-z0-9_-]{0,31}$')
}

function Test-YaCrossSlotWord([string]$Id) {
  return ((Repair-YaLine $Id) -eq 'all')
}

function Test-YaEntryId([string]$Id) {
  return ($Id -cmatch '^[A-Za-z][A-Za-z0-9_-]{0,40}$')
}

function Get-YaItems($Value) {
  # @() 包一层泛型 List 时，Windows PowerShell 5.1 会抛「参数类型不匹配」。这里改用下标。
  # 返回时加逗号，避免函数把 List 拆成单个元素，导致 .Count 在只有一条时变成空。
  $out = New-Object System.Collections.Generic.List[object]
  if ($null -eq $Value) { return ,$out }
  if ($Value -is [string]) { [void]$out.Add($Value); return ,$out }
  if ($Value -is [System.Collections.IList]) {
    for ($i = 0; $i -lt $Value.Count; $i++) { [void]$out.Add($Value[$i]) }
    return ,$out
  }
  [void]$out.Add($Value)
  return ,$out
}

function Get-YaSlotDir([string]$Lib, $Slot) {
  return (Join-Path (Join-Path $Lib '槽') ([string]$Slot.dir))
}

function Initialize-YaSlot([string]$Lib, $Slot) {
  $id = [string]$Slot.id
  $dirName = [string]$Slot.dir
  if (-not (Test-YaSlotId $id)) { throw ('槽位 id 不合法: ' + (Format-YaShownId $id)) }
  if ($dirName -ne $id) { throw ('槽位 dir 必须与 id 相同: ' + (Format-YaShownId $id)) }
  $dir = Get-YaSlotDir $Lib $Slot
  $subs = @(
    '',
    '招式库',
    '坑库',
    '零件方案库',
    '_草稿',
    '_草稿\招式库',
    '_草稿\坑库',
    '_草稿\零件方案库'
  )
  foreach ($sub in $subs) {
    $p = $dir
    if ($sub) { $p = Join-Path $dir $sub }
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
  }
  $idx = Join-Path $dir '索引.json'
  if (-not (Test-Path -LiteralPath $idx)) {
    $empty = [ordered]@{
      '说明'    = '本槽经验索引。只收已验证条目。c=类别 t=一句话 k=关键词 tags=任务标签 m=报错特征 sw=软件槽 v=1已验证。用量不写在这里。'
      'entries' = (New-Object System.Collections.Generic.List[object])
    }
    Write-YaJsonFile $idx $empty
  }
  return $dir
}

function Initialize-YaLibrary([string]$Root) {
  . (Join-Path $Root 'YA插件\连接上下文.ps1') -PathsOnly
  Assert-YaIsolatedPackage $Root
  $lib = Get-YaLibrary $Root
  $cfg = Read-YaSlots $lib
  $seen = @{}
  foreach ($s in (Get-YaItems $cfg.slots)) {
    $id = [string]$s.id
    if ($seen.ContainsKey($id)) { throw ('槽位 id 重复: ' + (Format-YaShownId $id)) }
    $seen[$id] = $true
    Initialize-YaSlot $lib $s | Out-Null
  }
  $active = Get-YaTextProp $cfg 'active'
  if (-not $seen.ContainsKey($active)) { throw ('当前槽不在槽位表里: ' + (Format-YaShownId $active)) }
  return $lib
}

function Resolve-YaSlot([string]$Lib, [string]$Id) {
  $cfg = Read-YaSlots $Lib
  if (-not $Id) { $Id = Get-YaTextProp $cfg 'active' }
  $found = $null
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if ([string]$s.id -eq $Id) { $found = $s; break }
  }
  if (-not $found) { throw ('没有这个槽: ' + (Format-YaShownId $Id) + '。先看 slot_list，或用 slot_add 新建。') }
  $dir = Initialize-YaSlot $Lib $found
  return @{ cfg = $cfg; slot = $found; dir = $dir; id = [string]$found.id }
}

function Read-YaIndex([string]$SlotDir) {
  $path = Join-Path $SlotDir '索引.json'
  $o = Read-YaJsonFile $path
  $entries = Get-YaItems $o.entries
  return @{ path = $path; note = (Get-YaTextProp $o '说明'); entries = $entries }
}

function ConvertTo-YaKeywordList($Value) {
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($one in (Get-YaItems $Value)) {
    if ($null -eq $one) { continue }
    $t = ([string]$one).Trim()
    if ($t) { [void]$list.Add($t) }
  }
  return ,$list
}

function ConvertTo-YaUseCount([string]$Text) {
  # 条目上的 u。放得进 32 位的整数（含负数）仍保留。读不了或超过 32 位按 0，避免改索引时整段中断。
  $t = Repair-YaLine $Text
  if (-not $t -or $t -notmatch '^-?\d+$') { return 0 }
  $n = [int64]0
  if (-not [int64]::TryParse($t, [ref]$n)) { return 0 }
  if ($n -lt [int32]::MinValue -or $n -gt [int32]::MaxValue) { return 0 }
  return [int]$n
}

function Write-YaIndex([string]$SlotDir, [string]$Note, $Entries) {
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($e in (Get-YaItems $Entries)) {
    $k = ConvertTo-YaKeywordList $e.k
    $tags = ConvertTo-YaKeywordList $e.tags
    $u = ConvertTo-YaUseCount (Get-YaTextProp $e 'u')
    [void]$list.Add([ordered]@{
        id   = [string]$e.id
        c    = [string]$e.c
        t    = [string]$e.t
        k    = $k
        tags = $tags
        m    = (Get-YaTextProp $e 'm')
        sw   = (Get-YaTextProp $e 'sw')
        v    = 1
        u    = $u
        f    = [string]$e.f
      })
  }
  if (-not $Note) { $Note = '本槽经验索引。只收已验证条目。' }
  $doc = [ordered]@{
    '说明'    = $Note
    'entries' = $list
  }
  Write-YaJsonFile (Join-Path $SlotDir '索引.json') $doc
}

function Get-YaHay($Entry) {
  $k = (ConvertTo-YaKeywordList $Entry.k) -join ' '
  $tags = (ConvertTo-YaKeywordList $Entry.tags) -join ' '
  $bits = @(
    (Get-YaTextProp $Entry 'id'),
    (Get-YaTextProp $Entry 'c'),
    (Get-YaTextProp $Entry 't'),
    (Get-YaTextProp $Entry 'm'),
    (Get-YaTextProp $Entry 'sw'),
    $k,
    $tags
  )
  return (($bits | Where-Object { $_ }) -join ' ')
}

function Search-YaEntries($Entries, [string]$Q) {
  $tokens = @($Q.Split([char[]]@(' ', '　', "`t"), [StringSplitOptions]::RemoveEmptyEntries))
  $hits = New-Object System.Collections.Generic.List[object]
  foreach ($e in (Get-YaItems $Entries)) {
    if ($tokens.Count -eq 0) { [void]$hits.Add($e); continue }
    $hay = (Get-YaHay $e).ToLowerInvariant()
    $ok = $true
    foreach ($t in $tokens) {
      if ($hay.IndexOf($t.ToLowerInvariant()) -lt 0) { $ok = $false; break }
    }
    if ($ok) { [void]$hits.Add($e) }
  }
  return ,$hits.ToArray()
}

function Get-YaCatDirName([string]$Cat) {
  if ($script:YaCatDir.ContainsKey($Cat)) { return [string]$script:YaCatDir[$Cat] }
  throw '类别只接受：招式、坑、零件方案。'
}

function Get-YaDraftFile([string]$SlotDir, [string]$Id) {
  if (-not (Test-YaEntryId $Id)) { throw ('条目 id 不合法: ' + (Format-YaShownId $Id)) }
  foreach ($name in $script:YaCatDir.Values) {
    $p = Join-Path (Join-Path (Join-Path $SlotDir '_草稿') $name) ($Id + '.json')
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

function Get-YaFormalFile([string]$SlotDir, [string]$Id) {
  if (-not (Test-YaEntryId $Id)) { throw ('条目 id 不合法: ' + (Format-YaShownId $Id)) }
  foreach ($name in $script:YaCatDir.Values) {
    $p = Join-Path (Join-Path $SlotDir $name) ($Id + '.json')
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

function Find-YaEntryPlaces([string]$Lib, [string]$Id) {
  $out = New-Object System.Collections.Generic.List[object]
  if (-not (Test-YaEntryId $Id)) { return ,$out }
  $cfg = Read-YaSlots $Lib
  foreach ($s in (Get-YaItems $cfg.slots)) {
    $dir = Get-YaSlotDir $Lib $s
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $formal = Get-YaFormalFile $dir $Id
    $draft = Get-YaDraftFile $dir $Id
    $hasFormal = ($null -ne $formal -and [string]$formal -ne '')
    $hasDraft = ($null -ne $draft -and [string]$draft -ne '')
    if ($hasFormal -or $hasDraft) {
      [void]$out.Add(@{ id = [string]$s.id; formal = $hasFormal; draft = $hasDraft })
    }
  }
  return ,$out
}

function Assert-YaExperienceLimits([string]$Title, [string]$Mark, $Keys, $Tags) {
  if ((Repair-YaLine $Title).Length -gt 200) { throw 't 最长 200 字。' }
  if ((Repair-YaLine $Mark).Length -gt 200) { throw 'm 最长 200 字。' }
  $n = 0
  foreach ($one in (Get-YaItems $Keys)) {
    $t = Repair-YaLine ([string]$one)
    if (-not $t) { continue }
    $n++
    if ($t.Length -gt 40) { throw '单个关键词最长 40 字。' }
    if ($n -gt 12) { throw '关键词最多 12 个。' }
  }
  $n = 0
  foreach ($one in (Get-YaItems $Tags)) {
    $t = Repair-YaLine ([string]$one)
    if (-not $t) { continue }
    $n++
    if ($t.Length -gt 40) { throw '单个任务标签最长 40 字。' }
    if ($n -gt 8) { throw '任务标签最多 8 个。' }
  }
}

function Read-YaRecipe([string]$Path,[string]$Slot) {
  if((Get-Item -LiteralPath $Path -ErrorAction Stop).Length -gt 65536){throw '经验记录超过64KiB'}
  $o=Read-YaJsonFile $Path
  $rawRecord=ConvertTo-Json -InputObject $o -Depth 20 -Compress
  if($rawRecord -match '(?i)"(?:api_key|api-key|password|secret|authorization|access_token|license_key)"\s*:' -or $rawRecord -match 'sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----'){throw '经验记录含疑似凭据字段；先移除凭据，不将其写入经验'}
  if($o.schema -ne 1){throw '经验记录schema须为1'}
  foreach($key in @('title','objective','recovery','applicability','source')){
    $text=Get-YaTextProp $o $key
    if(-not $text.Trim() -or $text.Length -gt 2000){throw ('经验缺少或超长字段：'+$key)}
    Assert-YaClean $text
  }
  if($o.conditions.slot -cne $Slot){throw '经验条件的软件槽与当前槽不一致'}
  foreach($key in @('software','version','interface')){if(-not (Get-YaTextProp $o.conditions $key).Trim()){throw ('经验条件缺少：'+$key)}}
  if(-not $o.conditions.PSObject.Properties['parameters']){throw '经验条件缺少parameters'}
  $steps=Get-YaItems $o.steps
  if($steps.Count -lt 1 -or $steps.Count -gt 20){throw '经验步骤须为1至20项'}
  foreach($step in $steps){
    if($step -isnot [string] -or -not $step.Trim() -or $step.Length -gt 1000 -or $step -match '(?m)^\s*(```|#!|param\(|def\s|class\s|function\s|using\s|import\s)'){throw '步骤应为可理解的方法描述，不能用脚本正文代替'}
    Assert-YaClean $step
  }
  if(-not (Get-YaTextProp $o.verification 'check').Trim()){throw '经验缺少验证方法'}
  # 只保留方法与条件，不接受调用方注入的可信标志或执行代码。
  return [ordered]@{schema=1;title=$o.title;objective=$o.objective;conditions=@{slot=$Slot;software=$o.conditions.software;version=$o.conditions.version;interface=$o.conditions.interface;parameters=$o.conditions.parameters};steps=$steps;verification=@{check=$o.verification.check;evidence=$o.verification.evidence;claimed_result=$o.verification.claimed_result;provenance='caller_provided'};recovery=$o.recovery;applicability=$o.applicability;source=$o.source}
}
function New-YaDraft {
  param(
    [string]$SlotDir,
    [string]$SlotId,
    [string]$Cat,
    [string]$Title,
    [string]$Keywords,
    [string]$Mark,
    [string]$Tags,
    $Recipe
  )
  $catDir = Get-YaCatDirName $Cat
  $title = (Repair-YaLine $Title)
  if (-not $title) { throw 'exp_done 需要 t=一句话。' }
  if ($title.Length -gt 200) { throw 't 最长 200 字。' }
  $mark = (Repair-YaLine $Mark)
  if ($mark.Length -gt 200) { throw 'm 最长 200 字。' }
  Assert-YaClean $title
  Assert-YaClean $mark
  $keys = New-Object System.Collections.Generic.List[object]
  foreach ($one in (Split-YaCommaList $Keywords)) {
    $t = (Repair-YaLine $one)
    if (-not $t) { continue }
    if ($t.Length -gt 40) { throw '单个关键词最长 40 字。' }
    if ($keys.Count -ge 12) { throw '关键词最多 12 个。' }
    Assert-YaClean $t
    [void]$keys.Add($t)
  }
  $tagList = New-Object System.Collections.Generic.List[object]
  foreach ($one in (Split-YaCommaList $Tags)) {
    $t = (Repair-YaLine $one)
    if (-not $t) { continue }
    if ($t.Length -gt 40) { throw '单个任务标签最长 40 字。' }
    if ($tagList.Count -ge 8) { throw '任务标签最多 8 个。' }
    Assert-YaClean $t
    [void]$tagList.Add($t)
  }
  $id = 'D' + (Get-Date -Format 'yyyyMMddHHmmss')
  $n = 0
  while ((Get-YaDraftFile $SlotDir $id) -or (Get-YaFormalFile $SlotDir $id)) {
    $n++
    if ($n -gt 99) { throw '草稿编号不够用，请稍后再试。' }
    $id = 'D' + (Get-Date -Format 'yyyyMMddHHmmss') + ('{0:d2}' -f $n)
  }
  $doc = [ordered]@{
    id       = $id
    c        = $Cat
    t        = $title
    k        = $keys
    tags     = $tagList
    m        = $mark
    sw       = $SlotId
    v        = 0
    verified = $false
    note     = '未验证草稿，不在本槽索引里。'
  }
  if($Recipe){
    $doc['recipe']=$Recipe
    $flowFile=Join-Path (Split-Path (Split-Path $SlotDir -Parent) -Parent) '流程.json'
    if(Test-Path -LiteralPath $flowFile){$taskFlow=Read-YaJsonFile $flowFile;if($taskFlow.current){$doc['task_id']=$taskFlow.current.id}}
  }
  $path = Join-Path (Join-Path (Join-Path $SlotDir '_草稿') $catDir) ($id + '.json')
  Write-YaJsonFile $path $doc
  return @{ id = $id; path = $path }
}

function Publish-YaDraft {
  param([string]$SlotDir, [string]$SlotId, [string]$Id, [string]$Method, [object[]]$Proof, $Context)
  $draft = Get-YaDraftFile $SlotDir $Id
  if (-not $draft) { throw ('没有这份草稿: ' + (Format-YaShownId $Id) + '。未验证的不会进索引。') }
  $o = Read-YaJsonFile $draft
  $cat = Get-YaTextProp $o 'c'
  $catDir = Get-YaCatDirName $cat
  $title = Repair-YaLine (Get-YaTextProp $o 't')
  if (-not $title) { throw '草稿缺少 t，不能入库。' }
  $mark = Repair-YaLine (Get-YaTextProp $o 'm')
  $keys = ConvertTo-YaKeywordList $o.k
  $tags = ConvertTo-YaKeywordList $o.tags
  Assert-YaClean $title
  Assert-YaClean $mark
  Assert-YaClean (Get-YaTextProp $o 'note')
  foreach ($one in (Get-YaItems $keys)) { Assert-YaClean ([string]$one) }
  foreach ($one in (Get-YaItems $tags)) { Assert-YaClean ([string]$one) }
  Assert-YaExperienceLimits $title $mark $keys $tags
  $rel = $catDir + '/' + $Id + '.json'
  $dest = Join-Path (Join-Path $SlotDir $catDir) ($Id + '.json')
  $entry = [ordered]@{
    id = $Id
    c  = $cat
    t  = $title
    k    = $keys
    tags = $tags
    m    = $mark
    sw   = $SlotId
    v    = 1
    u    = 0
    f    = $rel
  }
  $full = [ordered]@{
    id       = $Id
    c        = $cat
    t        = $title
    k        = $keys
    tags     = $tags
    m        = $mark
    sw       = $SlotId
    v        = 1
    verified = $true
    note     = '已由使用人标记为验证后入库。本包不代任何机械软件复核。'
  }
  if ($Method -and $Proof.Count) {
    $full['method'] = $Method
    $full['proof'] = $Proof
    $full['note'] = '由本软件会话读回核对后自动入库。'
  }
  $full['verification_state'] = if ($Method -and $Proof.Count) { 'adapter_reported' } else { 'caller_declared' }
  $full['independently_verified'] = $false
  $full['recorded_utc'] = [DateTime]::UtcNow.ToString('o')
  if ($Context) { $full['context'] = $Context }
  if($o.PSObject.Properties['recipe']){$full['recipe']=$o.recipe}
  if($o.PSObject.Properties['task_id']){$full['task_id']=$o.task_id}
  Write-YaJsonFile $dest $full
  $idx = Read-YaIndex $SlotDir
  $keep = New-Object System.Collections.Generic.List[object]
  foreach ($e in (Get-YaItems $idx.entries)) {
    if ([string]$e.id -ne $Id) { [void]$keep.Add($e) }
  }
  [void]$keep.Add($entry)
  Write-YaIndex $SlotDir $idx.note $keep
  Remove-Item -LiteralPath $draft -Force
  $lib = Split-Path (Split-Path $SlotDir -Parent) -Parent
  Rebuild-YaTagIndex $lib | Out-Null
  return @{ id = $Id; file = $rel }
}

function Add-YaSlot([string]$Lib, [string]$Id, [string]$Title, [string]$Note, [bool]$Use) {
  if (Test-YaCrossSlotWord $Id) { throw 'all 只能用来跨槽检索，不能当作槽名。请换一个 id，例如 slot_add id=app1 title=我的机械软件。跨槽检索写 exp_search slot=all。' }
  if (-not (Test-YaSlotId $Id)) { throw '槽 id 要用小写英文开头，只含小写字母、数字、下划线、连字符，最长 32。' }
  if (Test-YaForbidden $Id) { throw '禁止写入侵权或不合法连接相关内容。只连接自己已有的合法软件。' }
  $title = (Repair-YaLine $Title)
  if (-not $title) { $title = $Id }
  if ($title.Length -gt 80) { throw '标题最长 80 字。' }
  $note = (Repair-YaLine $Note)
  if ($note.Length -gt 200) { throw '备注最长 200 字。' }
  Assert-YaClean $title
  Assert-YaClean $note
  $cfg = Read-YaSlots $Lib
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if ([string]$s.id -eq $Id) { throw ('槽已存在: ' + (Format-YaShownId $Id)) }
  }
  $slot = [pscustomobject]@{ id = $Id; title = $title; dir = $Id; note = $note }
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($s in (Get-YaItems $cfg.slots)) { [void]$list.Add($s) }
  [void]$list.Add($slot)
  $cfg.slots = $list.ToArray()
  if ($Use) { $cfg.active = $Id }
  Write-YaSlots $Lib $cfg
  Initialize-YaSlot $Lib $slot | Out-Null
}

function Get-YaReservedClearHint() {
  return '请先迁走再清：slot_remove id=all to=具体槽。不要了就 slot_remove id=all drop=1。'
}

function Find-YaReservedSlot([string]$Lib) {
  $cfg = Read-YaSlots $Lib
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if (Test-YaCrossSlotWord ([string]$s.id)) { return $s }
  }
  return $null
}

function Get-YaReservedBag([string]$Dir) {
  $entries = 0
  $drafts = 0
  if (Test-Path -LiteralPath (Join-Path $Dir '索引.json')) {
    $counts = Get-YaCounts $Dir
    $entries = [int]$counts.entries
    $drafts = [int]$counts.drafts
  } elseif (Test-Path -LiteralPath $Dir) {
    $draftRoot = Join-Path $Dir '_草稿'
    if (Test-Path -LiteralPath $draftRoot) {
      $drafts = @(Get-ChildItem -LiteralPath $draftRoot -Recurse -Filter *.json -File -ErrorAction SilentlyContinue).Count
    }
  }
  return @{ entries = $entries; drafts = $drafts }
}

function Test-YaReservedHasBody([string]$Dir) {
  $bag = Get-YaReservedBag $Dir
  if ([int]$bag.entries -gt 0 -or [int]$bag.drafts -gt 0) { return $true }
  if (-not (Test-Path -LiteralPath $Dir)) { return $false }
  $jsons = @(Get-ChildItem -LiteralPath $Dir -Recurse -Filter *.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '索引.json' })
  return ($jsons.Count -gt 0)
}

function Get-YaBodyIds([string]$Dir) {
  $ids = New-Object System.Collections.Generic.List[string]
  $seen = @{}
  if (-not (Test-Path -LiteralPath $Dir)) { return ,$ids }
  $idxPath = Join-Path $Dir '索引.json'
  if (Test-Path -LiteralPath $idxPath) {
    $idx = Read-YaIndex $Dir
    foreach ($e in (Get-YaItems $idx.entries)) {
      $id = [string]$e.id
      if (-not $id -or $seen.ContainsKey($id)) { continue }
      $seen[$id] = $true
      [void]$ids.Add($id)
    }
  }
  $files = @(Get-ChildItem -LiteralPath $Dir -Recurse -Filter *.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '索引.json' })
  foreach ($f in $files) {
    $id = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $id -or $seen.ContainsKey($id)) { continue }
    $seen[$id] = $true
    [void]$ids.Add($id)
  }
  return ,$ids
}

function Format-YaReservedIds([string]$Dir) {
  $show = New-Object System.Collections.Generic.List[string]
  $n = 0
  foreach ($id in (Get-YaItems (Get-YaBodyIds $Dir))) {
    $n++
    if ($n -gt 8) { [void]$show.Add('…'); break }
    [void]$show.Add((Format-YaShownId $id))
  }
  if ($show.Count -eq 0) { return '' }
  return ('条目号 ' + ($show -join '，') + '。')
}

function Test-YaIdInSlot([string]$Dir, [string]$Id) {
  if (-not (Test-Path -LiteralPath $Dir)) { return $false }
  if (-not (Test-YaEntryId $Id)) { return $false }
  $idxPath = Join-Path $Dir '索引.json'
  if (Test-Path -LiteralPath $idxPath) {
    $idx = Read-YaIndex $Dir
    foreach ($e in (Get-YaItems $idx.entries)) {
      if ([string]$e.id -eq $Id) { return $true }
    }
  }
  if (Get-YaFormalFile $Dir $Id) { return $true }
  if (Get-YaDraftFile $Dir $Id) { return $true }
  return $false
}

function Set-YaSwProp($Obj, [string]$SlotId) {
  if ($null -eq $Obj) { return }
  if ($Obj -is [System.Collections.IDictionary]) { $Obj['sw'] = $SlotId; return }
  $prop = $Obj.PSObject.Properties['sw']
  if ($prop) { $prop.Value = $SlotId }
  else { $Obj | Add-Member -NotePropertyName 'sw' -NotePropertyValue $SlotId -Force }
}

function Move-YaReservedBody([string]$FromDir, [string]$ToDir, [string]$ToId) {
  $entries = 0
  $drafts = 0
  if (-not (Test-Path -LiteralPath $FromDir)) { return @{ entries = 0; drafts = 0 } }
  $keep = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  $note = '本槽经验索引。只收已验证条目。'
  $dstIdxPath = Join-Path $ToDir '索引.json'
  if (Test-Path -LiteralPath $dstIdxPath) {
    $dstIdx = Read-YaIndex $ToDir
    if ($dstIdx.note) { $note = [string]$dstIdx.note }
    foreach ($e in (Get-YaItems $dstIdx.entries)) {
      $seen[[string]$e.id] = $true
      [void]$keep.Add($e)
    }
  }
  $srcIdxPath = Join-Path $FromDir '索引.json'
  if (Test-Path -LiteralPath $srcIdxPath) {
    $srcIdx = Read-YaIndex $FromDir
    foreach ($e in (Get-YaItems $srcIdx.entries)) {
      $id = [string]$e.id
      if (-not $id -or $seen.ContainsKey($id)) { continue }
      Set-YaSwProp $e $ToId
      [void]$keep.Add($e)
      $seen[$id] = $true
      $entries++
    }
  }
  $root = [IO.Path]::GetFullPath($FromDir).TrimEnd('\')
  $files = @(Get-ChildItem -LiteralPath $FromDir -Recurse -Filter *.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '索引.json' })
  foreach ($f in $files) {
    $full = [IO.Path]::GetFullPath($f.FullName)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw '迁文件时路径不对，没有继续删。' }
    $rel = $full.Substring($root.Length).TrimStart('\')
    $dest = Join-Path $ToDir $rel
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $obj = Read-YaJsonFile $f.FullName
    Set-YaSwProp $obj $ToId
    Write-YaJsonFile $dest $obj
    $isDraft = $rel.StartsWith('_草稿')
    if ($isDraft) { $drafts++ }
    $id = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $isDraft -and $id -and -not $seen.ContainsKey($id)) {
      [void]$keep.Add([pscustomobject]@{
          id   = $id
          c    = (Get-YaTextProp $obj 'c')
          t    = (Get-YaTextProp $obj 't')
          k    = $obj.k
          tags = $obj.tags
          m    = (Get-YaTextProp $obj 'm')
          sw   = $ToId
          v    = 1
          u    = 0
          f    = (($rel -replace '\\', '/'))
        })
      $seen[$id] = $true
      $entries++
    }
  }
  if ($entries -gt 0 -or (Test-Path -LiteralPath $dstIdxPath)) {
    Write-YaIndex $ToDir $note $keep
  }
  return @{ entries = $entries; drafts = $drafts }
}

function Remove-YaReservedSlot([string]$Lib, [string]$To, [bool]$Drop) {
  $cfg = Read-YaSlots $Lib
  $found = $null
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if (Test-YaCrossSlotWord ([string]$s.id)) { $found = $s }
    else { [void]$list.Add($s) }
  }
  if (-not $found) { throw 'all 只能用来跨槽检索，不能当作槽名。现在没有这个槽。跨槽检索写 exp_search slot=all。' }
  if ($list.Count -eq 0) { throw '至少留一个槽。' }
  $dir = Get-YaSlotDir $Lib $found
  $bag = Get-YaReservedBag $dir
  $hasBody = Test-YaReservedHasBody $dir
  if ($hasBody -and -not $To -and -not $Drop) {
    throw ('all 是保留名，不能当槽。请先迁走条目再清。索引里还有 ' + $bag.entries + ' 条，草稿 ' + $bag.drafts + ' 份。' + (Format-YaReservedIds $dir) + (Get-YaReservedClearHint) + '不要把它当成普通槽读写。')
  }
  $movedE = 0
  $movedD = 0
  $droppedE = 0
  $droppedD = 0
  $didDrop = $false
  if ($To) {
    if (Test-YaCrossSlotWord $To) { throw '目标不能是 all。all 只能用来跨槽检索。请换一个具体槽，例如 slot_remove id=all to=app1。' }
    if (-not (Test-YaSlotId $To)) { throw '目标槽 id 不合法。请换一个已经存在的具体槽。' }
    $target = $null
    foreach ($s in (Get-YaItems $list)) {
      if ([string]$s.id -eq $To) { $target = $s; break }
    }
    if (-not $target) { throw ('没有这个槽: ' + (Format-YaShownId $To) + '。请先 slot_add，再 slot_remove id=all to=' + (Format-YaShownId $To) + '。') }
    $toDir = Initialize-YaSlot $Lib $target
    foreach ($one in (Get-YaItems (Get-YaBodyIds $dir))) {
      if (-not (Test-YaEntryId $one)) { throw ('保留名 all 里有不合法的条目号 ' + (Format-YaShownId ([string]$one)) + '。没有迁，也没有删。') }
      if (Test-YaIdInSlot $toDir $one) {
        throw ('具体槽 ' + (Format-YaShownId $To) + ' 里已经有同号条目 ' + (Format-YaShownId ([string]$one)) + '。没有迁，也没有删 all。请换一个没有这个号的槽。')
      }
    }
    $moved = Move-YaReservedBody $dir $toDir $To
    $movedE = [int]$moved.entries
    $movedD = [int]$moved.drafts
  } elseif ($Drop) {
    $didDrop = $true
    $droppedE = [int]$bag.entries
    $droppedD = [int]$bag.drafts
  }
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  $cfg.slots = $list.ToArray()
  if (Test-YaCrossSlotWord (Get-YaTextProp $cfg 'active')) { $cfg.active = 'generic' }
  Write-YaSlots $Lib $cfg
  Rebuild-YaTagIndex $Lib | Out-Null
  $usageCleared = Remove-YaUsageSlot $Lib ([string]$found.id)
  return @{
    id              = [string]$found.id
    reserved        = $true
    to              = $To
    moved_entries   = $movedE
    moved_drafts    = $movedD
    dropped         = $didDrop
    dropped_entries = $droppedE
    dropped_drafts  = $droppedD
    usage_cleared   = [bool]$usageCleared
  }
}

function Get-YaDraftIdList([string]$SlotDir) {
  $ids = New-Object System.Collections.Generic.List[string]
  $draftRoot = Join-Path $SlotDir '_草稿'
  if (-not (Test-Path -LiteralPath $draftRoot)) { return ,$ids }
  $files = @(Get-ChildItem -LiteralPath $draftRoot -Recurse -Filter *.json -File -ErrorAction SilentlyContinue)
  foreach ($f in $files) {
    $id = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($id) { [void]$ids.Add($id) }
  }
  return ,$ids
}

function Format-YaSlotKeep([string]$Id, [int]$Entries, [int]$Drafts, $DraftIds, [int]$OtherFiles) {
  $msg = '这个槽不删除。'
  if ($Entries -gt 0) {
    $msg += '索引里还有条目 ' + $Entries + ' 条，已入库的留着。'
  }
  if ($Drafts -gt 0) {
    $show = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($one in (Get-YaItems $DraftIds)) {
      $n++
      if ($n -gt 8) { [void]$show.Add('…'); break }
      if ($one) { [void]$show.Add((Format-YaShownId ([string]$one))) }
    }
    $msg += '还有草稿 ' + $Drafts + ' 份'
    if ($show.Count -gt 0) { $msg += '（' + ($show -join '，') + '）' }
    $msg += '。丢掉草稿再删空槽：exp_drop id=草稿号 slot=' + (Format-YaShownId $Id) + '。已入库的条目不会被 exp_drop 清掉。'
  }
  if ($OtherFiles -gt 0 -and $Entries -eq 0) {
    $msg += '还有条目文件，不删除。'
  }
  $msg += 'drop=1 只用来清掉误建的 all，不能用来删普通槽。'
  return $msg
}

function Test-YaIndexedHere([string]$SlotDir, [string]$Id) {
  if (Get-YaFormalFile $SlotDir $Id) { return $true }
  if (-not (Test-Path -LiteralPath (Join-Path $SlotDir '索引.json'))) { return $false }
  $idx = Read-YaIndex $SlotDir
  foreach ($e in (Get-YaItems $idx.entries)) {
    if ([string]$e.id -eq $Id) { return $true }
  }
  return $false
}

function Find-YaIndexEntry([string]$SlotDir, [string]$Id) {
  if (-not (Test-Path -LiteralPath (Join-Path $SlotDir '索引.json'))) { return $null }
  $idx = Read-YaIndex $SlotDir
  foreach ($e in (Get-YaItems $idx.entries)) {
    if ([string]$e.id -eq $Id) { return $e }
  }
  return $null
}

function Test-YaIndexEntryDirty($Entry, [string]$SlotId) {
  # 条目 id 本身不算禁止词。路径里只因为这个 id 才出现的词也不算。和检索是同一套。
  # sw 若只是这条所在的槽 id，同样不算。句子、报错特征、关键词、标签里的禁止词仍算。
  return (Test-YaIndexContentDirty $Entry $SlotId)
}

function Test-YaIndexContentDirty($Entry, [string]$SlotId) {
  if ($null -eq $Entry) { return $false }
  $id = Get-YaTextProp $Entry 'id'
  $sw = Get-YaTextProp $Entry 'sw'
  foreach ($p in @(
      (Get-YaTextProp $Entry 'c'),
      (Get-YaTextProp $Entry 't'),
      (Get-YaTextProp $Entry 'm'),
      ((ConvertTo-YaKeywordList $Entry.k) -join ' '),
      ((ConvertTo-YaKeywordList $Entry.tags) -join ' ')
    )) {
    if (Test-YaForbidden ([string]$p)) { return $true }
  }
  if ($sw -and ($sw -ne $SlotId) -and (Test-YaForbidden $sw)) { return $true }
  $f = Get-YaTextProp $Entry 'f'
  if ($f) {
    $rest = [string]$f
    if ($id) { $rest = $rest.Replace([string]$id, '') }
    if (Test-YaForbidden $rest) { return $true }
  }
  return $false
}

function Test-YaValueForbidden($Value, [bool]$SkipId, [string]$SlotId) {
  # 用栈走 JSON，不把数组当参数传，避免 PowerShell 把数组拆开。只跳过顶层 id。
  # 顶层 sw 若正好是这条所在的槽 id，也不算禁止词。
  $stack = New-Object System.Collections.Stack
  $stack.Push([pscustomobject]@{ node = $Value; skip = $SkipId })
  while ($stack.Count -gt 0) {
    $cur = $stack.Pop()
    $node = $cur.node
    $skip = [bool]$cur.skip
    if ($null -eq $node) { continue }
    if ($node -is [string]) {
      if (Test-YaForbidden $node) { return $true }
      continue
    }
    if ($node -is [bool] -or $node -is [byte] -or $node -is [int16] -or $node -is [int32] -or $node -is [int64] -or $node -is [decimal] -or $node -is [double] -or $node -is [single]) {
      continue
    }
    if ($node -is [System.Collections.IList]) {
      for ($i = 0; $i -lt $node.Count; $i++) {
        $stack.Push([pscustomobject]@{ node = $node[$i]; skip = $false })
      }
      continue
    }
    if ($node -is [System.Collections.IDictionary]) {
      foreach ($key in @($node.Keys)) {
        if ($skip -and [string]$key -eq 'id') { continue }
        if ($skip -and $SlotId -and [string]$key -eq 'sw' -and [string]$node[$key] -eq $SlotId) { continue }
        $stack.Push([pscustomobject]@{ node = $node[$key]; skip = $false })
      }
      continue
    }
    $guard = 0
    foreach ($p in @($node.PSObject.Properties)) {
      if ($p.MemberType -ne 'NoteProperty') { continue }
      $guard++
      if ($guard -gt 80) { return $true }
      if ($skip -and $p.Name -eq 'id') { continue }
      if ($skip -and $SlotId -and $p.Name -eq 'sw' -and [string]$p.Value -eq $SlotId) { continue }
      $stack.Push([pscustomobject]@{ node = $p.Value; skip = $false })
    }
  }
  return $false
}

function Get-YaEntrySlotId([string]$Path) {
  if (-not $Path) { return '' }
  $dir = [IO.Path]::GetDirectoryName($Path)
  if (-not $dir) { return '' }
  $leaf = [IO.Path]::GetFileName($dir)
  $catNames = @($script:YaCatDir.Values)
  if ($catNames -contains $leaf) {
    $dir = [IO.Path]::GetDirectoryName($dir)
    if (-not $dir) { return '' }
    $leaf = [IO.Path]::GetFileName($dir)
  }
  if ($leaf -eq '_草稿') {
    $dir = [IO.Path]::GetDirectoryName($dir)
    if (-not $dir) { return '' }
    $leaf = [IO.Path]::GetFileName($dir)
  }
  return [string]$leaf
}

function Test-YaFileForbidden([string]$Path) {
  if (-not $Path) { return $false }
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $obj = Read-YaJsonFile $Path
    return (Test-YaValueForbidden -Value $obj -SkipId $true -SlotId (Get-YaEntrySlotId $Path))
  } catch {
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $slotId = Get-YaEntrySlotId $Path
    if ($slotId) { $text = $text.Replace('"' + $slotId + '"', '""') }
    return (Test-YaForbidden $text)
  }
}

function Test-YaStoredDirty([string]$SlotDir, [string]$Id) {
  $slotId = ''
  if ($SlotDir) { $slotId = [IO.Path]::GetFileName($SlotDir.TrimEnd('\')) }
  $formal = Get-YaFormalFile $SlotDir $Id
  if ($formal -and (Test-YaFileForbidden $formal)) { return $true }
  return (Test-YaIndexEntryDirty (Find-YaIndexEntry $SlotDir $Id) $slotId)
}

function Remove-YaIndexId([string]$SlotDir, [string]$Id) {
  if (-not (Test-Path -LiteralPath (Join-Path $SlotDir '索引.json'))) { return $false }
  $idx = Read-YaIndex $SlotDir
  $keep = New-Object System.Collections.Generic.List[object]
  $removed = $false
  foreach ($e in (Get-YaItems $idx.entries)) {
    if ([string]$e.id -eq $Id) { $removed = $true }
    else { [void]$keep.Add($e) }
  }
  if ($removed) { Write-YaIndex $SlotDir $idx.note $keep }
  return $removed
}

function Move-YaFormalBackToDraft([string]$SlotDir, [string]$Id) {
  $formal = Get-YaFormalFile $SlotDir $Id
  if (-not $formal) { throw '全文文件不在，没有改成草稿。' }
  if (Get-YaDraftFile $SlotDir $Id) { throw '草稿位置已经有同号文件，没有清出，索引也没改。' }
  $cat = '招式'
  try {
    $o = Read-YaJsonFile $formal
    $got = Get-YaTextProp $o 'c'
    if ($got -and $script:YaCatDir.ContainsKey($got)) { $cat = $got }
  } catch { }
  $catDir = [string]$script:YaCatDir[$cat]
  $folder = Join-Path (Join-Path $SlotDir '_草稿') $catDir
  if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
  $dest = Join-Path $folder ($Id + '.json')
  if (Test-Path -LiteralPath $dest) { throw '草稿位置已经有同号文件，没有清出，索引也没改。' }
  Move-Item -LiteralPath $formal -Destination $dest
  if (Test-Path -LiteralPath $formal) { throw '全文没有移回草稿。' }
  if (-not (Test-Path -LiteralPath $dest)) { throw '全文没有移回草稿。' }
  return $dest
}

function Rewrite-YaIndexFromFormal([string]$SlotDir, [string]$SlotId, [string]$Id) {
  $formal = Get-YaFormalFile $SlotDir $Id
  if (-not $formal) { throw '全文文件不在，不能按全文改回索引。' }
  $o = Read-YaJsonFile $formal
  $cat = Get-YaTextProp $o 'c'
  if (-not $script:YaCatDir.ContainsKey($cat)) { throw '全文类别不能识别，没有改索引。' }
  $catDir = Get-YaCatDirName $cat
  $title = Repair-YaLine (Get-YaTextProp $o 't')
  $mark = Repair-YaLine (Get-YaTextProp $o 'm')
  $keys = ConvertTo-YaKeywordList $o.k
  $tags = ConvertTo-YaKeywordList $o.tags
  $rel = $catDir + '/' + $Id + '.json'
  $u = 0
  $old = Find-YaIndexEntry $SlotDir $Id
  if ($null -ne $old) {
    $u = ConvertTo-YaUseCount (Get-YaTextProp $old 'u')
  }
  $entry = [ordered]@{
    id   = $Id
    c    = $cat
    t    = $title
    k    = $keys
    tags = $tags
    m    = $mark
    sw   = $SlotId
    v    = 1
    u    = $u
    f    = $rel
  }
  $idx = Read-YaIndex $SlotDir
  $keep = New-Object System.Collections.Generic.List[object]
  $replaced = $false
  foreach ($e in (Get-YaItems $idx.entries)) {
    if ([string]$e.id -eq $Id) {
      [void]$keep.Add($entry)
      $replaced = $true
    } else { [void]$keep.Add($e) }
  }
  if (-not $replaced) { [void]$keep.Add($entry) }
  Write-YaIndex $SlotDir $idx.note $keep
}

function Hold-YaDirtyEntry([string]$Lib, [string]$SlotArg, [string]$Id) {
  if (Test-YaReservedActive $Lib $SlotArg) { throw (Format-YaAllHold $Lib $Id) }
  $resolved = Resolve-YaSlot $Lib $SlotArg
  $id = Repair-YaLine $Id
  if (-not $id) { throw 'exp_hold 需要 id=条目号。' }
  if (-not (Test-YaEntryId $id)) { throw ('条目 id 不合法: ' + (Format-YaShownId $id)) }
  $formal = Get-YaFormalFile $resolved.dir $id
  $entry = Find-YaIndexEntry $resolved.dir $id
  $draft = Get-YaDraftFile $resolved.dir $id
  $hasFormal = ($null -ne $formal -and [string]$formal -ne '')
  $hasIndex = ($null -ne $entry)
  if (-not $hasFormal -and -not $hasIndex) {
    if ($draft) {
      throw ('这还是草稿，没有入库。草稿可以调取，用来改回再入库。请用 exp_get id=' + (Format-YaShownId $id) + ' slot=' + (Format-YaShownId $resolved.id) + '。要丢掉这份草稿用 exp_drop id=' + (Format-YaShownId $id) + ' slot=' + (Format-YaShownId $resolved.id) + '。')
    }
    throw (Format-YaMissingDraft $Lib $resolved.id $id 'exp_hold')
  }
  $fileDirty = $false
  if ($hasFormal) { $fileDirty = Test-YaFileForbidden $formal }
  $indexDirty = (Test-YaIndexEntryDirty $entry $resolved.id)
  if (-not $fileDirty -and -not $indexDirty) {
    throw '这条已入库，没有禁止写入的词，不能清出。干净的条目留在索引里。'
  }
  if ($fileDirty) {
    if ($draft) {
      $root = [IO.Path]::GetFullPath($resolved.dir).TrimEnd('\')
      $full = [IO.Path]::GetFullPath($formal)
      if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '全文不在这个槽里，没有清出。'
      }
      Remove-Item -LiteralPath $full -Force
      if (Test-Path -LiteralPath $full) { throw '全文没有清出。' }
      Remove-YaIndexId $resolved.dir $id | Out-Null
      Rebuild-YaTagIndex $Lib | Out-Null
      return @{
        slot    = $resolved.id
        id      = $id
        action  = 'hold'
        indexed = 'no'
        where   = 'draft'
        note    = '已从索引清出。同号草稿本来就在，没有覆盖。正文没有打出来。请把草稿改干净后再 exp_save verified=1。'
      }
    }
    Move-YaFormalBackToDraft $resolved.dir $id | Out-Null
    Remove-YaIndexId $resolved.dir $id | Out-Null
    Rebuild-YaTagIndex $Lib | Out-Null
    return @{
      slot    = $resolved.id
      id      = $id
      action  = 'hold'
      indexed = 'no'
      where   = 'draft'
      note    = '已从索引清出，改回草稿。正文没有打出来。请把草稿改干净后再 exp_save verified=1。'
    }
  }
  if ($hasFormal) {
    $formalObj = Read-YaJsonFile $formal
    $formalTitle = Repair-YaLine (Get-YaTextProp $formalObj 't')
    $formalMark = Repair-YaLine (Get-YaTextProp $formalObj 'm')
    $formalKeys = ConvertTo-YaKeywordList $formalObj.k
    $formalTags = ConvertTo-YaKeywordList $formalObj.tags
    if (-not $formalTitle) { throw '全文缺少一句话，不能按全文改回索引。没有改索引，正文没有打出来。' }
    try {
      Assert-YaExperienceLimits $formalTitle $formalMark $formalKeys $formalTags
    } catch {
      throw ($_.Exception.Message + '不能按全文改回索引。没有改索引，正文没有打出来。')
    }
    Rewrite-YaIndexFromFormal $resolved.dir $resolved.id $id
    Rebuild-YaTagIndex $Lib | Out-Null
    return @{
      slot    = $resolved.id
      id      = $id
      action  = 'repair'
      indexed = 'yes'
      where   = 'index'
      note    = '索引已按全文改回。原来的句子没有打出来。全文仍可调取。'
    }
  }
  Remove-YaIndexId $resolved.dir $id | Out-Null
  Rebuild-YaTagIndex $Lib | Out-Null
  $whereLeft = 'none'
  $noteLeft = '索引里的这条已清出。全文文件不在，没有改成草稿。'
  if ($draft) {
    $whereLeft = 'draft'
    $noteLeft = '索引里的这条已清出。全文文件不在。同号草稿还在，没有覆盖。'
  }
  return @{
    slot    = $resolved.id
    id      = $id
    action  = 'hold'
    indexed = 'no'
    where   = $whereLeft
    note    = $noteLeft
  }
}

function Remove-YaDraftOnly([string]$Lib, [string]$SlotArg, [string]$Id) {
  if (Test-YaReservedActive $Lib $SlotArg) { throw (Format-YaAllDrop $Lib $Id) }
  $resolved = Resolve-YaSlot $Lib $SlotArg
  $id = Repair-YaLine $Id
  if (-not $id) { throw 'exp_drop 需要 id=草稿号。' }
  if (-not (Test-YaEntryId $id)) { throw ('条目 id 不合法: ' + (Format-YaShownId $id)) }
  if (Test-YaIndexedHere $resolved.dir $id) {
    if (Test-YaStoredDirty $resolved.dir $id) {
      throw ('这份已经在这个槽的索引里，不能用 exp_drop 丢掉。它含禁止写入的词。请用 exp_hold id=' + (Format-YaShownId $id) + ' slot=' + (Format-YaShownId $resolved.id) + ' 清出索引，改回草稿后再改。已入库的干净条目留着。')
    }
    throw ('这份已经在这个槽的索引里，不能用 exp_drop 丢掉。已入库的条目留着。exp_drop 只丢掉还没入库的草稿。drop=1 只用来清掉误建的 all，不能用来删普通槽。')
  }
  $draft = Get-YaDraftFile $resolved.dir $id
  if (-not $draft) { throw (Format-YaMissingDraft $Lib $resolved.id $id 'exp_drop') }
  $root = [IO.Path]::GetFullPath((Join-Path $resolved.dir '_草稿')).TrimEnd('\')
  $full = [IO.Path]::GetFullPath($draft)
  if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '这份不在草稿目录里，没有删。'
  }
  Remove-Item -LiteralPath $full -Force
  if (Test-Path -LiteralPath $full) { throw '草稿没有删掉。' }
  return @{ id = $id; slot = $resolved.id; path = $full }
}

function Remove-YaSlot {
  param(
    [string]$Lib,
    [string]$Id,
    [string]$To = '',
    [bool]$Drop = $false
  )
  $to = Repair-YaLine $To
  if ((Repair-YaLine $Id) -eq 'generic') { throw 'generic 是底槽，不删除。' }
  $reservedAsk = Test-YaCrossSlotWord $Id
  if ($to -and -not $reservedAsk) { throw 'to= 只用来把误建的 all 迁到具体槽。普通槽请不要带 to=。' }
  if ($Drop -and -not $reservedAsk) { throw 'drop=1 只用来清掉误建的 all 槽。普通槽有条目时不会删。' }
  if ($to -and $Drop) { throw 'to= 和 drop=1 只能选一个。迁走用 to=，不要了用 drop=1。' }
  if ($reservedAsk) { return (Remove-YaReservedSlot $Lib $to $Drop) }
  if (-not (Test-YaSlotId $Id)) { throw ('槽 id 不合法: ' + (Format-YaShownId $Id)) }
  $cfg = Read-YaSlots $Lib
  $found = $null
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if ([string]$s.id -eq $Id) { $found = $s } else { [void]$list.Add($s) }
  }
  if (-not $found) { throw ('没有这个槽: ' + (Format-YaShownId $Id)) }
  if ($list.Count -eq 0) { throw '至少留一个槽。' }
  $dir = Get-YaSlotDir $Lib $found
  if (Test-Path -LiteralPath $dir) {
    $idx = Read-YaIndex $dir
    $entries = (Get-YaItems $idx.entries).Count
    $draftIds = Get-YaItems (Get-YaDraftIdList $dir)
    $drafts = $draftIds.Count
    $jsons = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter *.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '索引.json' })
    $other = $jsons.Count - $drafts
    if ($other -lt 0) { $other = 0 }
    if ($entries -gt 0 -or $drafts -gt 0 -or $jsons.Count -gt 0) {
      throw (Format-YaSlotKeep $Id $entries $drafts $draftIds $other)
    }
    Remove-Item -LiteralPath $dir -Recurse -Force
  }
  $cfg.slots = $list.ToArray()
  if ((Get-YaTextProp $cfg 'active') -eq $Id) { $cfg.active = 'generic' }
  Write-YaSlots $Lib $cfg
  Rebuild-YaTagIndex $Lib | Out-Null
  $usageCleared = Remove-YaUsageSlot $Lib ([string]$found.id)
  return @{
    id              = [string]$found.id
    reserved        = $false
    to              = ''
    moved_entries   = 0
    moved_drafts    = 0
    dropped         = $false
    dropped_entries = 0
    dropped_drafts  = 0
    usage_cleared   = [bool]$usageCleared
  }
}

function Set-YaActiveSlot([string]$Lib, [string]$Id) {
  if (Test-YaCrossSlotWord $Id) { throw 'all 只能用来跨槽检索，不能设成当前槽。请写 slot_use id=具体槽。具体槽用 slot_list 看，不要把 all 当成槽。' }
  $cfg = Read-YaSlots $Lib
  $found = $null
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if ([string]$s.id -eq $Id) { $found = $s; break }
  }
  if (-not $found) { throw ('没有这个槽: ' + (Format-YaShownId $Id)) }
  $cfg.active = $Id
  Write-YaSlots $Lib $cfg
  Initialize-YaSlot $Lib $found | Out-Null
}

function Get-YaCounts([string]$SlotDir) {
  $idx = Read-YaIndex $SlotDir
  $drafts = 0
  $draftRoot = Join-Path $SlotDir '_草稿'
  if (Test-Path -LiteralPath $draftRoot) {
    $drafts = @(Get-ChildItem -LiteralPath $draftRoot -Recurse -Filter *.json -File -ErrorAction SilentlyContinue).Count
  }
  return @{ entries = (Get-YaItems $idx.entries).Count; drafts = $drafts }
}

function Get-YaTagList($Entry) {
  $list = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  $sources = New-Object System.Collections.Generic.List[object]
  [void]$sources.Add($Entry.tags)
  [void]$sources.Add($Entry.k)
  foreach ($source in $sources) {
    foreach ($one in (ConvertTo-YaKeywordList $source)) {
      $key = $one.ToLowerInvariant()
      if ($seen.ContainsKey($key)) { continue }
      $seen[$key] = $true
      [void]$list.Add($one)
    }
  }
  return ,$list
}

function Test-YaHasTag($Entry, [string]$Tag) {
  $want = (Repair-YaLine $Tag)
  if (-not $want) { return $true }
  $key = $want.ToLowerInvariant()
  foreach ($one in (Get-YaTagList $Entry)) {
    if ($one.ToLowerInvariant() -eq $key) { return $true }
  }
  return $false
}

function Rebuild-YaTagIndex([string]$Lib) {
  $cfg = Read-YaSlots $Lib
  $map = @{}
  foreach ($s in (Get-YaItems $cfg.slots)) {
    if (Test-YaCrossSlotWord ([string]$s.id)) { continue }
    $dir = Get-YaSlotDir $Lib $s
    if (-not (Test-Path -LiteralPath (Join-Path $dir '索引.json'))) { continue }
    $idx = Read-YaIndex $dir
    foreach ($e in (Get-YaItems $idx.entries)) {
      foreach ($tag in (Get-YaTagList $e)) {
        $key = $tag.ToLowerInvariant()
        if (-not $map.ContainsKey($key)) {
          $map[$key] = @{ tag = $tag; refs = (New-Object System.Collections.Generic.List[object]) }
        }
        [void]$map[$key].refs.Add([ordered]@{ slot = [string]$s.id; id = [string]$e.id })
      }
    }
  }
  $tags = New-Object System.Collections.Generic.List[object]
  foreach ($key in @($map.Keys | Sort-Object)) {
    [void]$tags.Add([ordered]@{ tag = [string]$map[$key].tag; refs = $map[$key].refs })
  }
  $doc = [ordered]@{
    version = 1
    '说明'  = '任务标签倒排。条目仍按软件槽分文件存放。检索先定槽，再用标签收窄。'
    tags    = $tags
  }
  Write-YaJsonFile (Join-Path $Lib '任务标签.json') $doc
  return $doc
}

function Search-YaDual {
  param([string]$Lib, [string]$SlotId, [string]$Query, [string]$Tag)
  $query = Repair-YaLine $Query
  $tag = Repair-YaLine $Tag
  if (-not $query -and -not $tag) {
    throw '检索要写 q=关键词 或 tag=标签。空检索不会打开写入闸，也不列出整槽。'
  }
  Assert-YaClean $query
  Assert-YaClean $tag
  Rebuild-YaTagIndex $Lib | Out-Null
  $chosen = New-Object System.Collections.Generic.List[object]
  if (Test-YaCrossSlotWord $SlotId) {
    $cfg = Read-YaSlots $Lib
    foreach ($s in (Get-YaItems $cfg.slots)) {
      if (Test-YaCrossSlotWord ([string]$s.id)) { continue }
      $dir = Initialize-YaSlot $Lib $s
      [void]$chosen.Add(@{ id = [string]$s.id; dir = $dir })
    }
  } else {
    $resolved = Resolve-YaSlot $Lib $SlotId
    [void]$chosen.Add(@{ id = $resolved.id; dir = $resolved.dir })
  }
  $hits = New-Object System.Collections.Generic.List[object]
  foreach ($s in $chosen) {
    $idx = Read-YaIndex $s.dir
    $found = Search-YaEntries $idx.entries $query
    foreach ($e in (Get-YaItems $found)) {
      if (-not (Test-YaHasTag $e $tag)) { continue }
      [void]$hits.Add(@{ slot = [string]$s.id; entry = $e })
    }
  }
  return ,$hits
}
