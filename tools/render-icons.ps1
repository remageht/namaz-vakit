# render-icons.ps1 — рендер иконок из SVG (tools/icon.html, tools/icon-round.html)
# Chrome надёжно рисует только крупный мастер, уменьшение — через System.Drawing.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"

function Render-Master([string]$html, [string]$dest) {
  $cargs = @(
    "--headless=new", "--disable-gpu", "--hide-scrollbars",
    "--default-background-color=00000000",
    "--screenshot=$dest",
    "--window-size=512,512",
    "file:///$($html -replace '\\','/')"
  )
  Start-Process -FilePath $chrome -ArgumentList $cargs -NoNewWindow -Wait | Out-Null
}

function Resize-Png([string]$src, [string]$dst, [int]$size) {
  $img = [System.Drawing.Image]::FromFile($src)
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
  $g.Dispose()
  $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $img.Dispose()
}

$masterSquare = Join-Path $env:TEMP "namaz_master_square.png"
$masterRound = Join-Path $env:TEMP "namaz_master_round.png"
Render-Master (Join-Path $PSScriptRoot "icon.html") $masterSquare
Render-Master (Join-Path $PSScriptRoot "icon-round.html") $masterRound

Copy-Item -LiteralPath $masterSquare -Destination (Join-Path $root "icon-512.png") -Force

Resize-Png $masterSquare (Join-Path $root "icon-192.png") 192

$map = @{ "mdpi" = 48; "hdpi" = 72; "xhdpi" = 96; "xxhdpi" = 144; "xxxhdpi" = 192 }
foreach ($d in $map.Keys) {
  $size = $map[$d]
  Resize-Png $masterSquare (Join-Path $root "android\app\src\main\res\mipmap-$d\ic_launcher.png") $size
  Resize-Png $masterRound (Join-Path $root "android\app\src\main\res\mipmap-$d\ic_launcher_round.png") $size
}

Resize-Png $masterSquare (Join-Path $root "android\app\src\main\assets\namaz\icon-512.png") 512
Resize-Png $masterSquare (Join-Path $root "android\app\src\main\assets\namaz\icon-192.png") 192

$buildDir = Join-Path $root "desktop\build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Copy-Item -LiteralPath (Join-Path $root "icon-512.png") -Destination (Join-Path $buildDir "icon.png") -Force

Write-Output "icons rendered"
