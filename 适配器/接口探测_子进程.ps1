param([string[]]$asmList,[string]$filter,[string]$out)
$dirs=@($asmList|ForEach-Object{Split-Path $_ -Parent}|Select-Object -Unique)
[AppDomain]::CurrentDomain.add_AssemblyResolve({param($s,$e);$n=(New-Object Reflection.AssemblyName($e.Name)).Name;foreach($d in $dirs){$f=Join-Path $d ($n+'.dll');if([IO.File]::Exists($f)){return [Reflection.Assembly]::LoadFrom($f)}};return $null})
$rx=New-Object regex($filter)
$res=@()
foreach($a in $asmList){
  $row=[ordered]@{file=$a;sha256=(Get-FileHash -LiteralPath $a).Hash;version='';file_version=(Get-Item -LiteralPath $a).VersionInfo.FileVersion;types=@();load_errors=@()}
  try{
    $as=[Reflection.Assembly]::LoadFrom($a);$row.version=$as.GetName().Version.ToString()
    try{$ts=$as.GetExportedTypes()}catch [Reflection.ReflectionTypeLoadException]{$ts=@($_.Exception.Types|Where-Object{$_});$row.load_errors+=@($_.Exception.LoaderExceptions|Select-Object -First 5|ForEach-Object{$_.Message})}
    $flags=[Reflection.BindingFlags]'Public,Instance,Static,DeclaredOnly'
    foreach($t in $ts){
      if(-not $rx.IsMatch($t.FullName)){continue}
      $ms=@();try{$ms=@($t.GetMethods($flags)|ForEach-Object{$_.Name+'('+((@($_.GetParameters()|ForEach-Object{$_.ParameterType.Name})) -join ',')+')'}|Select-Object -Unique)}catch{}
      $ps=@();try{$ps=@($t.GetProperties($flags)|ForEach-Object{$_.Name})}catch{}
      $base='';try{$base=[string]$t.BaseType.FullName}catch{}
      $row.types+=[ordered]@{type=$t.FullName;base=$base;methods=$ms;properties=$ps}
    }
  }catch{$row.load_errors+=$_.Exception.Message}
  $res+=$row
}
[IO.File]::WriteAllText($out,([ordered]@{schema=1;generated_utc=[DateTime]::UtcNow.ToString('o');assemblies=$res}|ConvertTo-Json -Depth 8 -Compress),[Text.UTF8Encoding]::new($true))