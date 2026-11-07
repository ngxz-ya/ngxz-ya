# YA 总览面板。只读本包经验库里的已挂、分槽和用量。
# 不附着到任何机械软件窗口，不读外部日志。
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\ya_panel.ps1
#   加上 -Snapshot 只打印总览；-UiCheck 建窗口后立即关掉。
param(
  [switch]$Snapshot,
  [switch]$UiCheck
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'ya_slots.ps1')
. (Join-Path $PSScriptRoot 'ya_flow.ps1')

$root = Get-YaPackageRoot
$lib = Initialize-YaLibrary $root
Initialize-YaFlow $lib

function Get-YaPanelLines {
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('YA 总览')
  foreach ($line in (Get-YaItems (Format-YaOverview $lib))) { [void]$lines.Add([string]$line) }
  return ,$lines
}

if ($Snapshot -and -not $UiCheck) {
  foreach ($line in (Get-YaItems (Get-YaPanelLines))) { Write-Output $line }
  exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function New-Brush([string]$Hex) {
  $color = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
  $brush = New-Object System.Windows.Media.SolidColorBrush $color
  $brush.Freeze()
  return $brush
}

function New-Label([string]$Text, [double]$Size, [string]$Hex, [string]$Weight, [string]$Margin) {
  $tb = New-Object System.Windows.Controls.TextBlock
  $tb.Text = $Text
  $tb.FontSize = $Size
  $tb.Foreground = (New-Brush $Hex)
  $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Microsoft YaHei UI'
  $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
  if ($Weight -eq 'bold') { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
  if ($Margin) { $tb.Margin = (New-YaMargin $Margin) }
  return ,$tb
}

function New-YaBox([double]$L, [double]$T, [double]$R, [double]$B) {
  $box = New-Object System.Windows.Thickness
  $box.Left = $L
  $box.Top = $T
  $box.Right = $R
  $box.Bottom = $B
  return $box
}

function New-YaMargin([string]$Text) {
  if (-not $Text -or $Text -eq '0') { return (New-YaBox 0 0 0 0) }
  $parts = $Text.Split(',')
  if ($parts.Count -eq 1) {
    $n = [double]$parts[0]
    return (New-YaBox $n $n $n $n)
  }
  return (New-YaBox ([double]$parts[0].Trim()) ([double]$parts[1].Trim()) ([double]$parts[2].Trim()) ([double]$parts[3].Trim()))
}

$ink = '#1C1B19'
$sub = '#6B6560'
$line = '#E4E0D8'
$ok = '#0F6E56'
$wait = '#8A5A00'
$model = Get-YaOverview $lib

$window = New-Object System.Windows.Window
$window.Title = 'YA 总览'
$window.Width = 392
$window.SizeToContent = [System.Windows.SizeToContent]::Height
$window.MaxHeight = 640
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
$window.ResizeMode = [System.Windows.ResizeMode]::CanMinimize
$window.Background = (New-Brush '#F6F4EF')
$window.FontFamily = New-Object System.Windows.Media.FontFamily 'Microsoft YaHei UI'

$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.VerticalScrollBarVisibility = 'Auto'
$scroll.Padding = New-YaBox 16 16 16 16
$rootPanel = New-Object System.Windows.Controls.StackPanel
$scroll.Content = $rootPanel
$window.Content = $scroll

function Put-Ui($Parent, $Child) {
  $node = $Child
  if ($node -is [System.Array]) { $node = $node[-1] }
  [void]$Parent.Children.Add([System.Windows.UIElement]$node)
}

function Add-Card([string]$Title, [string]$Body, [string]$Badge, [string]$BadgeHex) {
  $card = New-Object System.Windows.Controls.Border
  $card.Background = (New-Brush '#FFFFFF')
  $card.BorderBrush = (New-Brush $line)
  $card.BorderThickness = New-YaBox 1 1 1 1
  $card.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 10
  $card.Padding = New-YaBox 12 12 12 12
  $card.Margin = New-YaBox 0 0 0 8
  $sp = New-Object System.Windows.Controls.StackPanel
  $head = New-Object System.Windows.Controls.StackPanel
  $head.Orientation = 'Horizontal'
  Put-Ui $head (New-Label $Badge 11 $BadgeHex 'bold' '0,0,8,0')
  Put-Ui $head (New-Label $Title 14 $ink 'bold' '0')
  Put-Ui $sp $head
  Put-Ui $sp (New-Label $Body 12 $sub '' '0,6,0,0')
  $card.Child = $sp
  Put-Ui $rootPanel $card
}

$tokenText = '未登记'
if ([int]$model.token_known -gt 0) { $tokenText = [string]$model.sum_token }
Put-Ui $rootPanel (New-Label 'YA' 22 $ink 'bold' '0,0,0,2')
Put-Ui $rootPanel (New-Label ('已挂 ' + $model.linked_count + '    经验 ' + $model.sum_entries + '    调用 ' + $model.sum_calls + '    TOKEN ' + $tokenText) 13 $ink 'bold' '0,0,0,4')
Put-Ui $rootPanel (New-Label '分槽存放，这里一处看完。TOKEN 只显示已登记的数字。' 12 $sub '' '0,0,0,10')

if ((Get-YaItems $model.slots).Count -eq 0) {
  Add-Card '还没有经验槽' '装好之后至少有一个底槽。' '空' $wait
} else {
  foreach ($s in (Get-YaItems $model.slots)) {
    $badge = '未过关'
    $color = $wait
    if ($s.linked) { $badge = '已挂'; $color = $ok }
    $body = '经验 ' + $s.entries + '    草稿 ' + $s.drafts + '    调用 ' + $s.calls + '    TOKEN ' + (Format-YaToken $s.token)
    Add-Card ($s.title + '  ·  ' + (Format-YaShownId ([string]$s.id))) $body $badge $color
  }
}
if ([int]$model.linked_count -eq 0) {
  Put-Ui $rootPanel (New-Label '还没有软件通过三步闸。槽可以先记账，过关才算已挂。' 12 $sub '' '0,2,0,8')
}
if ([int]$model.failed_count -gt 0) {
  Put-Ui $rootPanel (New-Label ('失败 ' + $model.failed_count + '。原因用 link_list 看，不进已挂。') 12 $sub '' '0,2,0,8')
}
if ($model.reserved) {
  Put-Ui $rootPanel (New-Label ('保留名 all 不能当槽。经验 ' + $model.reserved_entries + '，草稿 ' + $model.reserved_drafts + '。有条目请先迁走再清。') 12 $sub '' '0,2,0,8')
}

$row = New-Object System.Windows.Controls.StackPanel
$row.Orientation = 'Horizontal'
$row.Margin = New-YaBox 0 4 0 12
$refresh = New-Object System.Windows.Controls.Button
$refresh.Content = '刷新'
$refresh.Margin = New-YaBox 0 0 8 0
$refresh.Padding = New-YaBox 12 4 12 4
$refresh.Add_Click({
    $again = Join-Path $PSScriptRoot 'ya_panel.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $again) | Out-Null
    $window.Close()
  })
$close = New-Object System.Windows.Controls.Button
$close.Content = '关闭'
$close.Padding = New-YaBox 12 4 12 4
$close.Add_Click({ $window.Close() })
Put-Ui $row $refresh
Put-Ui $row $close
Put-Ui $rootPanel $row

function Get-UiText($Node) {
  $buf = New-Object System.Collections.Generic.List[string]
  $stack = New-Object System.Collections.Stack
  $seen = New-Object System.Collections.Generic.List[object]
  $stack.Push($Node)
  while ($stack.Count -gt 0) {
    $cur = $stack.Pop()
    $known = $false
    foreach ($old in $seen) {
      if ([object]::ReferenceEquals($old, $cur)) { $known = $true; break }
    }
    if ($known) { continue }
    [void]$seen.Add($cur)
    if ($cur -is [System.Windows.Controls.TextBlock]) { [void]$buf.Add([string]$cur.Text) }
    if ($cur -is [System.Windows.Controls.Panel]) {
      foreach ($child in $cur.Children) { $stack.Push($child) }
    }
    foreach ($propName in @('Content', 'Child')) {
      $prop = $cur.PSObject.Properties[$propName]
      if ($prop -and $prop.Value -is [System.Windows.DependencyObject]) { $stack.Push($prop.Value) }
    }
  }
  return ,$buf
}

if ($UiCheck) {
  $window.ShowInTaskbar = $false; $window.ShowActivated = $false; $window.WindowStartupLocation = 'Manual'; $window.Left = -32000; $window.Top = -32000
  $window.Show()
  $window.UpdateLayout()
  $text = (Get-YaItems (Get-UiText $window)) -join "`n"
  $okText = 'no'
  if ($text.Contains('YA') -and $text.Contains('调用') -and $text.Contains('TOKEN')) { $okText = 'yes' }
  $failLine = 'na'
  if ([int]$model.failed_count -gt 0) {
    $failLine = 'no'
    if ($text.Contains('失败')) { $failLine = 'yes' }
  }
  Write-Output ('ui: cards=' + (Get-YaItems $model.slots).Count)
  Write-Output ('ui: text_ok=' + $okText)
  Write-Output ('ui: failed_line=' + $failLine)
  Write-Output ('ui: header_token=' + $tokenText)
  foreach ($line in (Get-YaItems (Get-YaPanelLines))) { Write-Output $line }
  $window.Close()
  if ($okText -ne 'yes') { exit 1 }
  exit 0
}

$null = $window.ShowDialog()
exit 0
