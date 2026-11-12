# 在图纸图片上画红色实心圈号（白字），不压原图线。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File 圈号.ps1 -Image 图.png -Out 工程图_圈号.png -Marks "1:420,380;2:520,410"
#   Marks：号:x,y（像素，圈心位置）用分号隔开。-R 圈半径，默认 14。
param([Parameter(Mandatory)][string]$Image, [Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][string]$Marks, [int]$R = 14)
Add-Type -AssemblyName System.Drawing
$src = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Image).Path)
$bmp = New-Object Drawing.Bitmap($src.Width, $src.Height)
$g = [Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $src.Dispose()
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAlias'
$red = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(220, 30, 30))
$font = New-Object Drawing.Font('Arial', [single]($R * 0.95), [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
foreach ($m in ($Marks -split ';' | Where-Object { $_.Trim() })) {
  $n, $xy = $m.Split(':'); $x, $y = $xy.Split(',') | ForEach-Object { [single]$_ }
  $g.FillEllipse($red, $x - $R, $y - $R, 2 * $R, 2 * $R)
  $g.DrawString($n.Trim(), $font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(($x - $R), ($y - $R), (2 * $R), (2 * $R))), $fmt)
}
$g.Dispose(); $bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ('已存 ' + $Out)
