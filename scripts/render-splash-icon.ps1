param([string]$Out)
Add-Type -AssemblyName System.Drawing
$S = 4.0; $size = [int](120 * $S)
$bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$gold = [System.Drawing.Color]::FromArgb(255,212,175,55)
$goldLight = [System.Drawing.Color]::FromArgb(255,247,232,164)
$goldDark = [System.Drawing.Color]::FromArgb(255,156,122,30)
$goldLightA = [System.Drawing.Color]::FromArgb(210,247,232,164)

function F([double]$v) { return [single]($v * $S) }

# --- Eight-point star: two square outlines (one rotated 45deg) ---
$pen = New-Object System.Drawing.Pen $goldLightA, (F 1.6)
$x = F 32; $y = F 32; $w = F 56; $h = F 56
$g.DrawRectangle($pen, $x, $y, $w, $h)
$cx = F 60; $cy = F 60
$m = New-Object System.Drawing.Drawing2D.Matrix
$m.RotateAt(45.0, [System.Drawing.PointF]::new($cx, $cy))
$old = $g.Transform
$g.MultiplyTransform($m)
$g.DrawRectangle($pen, $x, $y, $w, $h)
$g.Transform = $old
$m.Dispose(); $pen.Dispose()

# --- Crescent: outer circle minus offset cutter (Region.Exclude) ---
$outer = New-Object System.Drawing.Drawing2D.GraphicsPath
$outer.AddEllipse((F 33), (F 33), (F 54), (F 54))
$region = New-Object System.Drawing.Region $outer
$cutter = New-Object System.Drawing.Drawing2D.GraphicsPath
$cutter.AddEllipse((F 46), (F 30), (F 48), (F 48))
$region.Exclude($cutter)
$bounds = New-Object System.Drawing.Rectangle 0, 0, $size, $size
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, $goldLight, $goldDark, 45.0
$blend = New-Object System.Drawing.Drawing2D.ColorBlend
$blend.Count = 3
$blend.Colors = @($goldLight, $gold, $goldDark)
$blend.Positions = @([single]0.0, [single]0.5, [single]1.0)
$brush.InterpolationColors = $blend
$g.FillRegion($brush, $region)
$brush.Dispose(); $region.Dispose(); $cutter.Dispose(); $outer.Dispose()

# --- Sparkle ---
$sb = New-Object System.Drawing.SolidBrush $goldLight
$g.FillEllipse($sb, (F 81.6), (F 37.6), (F 4.8), (F 4.8))
$sb.Dispose()

$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("rendered " + $size + "x" + $size + " -> " + $Out)