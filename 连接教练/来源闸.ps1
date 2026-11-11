# 第一步先读 AGENTS.md「第 0 步」。来源闸（软件无关，严格硬闸）：首连时，准备接入 / 编译桥接 之前必须先在本会话里真实打开合法的开源或官方连接资料，并登记进 sources.json。
# 先打开：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\取页.ps1 -GitHubSearch "<软件名> 关键词"   然后   连接教练\取页.ps1 -Url <网址>（留缓存+哈希）
# 再登记：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Add -Url <同一网址> -Points "这份资料的要点（写出页面里出现的接口/类名/文件名/加载方式原词）、用在哪一步" [-Query "搜索词"]
# 检查：  powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Check   （退出码 0=SOURCES_OK，5=SOURCES_REQUIRED）
# 合格（全部满足）：≥2 条不同网址；其中 ≥1 条是 GitHub 仓库（github.com/<作者>/<仓库>，不是本包 ngxz-ya）；每条都由 取页.ps1 在本会话（artifacts\round.json 之后）打开过、HTTP 2xx、缓存文件哈希对得上；
#                   要点 ≥15 字，且至少 2 个英文词（≥4 字母，如接口名/类名/文件名）真的出现在该页正文里。凭印象填、没打开过、打开失败的网址一律不算。
param([switch]$Add,[switch]$Check,[string]$Url,[string]$Points,[string]$Query,[string]$File)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{Join-Path $pkg '运行数据'})
if(-not $File){$File=Join-Path $ws 'artifacts\sources.json'}
$cache=Join-Path $ws 'artifacts\page-cache'
$roundF=Join-Path $ws 'artifacts\round.json'
function Sha([byte[]]$b){$h=[Security.Cryptography.SHA256]::Create();(-join ($h.ComputeHash($b)|ForEach-Object{$_.ToString('x2')}))}
function Key([string]$u){(Sha ([Text.Encoding]::UTF8.GetBytes($u.Trim().TrimEnd('/').ToLowerInvariant()))).Substring(0,20)}
function UtcOf([string]$s){[DateTime]::Parse($s,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}
function Load([string]$f){
  if(-not [IO.File]::Exists($f)){return ,@()}
  try{$j=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{return $null}
  if($null -ne $j.sources){return ,@($j.sources)};return ,@($j)
}
$round=$null;if([IO.File]::Exists($roundF)){try{$round=[IO.File]::ReadAllText($roundF,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{}}
function IsRepo([string]$u){
  $m=[regex]::Match($u,'(?i)^https?://(www\.)?github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)')
  if(-not $m.Success){$m=[regex]::Match($u,'(?i)^https?://api\.github\.com/repos/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)');if(-not $m.Success){return $false};$o=$m.Groups[1].Value}else{$o=$m.Groups[2].Value}
  if($o -match '^(?i)(ngxz-ya|search|topics|orgs|marketplace|features|collections|settings|login|about)$'){return $false}
  return $true
}
# returns [reason] ('' = valid) for one entry
function Judge($e){
  $u=[string]$e.url
  if($u -notmatch '^https?://\S+$'){return '网址不是 http(s)'}
  if($u -match '(?i)github\.com/ngxz-ya/'){return '本包自己的仓库不算来源'}
  if($u -match '(?i)api\.github\.com/search/'){return '搜索结果页不算来源，要打开具体仓库/文档'}
  $pt=((@($e.points)|ForEach-Object{[string]$_}) -join ' ').Trim()
  if($pt.Length -lt 15){return '要点不足 15 字'}
  if(-not $round){return '缺 artifacts\round.json（本会话起点），先在包根跑 一键连接.ps1'}
  $meta=Join-Path $cache ((Key $u)+'.meta.json')
  if(-not [IO.File]::Exists($meta)){return '本会话没用 连接教练\取页.ps1 打开过这个网址（没有缓存记录）'}
  $m=[IO.File]::ReadAllText($meta,[Text.Encoding]::UTF8)|ConvertFrom-Json
  if([int]$m.status -lt 200 -or [int]$m.status -ge 300){return ('打开失败 HTTP '+$m.status)}
  if(-not [IO.File]::Exists([string]$m.body_file) -or (Sha ([IO.File]::ReadAllBytes([string]$m.body_file))) -ne [string]$m.sha256){return '缓存正文缺失或哈希对不上（缓存被改过）'}
  if(-not [IO.File]::Exists([string]$m.text_file) -or (Sha ([IO.File]::ReadAllBytes([string]$m.text_file))) -ne [string]$m.text_sha256){return '缓存文本缺失或哈希对不上（缓存被改过）'}
  $ft=UtcOf ([string]$m.fetched_utc);$rt=UtcOf ([string]$round.started_utc)
  if($ft -lt $rt){return ('打开时间 '+$ft.ToString('o')+' 早于本会话起点 '+$rt.ToString('o')+'，请本会话重新打开')}
  if($ft -gt [DateTime]::UtcNow.AddMinutes(5)){return '打开时间在未来，记录无效'}
  $txt=[IO.File]::ReadAllText([string]$m.text_file,[Text.Encoding]::UTF8)
  $stop='^(?i)(http|https|www|html|this|that|with|from|have|used|uses|code|file|page|docs|example|examples|github|readme|true|false|null)$'
  $tok=@([regex]::Matches($pt,'[A-Za-z_][A-Za-z0-9_]{3,}')|ForEach-Object{$_.Value}|Where-Object{$_ -notmatch $stop}|Select-Object -Unique)
  $hit=@($tok|Where-Object{$txt.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  if($hit.Count -lt 2){return ('要点里只有 '+$hit.Count+' 个英文词出现在该页正文（要 ≥2，例如页面里的接口名/类名/文件名/参数名）。命中：'+($hit -join ',')+'；未命中：'+(@($tok|Where-Object{$hit -notcontains $_}|Select-Object -First 8) -join ','))}
  return ''
}
if($Add){
  if($Url -notmatch '^https?://\S+$'){Write-Output 'SOURCES_BAD_URL: -Url 必须是 http(s) 网址';exit 2}
  $e=[pscustomobject][ordered]@{url=$Url;points=[string]$Points;query=[string]$Query}
  $why=Judge $e
  if($why){Write-Output ('SOURCES_ADD_REFUSED: '+$Url+' — '+$why);Write-Output '  先 连接教练\取页.ps1 -Url <网址> 真打开并读正文（.txt），要点里写页面原词，再登记。';exit 2}
  $cur=Load $File;if($null -eq $cur){Write-Output ('SOURCES_FILE_BROKEN: '+$File+' 不是合法 JSON，先修好或换 -File');exit 2}
  $m=[IO.File]::ReadAllText((Join-Path $cache ((Key $Url)+'.meta.json')),[Text.Encoding]::UTF8)|ConvertFrom-Json
  $cur=@($cur|Where-Object{$_ -and [string]$_.url -ne $Url})+@([pscustomobject][ordered]@{url=$Url;points=$Points.Trim();query=[string]$Query;github_repo=(IsRepo $Url);fetched_utc=[string]$m.fetched_utc;sha256=[string]$m.sha256;title=[string]$m.title;utc=[DateTime]::UtcNow.ToString('o')})
  [IO.Directory]::CreateDirectory((Split-Path $File -Parent))|Out-Null
  [IO.File]::WriteAllText($File,(ConvertTo-Json -InputObject ([ordered]@{schema=2;round_id=[string]$round.round_id;sources=$cur}) -Depth 5),[Text.UTF8Encoding]::new($false))
  Write-Output ('SOURCES_ADDED: '+$Url+' github_repo='+(IsRepo $Url)+' （本文件共 '+$cur.Count+' 条）-> '+$File)
}
$why='没有 sources.json（应在 '+$File+'）'
foreach($f in @(@($File,(Join-Path $ws 'artifacts\sources.json'))|Select-Object -Unique)){
  if(-not [IO.File]::Exists($f)){continue}
  $s=Load $f;if($null -eq $s){$why='sources.json 不是合法 JSON：'+$f;continue}
  $good=@();$bad=@()
  foreach($e in @($s|Where-Object{$_})){$w=Judge $e;if($w){$bad+=('  ✗ '+[string]$e.url+' — '+$w)}else{$good+=$e}}
  $urls=@($good|ForEach-Object{([string]$_.url).TrimEnd('/').ToLowerInvariant()}|Select-Object -Unique)
  $repos=@($good|Where-Object{IsRepo ([string]$_.url)}|ForEach-Object{([string]$_.url).TrimEnd('/').ToLowerInvariant()}|Select-Object -Unique)
  if($urls.Count -ge 2 -and $repos.Count -ge 1){Write-Output ('SOURCES_OK: '+$urls.Count+' 条合格来源（GitHub 仓库 '+$repos.Count+' 条），均本会话打开过 '+$f);exit 0}
  $why='合格来源 '+$urls.Count+' 条、其中 GitHub 仓库 '+$repos.Count+' 条（要 ≥2 条且 ≥1 个 GitHub 仓库）：'+$f
  if($bad){$why+="`n"+($bad -join "`n")}
}
Write-Output ('SOURCES_REQUIRED: '+$why)
Write-Output '  先上网找本软件的合法连接方案并在本会话真实打开（Agent 自带网页工具被代理挡时就用本包取页脚本）：'
Write-Output '    powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\取页.ps1 -GitHubSearch "<软件名> api automation"'
Write-Output '    powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\取页.ps1 -Url <仓库或官方文档网址>'
Write-Output '  读完缓存正文再逐条登记（要点写页面原词）：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Add -Url <网址> -Points "要点：用哪个接口、怎么加载、要注意什么" -Query "搜索词"'
Write-Output '  不合格时 适配器\准备接入.ps1 和 适配器\编译桥接.ps1 都会拒绝执行（退出码 5）。'
exit 5
