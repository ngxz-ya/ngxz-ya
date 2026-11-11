param([Parameter(Mandatory=$true)][string]$Destination,
  [ValidateSet('AuditCandidate','TestCopy','ReleaseCandidate')][string]$Profile='TestCopy')
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$target=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
if($target -ieq $source -or $target.StartsWith(($source+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '目标必须在源码目录之外（桌面固定路径 ngxz-ya 不在源码目录内；不再使用 ngxz-ya-ws 例外）'}
foreach($path in @($target,($target+'.manifest.json'),($target+'.SHA256SUMS.txt'))){if(Test-Path -LiteralPath $path){throw ('禁止覆盖已有路径: '+$path)}}
$policy=Get-Content -LiteralPath (Join-Path $source '发布允许清单.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($policy.schema -ne 1){throw '不支持的允许清单版本'}
# MIT范围已由维护者确认；内容检查不等于远端写入批准。
$licenseFile=Join-Path $source 'LICENSE'
if($policy.license -ne 'MIT' -or $policy.rights -ne 'MAINTAINER_OWNED_CODE_MIT' -or $policy.copyright -cne 'Copyright (c) 2026 ngxz-ya' -or $policy.files -cnotcontains 'LICENSE'){throw 'RELEASE_BLOCKED: MIT policy or LICENSE allowlist missing'}
$licenseHash=''
if(Test-Path -LiteralPath $licenseFile){
  $hashAlgorithm=[Security.Cryptography.SHA256]::Create()
  try{$licenseHash=[BitConverter]::ToString($hashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($licenseFile).Replace("`r`n","`n")))).Replace('-','')}finally{$hashAlgorithm.Dispose()}
}
if($licenseHash -cne '014DA63C10363D0BE9A971D3918E0E08690EC661D703375D1BCCEBBA3FE28290'){throw 'RELEASE_BLOCKED: LICENSE differs from approved standard MIT text'}
$allow=@{};foreach($rel in @($policy.files)){if($allow.ContainsKey($rel)){throw '允许清单重复'};$allow[$rel]='A'}
if($Profile -eq 'TestCopy'){
  foreach($rel in @($policy.development_tests)){
    if(Test-Path -LiteralPath (Join-Path $source $rel)){$allow[$rel]='B'}
  }
}
$inventory=@();$pending=@();$seen=@{}
# 不进入重解析点或.git；已跟踪文件与历史由审查报告另行核对。
$queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($source)
while($queue.Count){
  foreach($item in (Get-ChildItem -LiteralPath $queue.Dequeue() -Force)){
    $rel=$item.FullName.Substring($source.Length+1).Replace('\','/')
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('发现重解析点，停止打包: '+$rel)}
    if($item.PSIsContainer){if($rel -ne '.git'){$queue.Enqueue($item.FullName)};continue}
    $category='D';$reason='未列入明确允许清单，来源或用途待确认';$origin='UNKNOWN';$rights='UNKNOWN'
    if($allow.ContainsKey($rel)){
      $category=$allow[$rel];$reason='维护者有权发布的项目源码、说明或许可证';$origin='PROJECT_MAINTAINED_SOURCE';$rights='MIT_MAINTAINER_OWNED_CODE_ONLY'
      if($rel -like '经验库/通用技能库/*'){$reason='维护者原创通用卡，按 MIT 发布';$rights='MIT_MAINTAINER_ORIGINAL'}
      if($category -eq 'B'){$reason='研发测试，仅TestCopy包含'}
    }elseif($policy.development_tests -contains $rel -or $rel -eq '.gitignore' -or $rel -eq '包信息.json'){$category='B';$reason='研发工具、测试或上轮生成标记，不进入审查候选'}
    elseif($rel -match '^经验库/(槽/|[^/]+\.json$)' -or $rel -match '^连接教练/连接经验/(索引\.json$|[^/]+/)'){$category='C';$reason='本地槽、任务、经验或连接数据；生成空结构，不复制原件'}
    elseif($rel -like '经验库/通用技能库/*'){$reason='维护者原创通用卡（MIT）但未列入发布允许清单，本次不打包；需要时补进清单';$origin='PROJECT_MAINTAINED_SOURCE';$rights='MIT_MAINTAINER_ORIGINAL'}
    elseif($rel -match '(?i)\.(log|jsonl|prt|step|stp|stl|db|sqlite|tmp|bak)$|(^|/)(\.env|credentials)'){$category='C';$reason='运行证据、模型、日志或可能的私人配置'}
    $include=$allow.ContainsKey($rel)
    $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    $inventory+=[ordered]@{file=$rel;category=$category;included=$include;reason=$reason;origin=$origin;rights=$rights;sha256=$hash;length=$item.Length}
    if($include){
      if($rel -notin @('.gitignore','LICENSE') -and $item.Extension -notin @('.ps1','.cs','.md','.txt','.json','.bat','.py')){throw ('不允许的发布文件类型: '+$rel)}
      $text=[IO.File]::ReadAllText($item.FullName)
      if($text -match '(?im)(?:[A-Z]:\\(?:Users|UserData)\\|sk-[a-zA-Z0-9]{24,}|gh[pousr]_[a-zA-Z0-9]{24,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)'){throw ('待复核的私人路径或凭据特征: '+$rel)}
      $pending+=@{file=$rel;source=$item.FullName;sha256=$hash};$seen[$rel]=$true
    }
  }
}
foreach($rel in $allow.Keys){if(-not $seen.ContainsKey($rel)){throw ('允许清单文件缺失: '+$rel)}}
# 校验全部完成后才创建目标；失败目录保留调查，不自动删除。
[IO.Directory]::CreateDirectory($target)|Out-Null
foreach($row in $pending){
  $to=Join-Path $target $row.file
  [IO.Directory]::CreateDirectory((Split-Path $to -Parent))|Out-Null
  [IO.File]::Copy($row.source,$to,$false)
  if((Get-FileHash -LiteralPath $to).Hash -cne $row.sha256){throw '复制期间源码改变，保留副本并停止'}
}
function New-FactoryJson([string]$Relative,$Value){
  $path=Join-Path $target $Relative
  [IO.Directory]::CreateDirectory((Split-Path $path -Parent))|Out-Null
  [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $Value -Depth 15),[Text.UTF8Encoding]::new($true))
}
New-FactoryJson '经验库/槽位.json' @{version=1;active='generic';slots=@(@{id='generic';title='未指定软件';dir='generic';note='出厂空槽'},@{id='freecad';title='FreeCAD';dir='freecad';note='开源建模专属空槽'})}
New-FactoryJson '经验库/槽/generic/索引.json' @{说明='本槽经验索引。只收已验证条目。';entries=@()}
New-FactoryJson '经验库/槽/freecad/索引.json' @{说明='FreeCAD 用户经验索引。出厂为空。';entries=@()}
foreach($slotId in @('generic','freecad')){
  foreach($category in @('招式库','坑库','零件方案库','_草稿/招式库','_草稿/坑库','_草稿/零件方案库')){
    [IO.Directory]::CreateDirectory((Join-Path $target ('经验库/槽/'+$slotId+'/'+$category)))|Out-Null
  }
}
New-FactoryJson '连接教练/连接经验/索引.json' @{说明='本地连接卡出厂为空。';count=0;entries=@()}
# ReleaseCandidate contains only the root index and approved cards. Deployment and internal test profiles create the empty local categories.
$emptyCategories=@(if($Profile -ne 'ReleaseCandidate'){$policy.empty_knowledge_categories})
# 通用候选卡（v=0）与其索引随包发布，来自允许清单，不再改写为空。
foreach($category in $emptyCategories){
  if($category -notmatch '^\d\d_[^\\/.:]+$' -or $category -eq '00_索引'){throw '空分类目录非法'}
  New-FactoryJson ('经验库/通用技能库/'+$category+'/索引.json') @{说明='用户本地候选方法；出厂为空';count=0;entries=@()}
}
if($Profile -ne 'ReleaseCandidate'){New-FactoryJson '包信息.json' @{schema=2;stage=$Profile;status='TEST_COPY_NOT_FOR_UPLOAD';license='MIT';factory_data=$true;knowledge='PUBLIC_SOFTWARE_REFERENCE_LOCAL_EMPTY';release_blocked=$true}}
foreach($category in $emptyCategories){
  $empty=Get-Content -LiteralPath (Join-Path $target ('经验库/通用技能库/'+$category+'/索引.json')) -Raw -Encoding UTF8|ConvertFrom-Json
  if(@($empty.entries).Count -ne 0 -or $empty.count -ne 0){throw 'FACTORY_DATA_NOT_EMPTY'}
}
$output=@(Get-ChildItem -LiteralPath $target -File -Recurse|ForEach-Object{@{file=$_.FullName.Substring($target.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;origin=$(if($seen.ContainsKey($_.FullName.Substring($target.Length+1).Replace('\','/'))){'allowlisted_source'}else{'generated_empty_structure'})}}|Sort-Object file)
$rowsByFile=@{};foreach($row in $output){$rowsByFile[$row.file]=$row}
$orderedNames=[string[]]@($rowsByFile.Keys)
[Array]::Sort($orderedNames,[StringComparer]::Ordinal)
$output=@(foreach($name in $orderedNames){$rowsByFile[$name]})
foreach($row in $pending){if((Get-FileHash -LiteralPath $row.source).Hash -cne $row.sha256){throw '打包期间源码改变，保留失败副本，不产生成功清单'}}
$manifest=[ordered]@{schema=2;profile=$Profile;source=$source;target=$target;release_blocked=($Profile -ne 'ReleaseCandidate');blockers=@();remote_write_authorized=$false;license='MIT';rights_scope='MAINTAINER_OWNED_CODE_ONLY';files=$output;inventory=@($inventory|Sort-Object file);excluded=@($inventory|Where-Object{-not $_.included}|Sort-Object file);git_excluded=$true;history_clearance='NOT_ASSERTED'}
[IO.File]::WriteAllText(($target+'.manifest.json'),(ConvertTo-Json -InputObject $manifest -Depth 16),[Text.UTF8Encoding]::new($true))
$publicHashes=(@($output|ForEach-Object{$_.sha256+'  '+$_.file}) -join "`n")+"`n"
[IO.File]::WriteAllText(($target+'.SHA256SUMS.txt'),$publicHashes,[Text.UTF8Encoding]::new($false))
Write-Output ('isolated_package: '+$target)
Write-Output ('manifest: '+$target+'.manifest.json')
Write-Output 'manifest为内部审查元数据，含本机路径，禁止随包上传；SHA256SUMS仅含相对文件名和哈希。'
Write-Output 'RESULT: OK (content checked; GitHub write requires separate approval; TestCopy must not be published)'
