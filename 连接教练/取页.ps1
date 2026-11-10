# 第一步先读 AGENTS.md「第 0 步」。取页（软件无关）：本会话真实打开一个公开网页/GitHub 仓库，留本地缓存+哈希，来源闸只认这里打开过的网址。
# 为什么用它：有的代理把 github.com 解析成 fake-IP（198.18.x.x），Agent 自带的网页抓取会被 SSRF 拦；本脚本走本机 Invoke-WebRequest（失败再试 curl.exe），实测能打开 github.com / api.github.com / raw.githubusercontent.com。
# 打开网页：  powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\取页.ps1 -Url <https://...>           （GitHub 仓库页会顺带取 README 正文）
# 搜 GitHub： powershell -NoProfile -ExecutionPolicy Bypass -File 连接教练\取页.ps1 -GitHubSearch "<软件名> automation"  （走 api.github.com，列出仓库、星数、许可证、网址）
# 缓存：工作区\artifacts\page-cache\<键>.body / .txt（去标签正文，用来读）/ .meta.json（url、HTTP 状态、本会话时间、sha256）。读 .txt 找接口和加载方法，再去 来源闸.ps1 -Add 登记。
# 退出码：0 = FETCH_OK；2 = 参数错；3 = 打不开（如实报告，换别的来源，不要凭印象登记）。
param([string]$Url,[string]$GitHubSearch,[ValidateRange(1,30)][int]$Max=10,[ValidateRange(5,120)][int]$TimeoutSec=30,[int]$ShowLines=60)
$ErrorActionPreference='Stop'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)}catch{}
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}catch{}
$pkg=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ws=$(if((Split-Path $pkg -Leaf) -eq '工作区'){Split-Path $pkg -Parent}else{$pkg})
$cache=Join-Path $ws 'artifacts\page-cache';[IO.Directory]::CreateDirectory($cache)|Out-Null
function Sha([byte[]]$b){$h=[Security.Cryptography.SHA256]::Create();(-join ($h.ComputeHash($b)|ForEach-Object{$_.ToString('x2')}))}
function Key([string]$u){(Sha ([Text.Encoding]::UTF8.GetBytes($u.Trim().TrimEnd('/').ToLowerInvariant()))).Substring(0,20)}
function Fetch([string]$u,[string]$accept){
  $hd=@{'User-Agent'='ngxz-ya-fetch/1 (+https://github.com/ngxz-ya/ngxz-ya)'};if($accept){$hd['Accept']=$accept}
  try{
    $r=Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec $TimeoutSec -Headers $hd -MaximumRedirection 5
    $ms=New-Object IO.MemoryStream;$r.RawContentStream.Position=0;$r.RawContentStream.CopyTo($ms)
    $fu=$u;try{$fu=[string]$r.BaseResponse.ResponseUri.AbsoluteUri}catch{}
    return [pscustomobject]@{ok=$true;status=[int]$r.StatusCode;bytes=$ms.ToArray();final=$fu;via='Invoke-WebRequest';err=''}
  }catch{
    $e1=$_.Exception.Message
    $curl=Join-Path $env:WINDIR 'System32\curl.exe'
    if([IO.File]::Exists($curl)){
      $tmp=Join-Path $cache ('_dl_'+[guid]::NewGuid().ToString('N'))
      $ca=@('-sS','-L','--max-time',[string]$TimeoutSec,'-A','ngxz-ya-fetch/1','-o',$tmp,'-w','%{http_code} %{url_effective}');if($accept){$ca+=@('-H',('Accept: '+$accept))}
      $w=& $curl @ca $u 2>&1;$cc=$LASTEXITCODE
      if($cc -eq 0 -and [IO.File]::Exists($tmp)){$b=[IO.File]::ReadAllBytes($tmp);[IO.File]::Delete($tmp);$parts=([string]($w|Select-Object -Last 1)).Split(' ',2)
        return [pscustomobject]@{ok=([int]$parts[0] -ge 200 -and [int]$parts[0] -lt 300);status=[int]$parts[0];bytes=$b;final=$(if($parts.Count -gt 1){$parts[1]}else{$u});via='curl.exe';err=$e1}}
      if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
      return [pscustomobject]@{ok=$false;status=0;bytes=[byte[]]@();final=$u;via='curl.exe';err=($e1+' | curl exit '+$cc+' '+($w -join ' '))}
    }
    return [pscustomobject]@{ok=$false;status=0;bytes=[byte[]]@();final=$u;via='Invoke-WebRequest';err=$e1}
  }
}
function ToText([string]$s){
  $t=[regex]::Replace($s,'(?is)<(script|style|svg|noscript)[^>]*>.*?</\1>',' ')
  $t=[regex]::Replace($t,'(?i)<br\s*/?>|</(p|div|li|h[1-6]|tr|pre|code)>',"`n")
  $t=[regex]::Replace($t,'<[^>]+>',' ');$t=[Net.WebUtility]::HtmlDecode($t)
  $t=[regex]::Replace($t,'[ \t\r\f\v]+',' ');$t=[regex]::Replace($t,'\n\s*\n+',"`n")
  return $t.Trim()
}
function Save([string]$u,$r,[string]$extraText,[string]$kind){
  $k=Key $u;$body=Join-Path $cache ($k+'.body');$txt=Join-Path $cache ($k+'.txt');$meta=Join-Path $cache ($k+'.meta.json')
  [IO.File]::WriteAllBytes($body,$r.bytes)
  $s=[Text.Encoding]::UTF8.GetString($r.bytes)
  $title='';$m=[regex]::Match($s,'(?is)<title[^>]*>(.*?)</title>');if($m.Success){$title=[Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()}
  $text=$(if($s -match '(?is)<html|<body|<div'){ToText $s}else{$s});if($extraText){$text=$text+"`n`n===== README =====`n"+$extraText}
  [IO.File]::WriteAllText($txt,$text,[Text.UTF8Encoding]::new($false))
  $rec=[ordered]@{schema=1;kind=$kind;url=$u;final_url=$r.final;status=$r.status;via=$r.via;fetched_utc=[DateTime]::UtcNow.ToString('o');bytes=$r.bytes.Length;sha256=(Sha $r.bytes);text_file=$txt;text_sha256=(Sha ([IO.File]::ReadAllBytes($txt)));body_file=$body;title=$title}
  [IO.File]::WriteAllText($meta,($rec|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::AppendAllText((Join-Path $ws 'artifacts\page-fetches.jsonl'),((([ordered]@{utc=$rec.fetched_utc;url=$u;status=$r.status;sha256=$rec.sha256;meta=$meta})|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{meta=$meta;txt=$txt;title=$title;text=$text;rec=$rec}
}
if($GitHubSearch){
  $u='https://api.github.com/search/repositories?q='+[Uri]::EscapeDataString($GitHubSearch)+'&sort=stars&order=desc&per_page='+$Max
  $r=Fetch $u 'application/vnd.github+json'
  if(-not $r.ok){Write-Output ('FETCH_FAIL status='+$r.status+' '+$u+' '+$r.err);exit 3}
  $j=[Text.Encoding]::UTF8.GetString($r.bytes)|ConvertFrom-Json
  $lines=@($j.items|ForEach-Object{('{0}  ★{1}  {2}  license={3}  {4}' -f $_.html_url,$_.stargazers_count,$(if($_.pushed_at){'pushed '+([string]$_.pushed_at).Substring(0,10)}else{''}),$(if($_.license){$_.license.spdx_id}else{'none'}),([string]$_.description))})
  $sv=Save $u $r ($lines -join "`n") 'github-search'
  Write-Output ('FETCH_OK github-search total='+$j.total_count+' shown='+@($j.items).Count+' meta='+$sv.meta)
  $lines|ForEach-Object{Write-Output ('  '+$_)}
  Write-Output '下一步：挑合法开源（看 license）、和本机版本相符的仓库，用 -Url <仓库网址> 打开读 README/源码，再 来源闸.ps1 -Add 登记。搜索结果页本身不算来源。'
  exit 0
}
if(-not $Url -or $Url -notmatch '^https?://\S+$'){Write-Output 'FETCH_BAD_ARGS: 用 -Url <http(s)://...> 或 -GitHubSearch "<关键词>"';exit 2}
$r=Fetch $Url ''
if(-not $r.ok){Write-Output ('FETCH_FAIL status='+$r.status+' via='+$r.via+' '+$Url+' '+$r.err);Write-Output '  打不开就换来源；不要把没打开的网址登记进来源闸。';exit 3}
$extra=''
$gm=[regex]::Match($Url,'(?i)^https?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)')
if($gm.Success){
  $rr=Fetch ('https://api.github.com/repos/'+$gm.Groups[1].Value+'/'+$gm.Groups[2].Value.Replace('.git','')+'/readme') 'application/vnd.github.raw'
  if($rr.ok){$extra=[Text.Encoding]::UTF8.GetString($rr.bytes)}
}
$sv=Save $Url $r $extra $(if($gm.Success){'github-repo'}else{'page'})
Write-Output ('FETCH_OK status='+$r.status+' via='+$r.via+' bytes='+$r.bytes.Length+' title="'+$sv.title+'"')
Write-Output ('  正文（去标签）：'+$sv.txt)
Write-Output ('  记录：'+$sv.meta)
$sl=@($sv.text -split "`n"|Where-Object{$_.Trim().Length -gt 2})
$from=0;if($extra){$ix=[Array]::IndexOf($sl,'===== README =====');if($ix -ge 0){$from=$ix}}
$sl|Select-Object -Skip $from -First $ShowLines|ForEach-Object{Write-Output ('  | '+$(if($_.Length -gt 220){$_.Substring(0,220)}else{$_}))}
Write-Output ('  （共 '+$sl.Count+' 行；读全文：Get-Content -LiteralPath "'+$sv.txt+'" -Encoding UTF8）')
Write-Output '下一步：读完再登记：来源闸.ps1 -Add -Url <同一网址> -Points "要点（写出页面里出现的接口/类名/文件名/加载方式等原词）"'
exit 0
