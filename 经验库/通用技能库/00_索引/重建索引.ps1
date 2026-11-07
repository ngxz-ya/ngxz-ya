# 重建通用技能库两级索引。在本包根目录：
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\经验库\通用技能库\00_索引\重建索引.ps1"
# 只读各类文件夹里的 G-*.json，写根上 索引.json 和每类 索引.json。最后一行 RESULT: OK。
# 安全写法（2026-11-04）：先全量校验，任何一张坏卡（JSON 坏、文件名与 id 不符、重号、五要素空、v 不是 0）
# 都 RESULT: FAIL 退出，一个索引都不写；校验过了才先写临时文件、回读核对，再逐个替换。失败时原索引字节不变。
$ErrorActionPreference = 'Stop'
$package=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $package 'YA插件\连接上下文.ps1') -PathsOnly
Assert-YaIsolatedPackage $package
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$lib = Split-Path $PSScriptRoot -Parent
$enc = New-Object Text.UTF8Encoding($false)
$note = '通用技能库总索引。Agent 先查这里（按编号、关键词或类别，Select-String 只回命中行），只按 f 读命中单卡全文。c=类别 t=一句话 k=关键词 sw=generic v=0候选(公共资料不等于实测) u=使用次数 st=省token(不估算,填0) risk=默认档 trigger=触发条件'
function Get-Line($c, [string]$rel) {
  $e = [ordered]@{ id = [string]$c.id; c = [string]$c.c; t = [string]$c.t; k = @($c.k | ForEach-Object { [string]$_ }); sw = [string]$c.sw
    v = [int]$c.v; u = [int]$c.u; st = [int]$c.st; risk = [string]$c.risk; trigger = [string]$c.trigger; f = $rel }
  return (ConvertTo-Json -InputObject $e -Compress -Depth 4)
}
$all = New-Object System.Collections.Generic.List[string]
$ids = @{}
$bad = 0
$plan = New-Object System.Collections.Generic.List[object]
# 第一遍：只读、只校验，不写任何文件
foreach ($dir in @(Get-ChildItem -LiteralPath $lib -Directory | Where-Object { $_.Name -match '^\d\d_' -and $_.Name -ne '00_索引' } | Sort-Object Name)) {
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($f in @(Get-ChildItem -LiteralPath $dir.FullName -Filter 'G-*.json' -File | Sort-Object Name)) {
    $c = $null
    try { $c = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { Write-Output ('BAD JSON 读不出: ' + $dir.Name + '/' + $f.Name); $bad++; continue }
    if ($null -eq $c) { Write-Output ('BAD JSON 为空: ' + $dir.Name + '/' + $f.Name); $bad++; continue }
    $cardBad = $false
    if ([string]$c.id + '.json' -ne $f.Name) { Write-Output ('BAD 文件名与 id 不符: ' + $dir.Name + '/' + $f.Name); $bad++; continue }
    if ($ids.ContainsKey([string]$c.id)) { Write-Output ('BAD 重复编号: ' + $c.id + ' 已在 ' + $ids[[string]$c.id]); $bad++; continue }
    foreach ($key in @('trigger', 'general', 'verify', 'exception', 'keep')) {
      if ([string]::IsNullOrWhiteSpace([string]$c.$key)) { Write-Output ('BAD 五要素缺 ' + $key + ': ' + $c.id); $bad++; $cardBad = $true }
    }
    if ([string]$c.v -notmatch '^0$') { Write-Output ('BAD 候选卡 v 必须是 0: ' + $c.id + ' v=' + [string]$c.v); $bad++; $cardBad = $true }
    $ids[[string]$c.id] = ($dir.Name + '/' + $f.Name)
    if ($cardBad) { continue }
    $rel = $dir.Name + '/' + $f.Name
    $line = Get-Line $c $rel
    [void]$lines.Add($line); [void]$all.Add($line)
  }
  $catNote = ($dir.Name + ' 小索引。字段同总索引；f 相对 经验库\通用技能库。')
  $text = '{"说明":' + (ConvertTo-Json -InputObject $catNote -Compress) + ",`n" + '"count":' + $lines.Count + ",`n" + '"entries":[' + "`n" + ($lines -join ",`n") + "`n]}`n"
  [void]$plan.Add([pscustomobject]@{ path = (Join-Path $dir.FullName '索引.json'); text = $text; count = $lines.Count; name = $dir.Name })
  Write-Output ('cat ' + $dir.Name + ' ' + $lines.Count)
}
$text = '{"说明":' + (ConvertTo-Json -InputObject $note -Compress) + ",`n" + '"total":' + $all.Count + ",`n" + '"entries":[' + "`n" + ($all -join ",`n") + "`n]}`n"
[void]$plan.Add([pscustomobject]@{ path = (Join-Path $lib '索引.json'); text = $text; count = $all.Count; name = 'total' })
Write-Output ('total: ' + $all.Count)
if ($bad -gt 0) {
  Write-Output ('bad: ' + $bad + '。没有写任何索引，原索引不变。修好坏卡再重建。')
  Write-Output 'RESULT: FAIL'; exit 1
}
# 第二遍：写临时文件并回读核对，全部过了才替换
$tmps = New-Object System.Collections.Generic.List[string]
try {
  foreach ($p in $plan) {
    $tmp = $p.path + '.tmp'
    [IO.File]::WriteAllText($tmp, $p.text, $enc)
    [void]$tmps.Add($tmp)
    $back = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $n = if ($p.name -eq 'total') { [int]$back.total } else { [int]$back.count }
    if ($n -ne $p.count -or @($back.entries).Count -ne $p.count) { throw ('临时索引回读条数不符: ' + $p.name) }
    foreach ($e in @($back.entries)) {
      if (-not (Test-Path -LiteralPath (Join-Path $lib ([string]$e.f)))) { throw ('临时索引 f 指向不存在的卡: ' + [string]$e.f) }
    }
  }
}
catch {
  foreach ($t in $tmps) { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force } }
  Write-Output ('BAD 临时索引校验失败: ' + $_.Exception.Message + '。原索引不变。')
  Write-Output 'RESULT: FAIL'; exit 1
}
$replaced = 0
try {
  foreach ($p in $plan) {
    $tmp = $p.path + '.tmp'
    if (Test-Path -LiteralPath $p.path) { [IO.File]::Replace($tmp, $p.path, [NullString]::Value) } else { [IO.File]::Move($tmp, $p.path) }
    $replaced++
  }
}
catch {
  foreach ($t in $tmps) { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force } }
  Write-Output ('BAD 替换中断: 已换 ' + $replaced + '/' + $plan.Count + ' 个，' + $_.Exception.Message + '。已换的都是校验过的新索引，请重跑一次。')
  Write-Output 'RESULT: FAIL'; exit 1
}
Write-Output 'RESULT: OK'
