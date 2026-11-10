# 经验分存（跨软件通用，所有机械软件同一套，不绑任何一款）：连上软件时自动建该软件的专属经验夹；做完任务把经验按「专属 / 通用」分流存。
# 在本包根目录：
#   确保专属夹（ya_link.ps1 连接成功时自动调，人不用手建）：
#     powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接教练\连接经验\经验分存.ps1" ensure soft=软件名 [slot=槽id]
#   只搜「本软件专属 + 通用」（只读，不整库通搜，别的软件槽不读）：
#     ... 经验分存.ps1 find q=关键词 [slot=槽id]（不写 slot= 就用当前已核对连接的槽；登记还在但窗口不可见、进程不在、未响应、进程号读不了、槽号对不上本包的槽，都不算；只是大小写不同则用那个槽。slot= 只能是一个槽号，不能写路径。max= 只收 1 到 50）
#   看分流去向和条数（只读）：
#     ... 经验分存.ps1 where [slot=槽id]
#   存本软件做法（专属）：先 task_open + exp_recall 过检索闸，再
#     ... 经验分存.ps1 save scope=专属 [slot=槽id] c=招式|坑|零件方案 t=一句话 'k=G-MODEL-004,关键词' tag=任务标签 [m=报错特征]
#   存跨软件通法（通用，候选 v=0）：
#     ... 经验分存.ps1 save scope=通用 cat=03 t=一句话 general=通法 trigger=触发 verify=怎么核 exception=异常怎么办 keep=沉淀什么 [precond=] [risk=快检|标准|严格] [k=词1,词2] [from=来源草稿号]
# 专属夹 = 经验库\槽\<槽id>\（招式库/坑库/零件方案库/_草稿/索引.json，由运行时 Add-YaSlot 建，结构与 generic 母槽一致）
#        + 连接教练\连接经验\<槽id>\（这款软件的连接卡和附件）。两处同一个槽 id，不新建一级目录。
# 槽 id：给了 slot= 就用它（小写）；没给就先找槽位.json 里标题等于软件名的槽；再没有就用软件名转小写英文数字（SW→sw，NX→nx）；名字里有中文等非英文字符（含「中望3D」这种混写）用 app-<8位哈希>；转出来的 id 已被另一款软件占了就加哈希尾，再撞就从原 id 加长，绝不并进别人的槽。显式 slot= 若标题已是另一款软件（同时写了 soft=），改按软件名定槽。软件原名一律存在槽标题里。
#        generic / all 不能当软件专属槽：连上软件一律落到它自己的槽。find / where 写 slot=all 都拒绝整库通搜。不写 slot= 时，连接登记没核对通过就只搜通用，不把残留 slot 当当前软件。没有已核对连接、或窗口在但槽号对不上时，save scope=专属 都不新建槽。草稿没写成时，这次新建的空槽会收回。通法的关键词、来源和编号也查禁止词。find 已入库又含禁止词的正式条目不列出，草稿仍列出。条目上读不了的调用次数按 0。ensure 说明里不合规的槽号不回显。通用正式条目的 id 若是禁止词，命中行写「没有列出来」。草稿的一句话里有禁止词也不打出来。
# 测试包（包目录名含「副本」「测试」）：ensure 照常自动建夹（维护者 2026-11-05 定规：正式包、测试包都要有）；save 默认拒绝，除非本轮测试明确允许存经验并加 allow_test=1。
# 不改冻结运行时：只调用 安装卸载\运行时 里已有的函数；专属存经验走本包自己的 ya.ps1 exp_done（检索闸、禁词、草稿规则全照旧）。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try {
  $cmd = ''
  $map = @{}
  foreach ($kv in @($Rest)) {
    if (-not $kv) { continue }
    $i = $kv.IndexOf('=')
    if ($i -lt 1) {
      if (-not $cmd) { $cmd = $kv.Trim(); continue }
      $shown = [string]$kv
      if (($shown -match '(?i)破解|注册机|盗版|keygen|\bcrack\b') -or ($shown -match '[\\/]') -or ($shown.Contains('..'))) { $shown = '没有列出来' }
      throw ('参数要写成 名字=值 ：' + $shown)
    }
    $map[$kv.Substring(0, $i).Trim()] = $kv.Substring($i + 1).Trim().Trim('"')
  }
  function A([string]$n) { if ($map.ContainsKey($n)) { return [string]$map[$n] } return '' }
  if (-not $cmd) { throw '要写子命令：ensure / find / where / save' }

  $here = $PSScriptRoot
  $pkg = Split-Path (Split-Path $here -Parent) -Parent
  . (Join-Path $pkg 'YA插件\连接上下文.ps1')
  $runtime = Join-Path $pkg '安装卸载\运行时'
  . (Join-Path $runtime 'ya_slots.ps1')
  . (Join-Path $runtime 'ya_flow.ps1')
  $lib = Initialize-YaLibrary $pkg
  $isTestPkg = (Split-Path $pkg -Leaf) -match '副本|测试|(?i)test|copy'

  function Get-HudIo {
    $h = Get-YaPackageHudHome $pkg
    return (Join-Path $h 'io')
  }
  function Get-LinkInfo {
    $p = Join-Path (Get-HudIo) 'link.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return (Read-YaJsonFile $p) } catch { return $null }
  }
  function ConvertTo-SlotId([string]$Soft) {
    # 名字里有中文等非英文字符：不拿残留的英文数字凑 id（「中望3D」不能变成 app-3d），一律 app-<8位哈希>；软件原名留在槽标题里
    if (([string]$Soft).Trim() -match '[^\x00-\x7F]') { $s = '' } else {
    $s = ([string]$Soft).Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9_-]+', '-')
    $s = [regex]::Replace($s, '-{2,}', '-').Trim('-', '_')
    if ($s -and $s -notmatch '^[a-z]') { $s = 'app-' + $s }
    if ($s.Length -gt 32) { $s = $s.Substring(0, 32).Trim('-', '_') }
    }
    if (-not $s -or -not (Test-YaSlotId $s) -or $s -eq 'generic' -or $s -eq 'all') {
      $sha = [Security.Cryptography.SHA1]::Create()
      $hex = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$Soft)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') })
      $s = 'app-' + $hex
    }
    return $s
  }
  # 专属夹：找到或自动建。返回 @{ id; title; dir; conn; created }
  function Ensure-SoftSlot([string]$Soft, [string]$SlotArg, [bool]$AllowCreate = $true) {
    $cfg = Read-YaSlots $lib
    $slots = Get-YaItems $cfg.slots
    $id = ([string]$SlotArg).Trim().ToLowerInvariant()
    $why = ''
    if ($id -eq 'generic' -or $id -eq 'all') { $why = $id + ' 不是软件专属槽，改按软件名定槽'; $id = '' }
    if ($id -and -not (Test-YaSlotId $id)) { $why = 'slot=' + (Show-ArgEcho $SlotArg) + ' 不合规，改按软件名定槽'; $id = '' }
    if ($id -and $Soft) {
      foreach ($s in $slots) {
        if ([string]$s.id -eq $id -and ([string]$s.title).Trim().ToLowerInvariant() -ne $Soft.Trim().ToLowerInvariant()) {
          throw ('SLOT_NAME_CONFLICT: 指定槽已有软件名称；请使用槽中登记的名称，核对别名后再连接。没有创建其他槽。')
        }
      }
    }
    if (-not $id) {
      if (-not $Soft) { throw '要写 soft=软件名 或 slot=槽id。' }
      foreach ($s in $slots) { if ([string]$s.id -ne 'generic' -and ([string]$s.title).Trim().ToLowerInvariant() -eq $Soft.Trim().ToLowerInvariant()) { $id = [string]$s.id; break } }
      if (-not $id) {
        $id = ConvertTo-SlotId $Soft
        $root = $id
        $sha = [Security.Cryptography.SHA1]::Create()
        $full = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Soft)) | ForEach-Object { $_.ToString('x2') })
        # 转出来的 id 已被另一款软件（标题不同）占了：从原 id 加哈希尾，再撞就加长。绝不并进别人的槽。
        for ($round = 0; $round -lt 4; $round++) {
          $taken = $false
          foreach ($s in $slots) {
            if ([string]$s.id -eq $id -and ([string]$s.title).Trim().ToLowerInvariant() -ne $Soft.Trim().ToLowerInvariant()) { $taken = $true; break }
          }
          if (-not $taken) { break }
          $nbytes = 2 + $round
          if (($nbytes * 2) -gt $full.Length) { break }
          $hx = $full.Substring(0, $nbytes * 2)
          $base = $root
          $room = 32 - 1 - $hx.Length
          if ($room -lt 1) { break }
          if ($base.Length -gt $room) { $base = $base.Substring(0, $room) }
          $id = $base + '-' + $hx
        }
        $still = $false
        foreach ($s in $slots) {
          if ([string]$s.id -eq $id -and ([string]$s.title).Trim().ToLowerInvariant() -ne $Soft.Trim().ToLowerInvariant()) { $still = $true; break }
        }
        if ($still -or -not (Test-YaSlotId $id)) { throw '自动槽 id 和已有软件撞了太多次，没有并进别人的槽。' }
      }
    }
    $found = $null
    foreach ($s in $slots) { if ([string]$s.id -eq $id) { $found = $s; break } }
    $created = $false
    if (-not $found) {
      if (-not $AllowCreate) { throw '没有已核对的连接，不能新建专属槽。请写已经有的 slot=，或先连上软件。没有写入。' }
      $title = $Soft; if (-not $title) { $title = $id }
      Add-YaSlot $lib $id $title '连接软件时自动建的专属经验槽（经验分存.ps1 ensure）' $false
      $created = $true
    }
    $r = Resolve-YaSlot $lib $id
    $conn = Join-Path $here $id
    $connNew = $false
    if (-not (Test-Path -LiteralPath $conn)) { New-Item -ItemType Directory -Path $conn | Out-Null; $connNew = $true }
    return @{ id = $id; title = [string]$r.slot.title; dir = [string]$r.dir; conn = $conn; created = $created; connNew = $connNew; why = $why }
  }
  function Get-SlotFromLink {
    $L = Get-LinkInfo
    if (-not $L) { return $null }
    $gateLink = [YaEvidence]::Read((Join-Path (Get-HudIo) 'link.json'))
    if ([YaEvidence]::CheckRegistered($pkg, (Get-HudIo), $gateLink)) { return $null }
    if ([string](Get-YaTextProp $L 'state') -ne 'ok') { return $null }
    $pidNum = ConvertTo-YaPid ([string](Get-YaTextProp $L 'pid'))
    if (-not (Test-YaForegroundPid $pidNum)) { return $null }
    $s = Resolve-YaRegisteredSlot $lib ([string](Get-YaTextProp $L 'slot'))
    return @{ slot = $s; soft = [string](Get-YaTextProp $L 'soft') }
  }
  function Show-ArgEcho([string]$Text) {
    $t = [string]$Text
    if ((Test-YaForbidden $t) -or ($t -match '[\\/]') -or ($t.Contains('..'))) { return '没有列出来' }
    return $t
  }
  function Show-Slot([string]$Id) { return (Format-YaShownId $Id) }
  function Show-OutPath([string]$Text) {
    if (Test-YaForbidden ([string]$Text)) { return '没有列出来' }
    return [string]$Text
  }
  function Assert-OneSlotArg([string]$Id) {
    if (-not $Id -or $Id -eq 'all' -or $Id -eq 'generic') { return }
    if (-not (Test-YaSlotId $Id)) { throw 'slot= 不合规。只写本包里的一个软件槽，不能写路径，也不能整库通搜。' }
  }
  function Count-Slot([string]$Dir) {
    $c = Get-YaCounts $Dir
    return ('正式 ' + $c.entries + ' 条 · 草稿 ' + $c.drafts + ' 条')
  }
  $skillLib = Join-Path $lib '通用技能库'

  if ($cmd -eq 'ensure') {
    $soft = A 'soft'
    $e = Ensure-SoftSlot $soft (A 'slot')
    Write-Output ('slot: ' + (Show-Slot $e.id) + '  title=' + (Format-YaShown $e.title))
    Write-Output ('exp_dir: ' + (Show-OutPath $e.dir) + $(if ($e.created) { '  （新建：连接时自动建）' } else { '  （已有）' }))
    Write-Output ('conn_dir: ' + (Show-OutPath $e.conn) + $(if ($e.connNew) { '  （新建）' } else { '  （已有）' }))
    Write-Output ('count: ' + (Count-Slot $e.dir))
    if ($e.why) { Write-Output ('note: ' + $e.why) }
    Write-Output 'route: 本软件做法 → 这个专属槽；跨软件通法 → 经验库\通用技能库（候选 v=0）。开槽≠已挂。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($cmd -eq 'where') {
    $slot = (A 'slot').ToLowerInvariant()
    $li = $null
    if (-not $slot) { $li = Get-SlotFromLink; if ($li) { $slot = $li.slot } }
    if ($slot -eq 'all') { throw 'where 不做整库通搜。要看某一软件写 slot=该槽；跨槽看用 ya.ps1 exp_search slot=all。' }
    Assert-OneSlotArg $slot
    if ($slot -and $slot -ne 'generic') {
      try { $r = Resolve-YaSlot $lib $slot; Write-Output ('专属: ' + (Show-OutPath ([string]$r.dir)) + '  ' + (Count-Slot $r.dir)) } catch { Write-Output ('专属: 还没有槽 ' + (Show-Slot $slot) + '（连上软件时 ya_link 会自动建）') }
      Write-Output ('专属连接卡: ' + (Show-OutPath (Join-Path $here $slot)))
    } elseif ($li -and -not $slot) { Write-Output '专属: 当前没有已核对的连接（登记的槽对不上本包里的软件槽）' }
    else { Write-Output '专属: 当前没有已核对的连接（未连接、窗口不可见、进程不在，或 link.json 不是 ok）' }
    $g = Resolve-YaSlot $lib 'generic'
    $gi = 0; try { $gi = [int](Read-YaJsonFile (Join-Path $skillLib '索引.json')).total } catch { }
    Write-Output ('通用候选: ' + $skillLib + '  ' + $gi + ' 张（v=0）')
    Write-Output ('通用正式: ' + $g.dir + '  ' + (Count-Slot $g.dir))
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($cmd -eq 'find') {
    # 只读检索：只搜「当前软件专属 + 通用」两处，不整库通搜（别的软件槽一律不读，为的是快、也不串用）
    $q = (A 'q'); if (-not $q) { throw '要写 q=关键词（空格分开，全都要命中）' }
    $terms = @($q -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $max = 8
    $rawMax = A 'max'
    if ($rawMax) {
      $n64 = [int64]0
      if (-not [int64]::TryParse($rawMax, [ref]$n64) -or $n64 -lt 1 -or $n64 -gt 50) { throw 'max= 要是 1 到 50 的整数。' }
      $max = [int]$n64
    }
    $slot = (A 'slot').ToLowerInvariant()
    $li = $null
    if (-not $slot) { $li = Get-SlotFromLink; if ($li) { $slot = $li.slot } }
    if ($slot -eq 'all') { throw 'find 不做整库通搜；要跨槽看用 ya.ps1 exp_search slot=all。' }
    Assert-OneSlotArg $slot
    function Hit([string]$Text) { $x = $Text.ToLowerInvariant(); foreach ($t in $terms) { if (-not $x.Contains($t)) { return $false } }; return $true }
    $total = 0
    $skipped = 0
    if ($slot -and $slot -ne 'generic') {
      $sd = Join-Path $lib ('槽\' + $slot)
      if (Test-Path -LiteralPath $sd) {
        $n = 0
        foreach ($en in @((Read-YaJsonFile (Join-Path $sd '索引.json')).entries)) {
          if ($null -eq $en) { continue }
          $line = ConvertTo-Json -InputObject $en -Compress -Depth 4
          if (-not (Hit $line)) { continue }
          if (Test-YaIndexContentDirty $en $slot) { $skipped++; continue }
          $recordFile=Get-YaFormalFile $sd ([string]$en.id)
          if(-not $recordFile -or (Read-YaJsonFile $recordFile).lifecycle -eq 'withdrawn'){continue}
          $n++
          if ($n -le $max) { Write-Output ('专属记录（需核对版本与证据） ' + (Show-Slot ([string]$en.id)) + ' ' + (Format-YaShown ([string]$en.t)) + '  get: ya.ps1 exp_get id=' + (Show-Slot ([string]$en.id)) + ' slot=' + (Show-Slot $slot)) }
        }
        foreach ($df in @(Get-ChildItem -LiteralPath (Join-Path $sd '_草稿') -Recurse -Filter *.json -File -ErrorAction SilentlyContinue)) { $txt = [IO.File]::ReadAllText($df.FullName, [Text.Encoding]::UTF8); if (Hit $txt) { $n++; if ($n -le $max) { $o = $null; try { $o = $txt | ConvertFrom-Json } catch { $o = $null }; $shownT = ''; if ($null -ne $o) { $shownT = Format-YaShown ([string]$o.t) }; Write-Output ('专属草稿 ' + (Show-Slot $df.BaseName) + ' ' + $shownT + '  （v=0 未验证，照做也要读回核对）  file: ' + (Show-OutPath ($df.FullName.Substring($pkg.Length + 1)))) } } }
        Write-Output ('hits_专属: ' + $n)
        $total += $n
      } else { Write-Output ('hits_专属: 0（还没有槽 ' + (Show-Slot $slot) + '，连上软件时会自动建）') }
      $cn = 0
      $ci = Join-Path $here '索引.json'
      if (Test-Path -LiteralPath $ci) {
        foreach ($en in @((Read-YaJsonFile $ci).entries)) {
          if ($null -eq $en) { continue }
          if (([string]$en.slot).ToLowerInvariant() -ne $slot) { continue }
          $line = ConvertTo-Json -InputObject $en -Compress -Depth 4
          if (-not (Hit $line)) { continue }
          if (Test-YaIndexContentDirty $en $slot) { $skipped++; continue }
          $cn++
          if ($cn -le $max) { Write-Output ('专属连接卡 ' + (Show-Slot ([string]$en.id)) + ' v=' + [string]$en.v + '  file: ' + (Show-OutPath ([string]$en.f))) }
        }
      }
      Write-Output ('hits_专属连接卡: ' + $cn)
      $total += $cn
    } elseif ($li -and -not $slot) { Write-Output 'hits_专属: 未指定软件槽（登记的槽对不上，只搜通用）' }
    else { Write-Output 'hits_专属: 未指定软件槽（没连软件时只搜通用）' }
    $gn = 0
    $gd = Join-Path $lib '槽\generic'
    if($slot -eq 'generic'){foreach ($en in @((Read-YaJsonFile (Join-Path $gd '索引.json')).entries)) {
      if ($null -eq $en) { continue }
      $line = ConvertTo-Json -InputObject $en -Compress -Depth 4
      if (-not (Hit $line)) { continue }
      if (Test-YaIndexContentDirty $en 'generic') { $skipped++; continue }
      $gn++
      if ($gn -le $max) { Write-Output ('未指定软件的记录 ' + (Show-Slot ([string]$en.id)) + ' ' + (Format-YaShown ([string]$en.t))) }
    }}
    foreach ($l in [IO.File]::ReadAllLines((Join-Path $skillLib '索引.json'), [Text.Encoding]::UTF8)) {
      if (-not $l.StartsWith('{"id"')) { continue }
      if (-not (Hit $l)) { continue }
      $o = $l.TrimEnd(',') | ConvertFrom-Json
      if (Test-YaIndexContentDirty $o 'generic') { $skipped++; continue }
      $gn++
      if ($gn -le $max) { Write-Output ('通用候选 ' + (Show-Slot ([string]$o.id)) + ' ' + (Format-YaShown ([string]$o.t)) + '  file: ' + (Show-OutPath ('经验库\通用技能库\' + ([string]$o.f).Replace('/', '\')))) }
    }
    Write-Output ('hits_通用: ' + $gn)
    $total += $gn
    $others = 0; $allSlots = Get-YaItems (Read-YaSlots $lib).slots; foreach ($s in $allSlots) { if ([string]$s.id -ne 'generic' -and [string]$s.id -ne $slot) { $others++ } }
    Write-Output ('scope: 专属 ' + $(if ($slot -and $slot -ne 'generic') { Show-Slot $slot } else { '(无)' }) + ' + 通用知识候选；没读其他软件槽 ' + $others + ' 个（不整库通搜）')
    if ($skipped -gt 0) { Write-Output ('note: 有 ' + $skipped + ' 条含禁止写入的词，没有列出来。') }
    Write-Output ('hits: ' + $total)
    Write-Output 'note: 只读，不记调用、不开检索闸；要写草稿仍须 ya.ps1 task_open + exp_recall slot=<本槽>。'
    Write-Output 'RESULT: OK'
    exit 0
  }

  if ($cmd -eq 'save') {
    if ($isTestPkg -and (A 'allow_test') -ne '1') { throw '这是测试包：本轮默认不改包内经验。测试方案明确允许存经验时才加 allow_test=1。' }
    $scope = A 'scope'
    if ($scope -in @('专属', 'own', 'slot')) {
      $slot = (A 'slot').ToLowerInvariant(); $soft = A 'soft'
      if ($slot) { Assert-OneSlotArg $slot }
      $linked = Get-SlotFromLink
      if (-not $slot) { if ($linked) { $slot = [string]$linked.slot; if (-not $soft) { $soft = [string]$linked.soft } } }
      if (-not $slot -and -not $soft) { throw '没有已连接的软件槽：写 slot=槽id，或先连上软件（ya_link 会自动建专属槽）。' }
      if ($slot -eq 'generic' -or $slot -eq 'all') { throw '专属经验不能写进 generic/all。本软件做法写本软件的槽；跨软件通法用 scope=通用。' }
      $allowNew = $false
      if ($null -ne $linked -and [string]$linked.slot) { $allowNew = $true }
      $e = Ensure-SoftSlot $soft $slot $allowNew
      $ya = Join-Path $pkg 'YA插件\本包命令.ps1'
      $pass = New-Object System.Collections.Generic.List[string]
      [void]$pass.Add('exp_done')
      foreach ($n in @('c', 't', 'k', 'tag', 'm')) { if ($map.ContainsKey($n)) { [void]$pass.Add($n + '=' + $map[$n]) } }
      [void]$pass.Add('slot=' + $e.id)
      $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ya @pass 2>&1 | Out-String
      Write-Output ('route: 专属 → ' + (Show-OutPath $e.dir))
      $okSave = $out -match 'RESULT: OK'
      Write-Output ((($out.TrimEnd() -split "`r?`n") | Where-Object { $_ -notmatch '^RESULT:' }) -join "`r`n")
      if (-not $okSave) {
        if ($e.created) {
          $rolled = $false
          try { Remove-YaSlot $lib $e.id | Out-Null; $rolled = $true } catch { }
          if ($e.connNew -and $e.conn -and (Test-Path -LiteralPath $e.conn)) {
            $leftConn = @(Get-ChildItem -LiteralPath $e.conn -Force -ErrorAction SilentlyContinue)
            if ($leftConn.Count -eq 0) { Remove-Item -LiteralPath $e.conn -Force -ErrorAction SilentlyContinue }
          }
          if ($rolled) { Write-Output 'note: 草稿没写成，这次新建的空槽已收回。' }
        }
        Write-Output 'RESULT: FAIL'
        exit 1
      }
      if ($okSave) { Write-Output ('count: ' + (Count-Slot $e.dir)); Write-Output ('note: 这是草稿（v=0）。在本软件里核对过才 exp_save id=草稿号 verified=1 slot=' + (Show-Slot $e.id)); Write-Output 'RESULT: OK'; exit 0 }
      exit 1
    }
    if ($scope -in @('通用', 'generic', 'common')) {
      $cat = A 'cat'
      if (-not $cat) { throw '通用要写 cat=类别（两位号如 03，或类夹名/类名）。' }
      $dirs = @(Get-ChildItem -LiteralPath $skillLib -Directory | Where-Object { $_.Name -match '^\d\d_' -and $_.Name -ne '00_索引' })
      $d = @($dirs | Where-Object { $_.Name -eq $cat -or $_.Name.Substring(0, 2) -eq $cat -or $_.Name.Substring(3) -eq $cat })
      if ($d.Count -ne 1) { throw ('找不到类别 ' + (Show-ArgEcho $cat) + '。可选：' + (($dirs | ForEach-Object { $_.Name }) -join ' ')) }
      $d = $d[0]
      $codes = @{}
      $maxNo = @{}
      foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter 'G-*.json' -File)) {
        $m = [regex]::Match($f.BaseName, '^G-([A-Z]+)-(\d{3})$')
        if ($m.Success) { $k0 = $m.Groups[1].Value; $codes[$k0] = 1 + [int]$codes[$k0]; $n0 = [int]$m.Groups[2].Value; if ($n0 -gt [int]$maxNo[$k0]) { $maxNo[$k0] = $n0 } }
      }
      $code = A 'code'
      if (-not $code) { if ($codes.Count -eq 0) { throw '这一类还没有字母编号，写 code=类别码。' }; $code = @($codes.GetEnumerator() | Sort-Object Value -Descending)[0].Key }
      if ($code -notmatch '^[A-Z]{2,12}$') { throw 'code= 要大写字母。' }
      $newId = 'G-' + $code + '-' + ('{0:d3}' -f ([int]$maxNo[$code] + 1))
      $catName = $d.Name.Substring(3)
      $t = Repair-YaLine (A 't')
      $fields = [ordered]@{ general = (A 'general'); trigger = (A 'trigger'); verify = (A 'verify'); exception = (A 'exception'); keep = (A 'keep') }
      if (-not $t) { throw '要写 t=一句话。' }
      foreach ($n in $fields.Keys) { if ([string]::IsNullOrWhiteSpace($fields[$n])) { throw ('通法五要素缺 ' + $n + '=（trigger/general/verify/exception/keep 都要写）。') } }
      $precond = A 'precond'
      $risk = A 'risk'; if (-not $risk) { $risk = '标准' }
      if ($risk -notin @('快检', '标准', '严格')) { throw 'risk= 只能是 快检/标准/严格。' }
      $allText = @($t, $precond) + @($fields.Values)
      # 通法不点名软件：槽位里各软件槽的 id/标题、当前连接的软件名都不能出现；也不写路径和程序文件
      $names = New-Object System.Collections.Generic.List[string]
      $allSlots = Get-YaItems (Read-YaSlots $lib).slots
      foreach ($s in $allSlots) { if ([string]$s.id -ne 'generic') { foreach ($w in @([string]$s.id, [string]$s.title)) { if ($w.Length -ge 2) { [void]$names.Add($w) } } } }
      $li = Get-LinkInfo; if ($li) { $sw = [string](Get-YaTextProp $li 'soft'); if ($sw.Length -ge 2) { [void]$names.Add($sw) } }
      foreach ($x in $allText) {
        if (Test-YaForbidden $x) { throw '禁止写入侵权或不合法连接相关内容。' }
        foreach ($w in $names) { if ($x.ToLowerInvariant().Contains($w.ToLowerInvariant())) { throw ('通法里出现了软件名/槽名「' + (Format-YaShown ([string]$w)) + '」：去掉软件菜单、接口、名字再存通用；只在这款软件成立的写 scope=专属。') } }
        if ($x -match '(?i)[a-z]:\\|\\\\|\.(exe|dll|bat|ps1|py|cs)\b') { throw '通法里不写路径和程序文件；那是专属做法或证据附件。' }
      }
      $idx = Read-YaJsonFile (Join-Path $skillLib '索引.json')
      foreach ($en in @($idx.entries)) { if ([string]$en.t -eq $t) { throw ('通用库已有同题卡 ' + [string]$en.id + '：补适用条件或写修订候选，不重复建。') } }
      $keys = New-Object System.Collections.Generic.List[string]
      foreach ($w in @($newId, $t, $catName) + @(Split-YaCommaList (A 'k')) + @('通法')) { $w = Repair-YaLine ([string]$w); if ($w -and -not $keys.Contains($w) -and $keys.Count -lt 12) { if ($w.Length -gt 40) { $w = $w.Substring(0, 40) }; [void]$keys.Add($w) } }
      $from = A 'from'
      if ($from -and -not (Test-YaEntryId $from)) { throw 'from= 只写来源草稿号/条目号（如 D20261105...），不写软件名。' }
      $src = '任务沉淀（' + (Get-Date).ToString('yyyy-MM-dd') + '，经验分存.ps1 save scope=通用）' + $(if ($from) { '，来源条目 ' + $from } else { '' }) + '；未在多款软件验证'
      $card = [ordered]@{ id = $newId; c = $catName; t = $t; k = $keys.ToArray(); sw = 'generic'; general = $fields.general; trigger = $fields.trigger; verify = $fields.verify; exception = $fields.exception; keep = $fields.keep; precond = $precond; risk = $risk; source = $src; v = 0; st = 0; u = 0; cid = $d.Name.Substring(0, 2); status = 'candidate'; notes = '候选通法：一个软件成功不等于其他软件已验证；升级只走 generic 槽 exp_save verified=1 流程' }
      foreach ($w in (Split-YaCommaList (A 'k'))) { Assert-YaClean (Repair-YaLine ([string]$w)) }
      if ($from) { Assert-YaClean $from }
      Assert-YaClean $newId
      Assert-YaClean $src
      foreach ($one in $keys) { Assert-YaClean ([string]$one) }
      $path = Join-Path $d.FullName ($newId + '.json')
      if (Test-Path -LiteralPath $path) { throw ('编号已被占用: ' + $newId) }
      [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $card -Depth 4), (New-Object Text.UTF8Encoding $false))
      $rb = Join-Path $skillLib '00_索引\重建索引.ps1'
      $rout = & powershell -NoProfile -ExecutionPolicy Bypass -File $rb 2>&1 | Out-String
      if ($rout -notmatch 'RESULT: OK') { Remove-Item -LiteralPath $path -Force; Write-Output $rout.TrimEnd(); throw '重建索引没过，新卡已撤回，原索引不变。' }
      Write-Output ('route: 通用 → ' + $path)
      Write-Output ('card: ' + $newId + ' v=0 候选（不是已验证）')
      Write-Output ('index: ' + (($rout -split "`r?`n") | Where-Object { $_ -match '^total:' }))
      Write-Output 'RESULT: OK'
      exit 0
    }
    throw 'save 要写 scope=专属 或 scope=通用。本软件里的菜单、接口、参数、报错 → 专属；换任何软件都成立的方法 → 通用。'
  }
  throw ('不认识的子命令: ' + (Show-ArgEcho $cmd) + '（ensure / find / where / save）')
}
catch {
  Write-Output ('ERROR: ' + $_.Exception.Message)
  Write-Output 'RESULT: FAIL'
  exit 1
}
