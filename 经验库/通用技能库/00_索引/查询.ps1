# 只读查询候选通法；不执行卡片，不提升验证等级。
param([ValidateSet('skill_search','skill_get')][string]$Command,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference='Stop'
try {
  $lib=Split-Path $PSScriptRoot -Parent
  $argsMap=@{};foreach($arg in $Rest){if($arg -notmatch '^([^=]+)=(.*)$'){throw '参数须为 key=value'};$argsMap[$matches[1]]=$matches[2]}
  $index=Get-Content -LiteralPath (Join-Path $lib '索引.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($Command -eq 'skill_get'){
    $rows=@($index.entries|Where-Object id -ceq $argsMap['id'])
    if($rows.Count -ne 1){throw '未找到唯一通法编号'}
    $file=[IO.Path]::GetFullPath((Join-Path $lib $rows[0].f))
    if(-not $file.StartsWith(([IO.Path]::GetFullPath($lib).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '通法路径越界'}
    $card=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json
    if($card.id -cne $rows[0].id){throw '索引与全文编号不一致'}
    [ordered]@{kind='candidate_guidance';eligible_for_execution=$false;card=$card;file=$rows[0].f}|ConvertTo-Json -Depth 16
  }else{
    $query=([string]$argsMap['q']).Trim();if(-not $query -or $query.Length -gt 200){throw 'q须为1至200字符'}
    $limit=5;if($argsMap.ContainsKey('max')){if(-not [int]::TryParse($argsMap['max'],[ref]$limit) -or $limit -lt 1 -or $limit -gt 20){throw 'max须为1至20'}}
    $terms=@($query -split '\s+')
    $rows=@($index.entries|Where-Object{$text=($_|ConvertTo-Json -Depth 5 -Compress);$match=$true;foreach($term in $terms){if($text.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0){$match=$false}};$match})
    [ordered]@{kind='candidate_guidance';query=$query;hits=$rows.Count;shown=[Math]::Min($limit,$rows.Count);eligible_for_execution=$false;entries=@($rows|Select-Object -First $limit id,t,c,k,f,v)}|ConvertTo-Json -Depth 10
  }
  Write-Output 'RESULT: OK'
}catch{Write-Output ('error: '+$_.Exception.Message);Write-Output 'RESULT: FAIL';exit 1}
