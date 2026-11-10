# 第一步先读 AGENTS.md「第 0 步」。本脚本：按阶段查随包通用卡（skill_search），把命中编号写进证据文件，证明卡确实被调用。
# 连接前：  powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\查通用卡.ps1 -Stage 连接前
# 建模前：  powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\查通用卡.ps1 -Stage 建模前 [-Q 关键词,关键词]
# 读全文：  ... -Get G-MODEL-004        照做后登记：  ... -Apply G-MODEL-004 -How "用在哪一步、怎么用的"
# 证据：工作区根\artifacts\card-calls.jsonl（每次一行 JSON：时间、阶段、查询词、命中编号、读取/采用）。报告时引用这份文件。
param([string]$Stage='连接前',[string[]]$Q,[string[]]$Get,[string]$Apply,[string]$How,[string]$Log)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if(-not $Log){
  if((Split-Path $pkg -Leaf) -eq '工作区'){$Log=Join-Path (Split-Path $pkg -Parent) 'artifacts\card-calls.jsonl'}else{$Log=Join-Path $pkg 'card-calls.jsonl'}
}
[IO.Directory]::CreateDirectory((Split-Path $Log -Parent))|Out-Null
$qs=Join-Path $pkg '经验库\通用技能库\00_索引\查询.ps1'
$default=@{'连接前'=@('启动','读回','接口','自动化','桥接');'建模前'=@('尺寸编号','建模','拉伸','验证','桥接')}
# -Get/-Apply 没显式给 -Stage 时，阶段跟随本日志里最近一次 skill_search（R8：建模前采用的卡被记成了 连接前）
if(($Apply -or $Get) -and -not $PSBoundParameters.ContainsKey('Stage') -and [IO.File]::Exists($Log)){
  $ls=@([IO.File]::ReadAllLines($Log,[Text.Encoding]::UTF8)|Where-Object{$_ -match '"kind":"skill_search"'})|Select-Object -Last 1
  if($ls){try{$Stage=($ls|ConvertFrom-Json).stage}catch{}}
}
function Put($o){[IO.File]::AppendAllText($Log,(($o|ConvertTo-Json -Depth 8 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))}
$now=[DateTime]::UtcNow.ToString('o')
if($Apply){
  if(-not $How){throw 'APPLY_NEEDS_HOW: -Apply 必须同时写 -How 说明用在哪一步'}
  Put ([ordered]@{utc=$now;stage=$Stage;kind='apply';id=$Apply;how=$How})
  Write-Output ('CARD_APPLIED: '+$Apply+' stage='+$Stage+' -> '+$Log+' （连接软件.ps1 Connect/Run 会把采用过的卡自动写进任务 JSON 的 used_general_cards）');exit 0
}
if($Get){
  foreach($id in $Get){
    $o=& powershell -NoProfile -ExecutionPolicy Bypass -File $qs skill_get ("id="+$id)|Out-String
    Write-Output $o
    Put ([ordered]@{utc=$now;stage=$Stage;kind='skill_get';id=$id;ok=($o -match 'RESULT: OK')})
  }
  Write-Output ('CARD_LOG: '+$Log);exit 0
}
$Q=@($Q|ForEach-Object{$_ -split ','}|Where-Object{$_});if(-not $Q){$Q=$default[$Stage];if(-not $Q){$Q=@($Stage)}}
$all=New-Object System.Collections.Generic.List[object]
foreach($term in @($Q|ForEach-Object{$_ -split ','}|Where-Object{$_})){
  $raw=& powershell -NoProfile -ExecutionPolicy Bypass -File $qs skill_search ("q="+$term) max=5|Out-String
  $ids=@();try{$j=($raw -split 'RESULT:')[0]|ConvertFrom-Json;$ids=@($j.entries|ForEach-Object{$_.id});foreach($e in @($j.entries)){$all.Add($e)}}catch{}
  Put ([ordered]@{utc=$now;stage=$Stage;kind='skill_search';q=$term;hits=$ids})
  Write-Output ('skill_search q='+$term+' -> '+($(if($ids){$ids -join ','}else{'0 命中'})))
}
$seen=@{}
foreach($e in $all){if(-not $seen.ContainsKey($e.id)){$seen[$e.id]=1;Write-Output ('  '+$e.id+'  '+$e.t)}}
Write-Output ('CARD_LOG: '+$Log)
Write-Output '下一步：挑与本步相关的卡 -Get <编号> 读全文；照做了就 -Apply <编号> -How "..." 登记。卡是候选指导(v=0)，不是连接方法。'
exit 0