# 包内回归：通用修（不启动任何机械软件，不写正式经验）。
# 用法（包根）：powershell -NoProfile -ExecutionPolicy Bypass -File .\YA插件\回归_通用修.ps1
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$pkg = Split-Path $PSScriptRoot -Parent
. (Join-Path $pkg 'YA插件\连接上下文.ps1')
Assert-YaIsolatedPackage $pkg
. (Join-Path $pkg 'YA插件\真实记录.ps1')
$iso = Join-Path $env:TEMP ('ya-reg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $iso 'appdata') -Force | Out-Null
$env:LOCALAPPDATA = Join-Path $iso 'appdata'
Remove-Item Env:YALINK_HUD_HOME -ErrorAction SilentlyContinue

$pass = New-Object System.Collections.Generic.List[string]

# a/d: ContainsKey is the supported dictionary probe; .Contains(string) is not.
$proof = New-Object 'Collections.Generic.Dictionary[string,object]'
$proof['bridge_path'] = 'C:\workspace\artifacts\bridge.dll'
if (-not $proof.ContainsKey('bridge_path')) { throw 'ContainsKey should be true for a present key' }
$missing = New-Object 'Collections.Generic.Dictionary[string,object]'
if ($missing.ContainsKey('bridge_path')) { throw 'ContainsKey should be false when the key is absent' }
$threw = $false
try { [void]$proof.Contains('bridge_path') } catch { $threw = $true }
if (-not $threw) { Write-Output 'note: Dictionary.Contains(string) did not throw on this PowerShell; contract is still ContainsKey.' }
$pass.Add('PASS: ContainsKey (good proof present, missing key not treated as present)')

# b: Grok type=end import (终态 only; total = input+output+cache, not reasoning)
$ws = $iso
$log = Join-Path $ws 'grok.jsonl'
$sid = '01regression-session-grok-testxxxxxxxx'
$end = @{
  type='end'; stopReason='end_turn'; sessionId=$sid
  usage=@{ input_tokens=10; cache_read_input_tokens=20; cache_creation_input_tokens=0; output_tokens=5; reasoning_tokens=3; total_tokens=35 }
  modelUsage=@{ 'grok-regression'=@{ inputTokens=10; outputTokens=5 } }
} | ConvertTo-Json -Compress -Depth 6
# a step event must be ignored
$step = @{ type='usage'; usage=@{ input_tokens=999; output_tokens=999; total_tokens=1998 } } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($log, ($step + "`n" + $end + "`n"), [Text.UTF8Encoding]::new($false))
$fmt = Resolve-YaUsageFormat $log 'Auto'
if ($fmt -cne 'Grok') { throw ('Auto format expected Grok, got ' + $fmt) }
$gotSid = Get-YaUsageSessionFromLog $log 'Grok'
if ($gotSid -cne $sid) { throw ('session mismatch ' + $gotSid) }
$doc = Import-YaRuntimeUsage $pkg $log $sid 'hud-auto' 'Grok'
if ($doc.source_kind -cne 'runtime_measured') { throw 'source_kind' }
if ([int]$doc.input_tokens -ne 10 -or [int]$doc.output_tokens -ne 5 -or [int]$doc.total_tokens -ne 35) { throw ('Grok totals wrong: ' + ($doc | ConvertTo-Json -Compress)) }
if ([int]$doc.cache_read_tokens -ne 20 -or [int]$doc.reasoning_tokens -ne 3) { throw 'Grok detail tokens' }
if ([int]$doc.total_tokens -eq 999) { throw 'step usage was incorrectly accumulated' }
$pass.Add('PASS: Grok type=end import (Auto detect, no step accumulation, cache in total)')

# e: HasColdFastpathVerification / HasFirstConnectComplete
$io = Join-Path (Get-YaPackageHudHome $pkg) 'io'
if (-not (Test-Path -LiteralPath $io)) { New-Item -ItemType Directory -Path $io -Force | Out-Null }
$slotDir = Join-Path $pkg '连接教练\连接经验\_regslot'
New-Item -ItemType Directory -Path $slotDir -Force | Out-Null
$cardPath = Join-Path $slotDir '连接卡-_regslot-001.json'
$card = @{ slot='_regslot'; id='连接卡-_regslot-001'; v=1; 核验='从零快通道核验通过（回归）'; t='regression' }
[IO.File]::WriteAllText($cardPath, ($card | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($true))
$rel = '连接教练\连接经验\_regslot\连接卡-_regslot-001.json'
$evPath = Join-Path $io 'fastpath-verified.json'
$ev = @{ schema=1; package_id=[YaEvidence]::Identity($pkg); slot='_regslot'; card='连接卡-_regslot-001'; card_file=$rel; card_sha256=[YaEvidence]::Hash($cardPath); cold_start=$true; result='OK'; pid='4242'; utc=[DateTime]::UtcNow.ToString('o') }
Write-YaAtomic $evPath $ev
if (-not [YaEvidence]::HasColdFastpathVerification($pkg, $io, '_regslot')) { throw 'expected cold fastpath verification' }
$link = New-Object 'Collections.Generic.Dictionary[string,object]'
foreach ($item in @{slot='_regslot'; pid='4242'; package_id=[YaEvidence]::Identity($pkg)}.GetEnumerator()) { $link[$item.Key]=$item.Value }
if (-not [YaEvidence]::HasFirstConnectComplete($pkg, $io, $link)) { throw 'same pid as cold 快连 should complete first connect' }
$link['pid']='9999'
if ([YaEvidence]::HasFirstConnectComplete($pkg, $io, $link)) { throw 'different pid without frontend acceptance must not complete' }
# v=0 should fail
$card.v = 0
[IO.File]::WriteAllText($cardPath, ($card | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($true))
if ([YaEvidence]::HasColdFastpathVerification($pkg, $io, '_regslot')) { throw 'v=0 card must not count as verified' }
$pass.Add('PASS: first-connect complete only after cold fastpath v=1 (same pid); v=0 or other pid without acceptance rejected')

# cleanup regression artifacts (do not leave a fake slot/card in the official tree or hud io)
Remove-Item -LiteralPath $slotDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $evPath) { Remove-Item -LiteralPath $evPath -Force }
Remove-Item -LiteralPath $iso -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ($_ ) 
$pass | ForEach-Object { Write-Output $_ }
Write-Output ('count: ' + $pass.Count)
Write-Output 'RESULT: OK'
exit 0
