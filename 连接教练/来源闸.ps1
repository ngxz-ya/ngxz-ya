# 第一步先读 AGENTS.md「第 0 步」。来源闸（软件无关，硬闸）：首连时，准备接入 / 编译桥接 之前必须先上网搜到合法的开源或官方连接方案，并把来源登记进 sources.json。
# 登记：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Add -Url <https://...> -Points "这份资料的要点、用在哪一步" [-Query "搜索词"]
# 检查：powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Check   （退出码 0=通过 SOURCES_OK，5=不合格/缺失 SOURCES_REQUIRED）
# 合格：至少 2 条不同网址（http/https，不是本包自己的仓库），每条要点 ≥15 字。默认文件 工作区根\artifacts\sources.json；存经验时复制到 连接教练\连接经验\<槽>\sources.json 也算。
param([switch]$Add,[switch]$Check,[string]$Url,[string]$Points,[string]$Query,[string]$File)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
if(-not $File){$File=Join-Path $ws 'artifacts\sources.json'}
function Load([string]$f){
  if(-not [IO.File]::Exists($f)){return ,@()}
  try{$j=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{return $null}
  if($null -ne $j.sources){return ,@($j.sources)};return ,@($j)
}
if($Add){
  if($Url -notmatch '^https?://\S+$'){Write-Output 'SOURCES_BAD_URL: -Url 必须是 http(s) 网址';exit 2}
  if(-not $Points -or $Points.Trim().Length -lt 15){Write-Output 'SOURCES_POINTS_TOO_SHORT: -Points 至少 15 字，写清资料要点和用在哪一步';exit 2}
  $cur=Load $File;if($null -eq $cur){Write-Output ('SOURCES_FILE_BROKEN: '+$File+' 不是合法 JSON，先修好或换 -File');exit 2}
  $cur=@($cur|Where-Object{$_ -and [string]$_.url -ne $Url})+@([pscustomobject][ordered]@{url=$Url;points=$Points.Trim();query=[string]$Query;utc=[DateTime]::UtcNow.ToString('o')})
  [IO.Directory]::CreateDirectory((Split-Path $File -Parent))|Out-Null
  [IO.File]::WriteAllText($File,(ConvertTo-Json -InputObject ([ordered]@{schema=1;sources=$cur}) -Depth 5),[Text.UTF8Encoding]::new($false))
  Write-Output ('SOURCES_ADDED: '+$Url+' （本文件共 '+$cur.Count+' 条）-> '+$File)
}
$cands=@($File,(Join-Path $ws 'artifacts\sources.json'),(Join-Path $pkg 'artifacts\sources.json'))
$cd=Join-Path $pkg '连接教练\连接经验';if(Test-Path -LiteralPath $cd){$cands+=@(Get-ChildItem -LiteralPath $cd -Recurse -Filter 'sources.json' -File -ErrorAction SilentlyContinue|ForEach-Object{$_.FullName})}
$why='没有 sources.json（应在 '+$File+'）'
foreach($f in @($cands|Select-Object -Unique)){
  if(-not [IO.File]::Exists($f)){continue}
  $s=Load $f;if($null -eq $s){$why='sources.json 不是合法 JSON：'+$f;continue}
  $ok=@($s|Where-Object{$_ -and [string]$_.url -match '^https?://\S+$' -and [string]$_.url -notmatch '(?i)github\.com/ngxz-ya/' -and ((@($_.points)|ForEach-Object{[string]$_}) -join ' ').Trim().Length -ge 15})
  $n=@($ok|ForEach-Object{([string]$_.url).TrimEnd('/').ToLowerInvariant()}|Select-Object -Unique).Count
  if($n -ge 2){Write-Output ('SOURCES_OK: '+$n+' 条合格来源 '+$f);exit 0}
  $why='合格来源只有 '+$n+' 条（要 ≥2 条不同网址、每条要点 ≥15 字、不能是本包仓库）：'+$f
}
Write-Output ('SOURCES_REQUIRED: '+$why)
Write-Output '  先上网搜本软件的合法连接方案（官方 API/SDK 文档；GitHub「<软件名> API / MCP / bridge / automation / journal」；MCP Registry），读完再逐条登记：'
Write-Output '  powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\来源闸.ps1 -Add -Url <网址> -Points "要点：用哪个接口、怎么加载、要注意什么" -Query "搜索词"'
Write-Output '  不合格时 适配器\准备接入.ps1 和 适配器\编译桥接.ps1 都会拒绝执行（退出码 5）。'
exit 5