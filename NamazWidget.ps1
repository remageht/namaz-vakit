# NamazWidget.ps1 — виджет времени намаза в трее Windows (рядом с часами)
# Показывает следующий намаз + обратный отсчёт, балуны за 10 мин и в начале.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinApi {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int n, IntPtr v);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$Lat = 45.1342; $Lon = 33.60; $Method = 3; $School = 1; $Place = "Саки"
if (Test-Path -LiteralPath $ConfigFile) {
  try { $cfg = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.latitude -ne $null) { $Lat = $cfg.latitude }
    if ($cfg.longitude -ne $null) { $Lon = $cfg.longitude }
    if ($cfg.method -ne $null) { $Method = $cfg.method }
    if ($cfg.school -ne $null) { $School = $cfg.school }
    if ($cfg.place -ne $null -and $cfg.place -ne "") { $Place = $cfg.place }
  } catch {}
}
# Саки, Egypt-метод (сверен с islam.global), Ханафи
$AppUrl = "https://remageht.github.io/namaz-vakit/"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $ScriptDir "widget.log"
$CacheFile = Join-Path $env:TEMP "namaz_timings.json"
$RU = @{ Fajr="Фаджр"; Sunrise="Восход"; Dhuhr="Зухр"; Asr="Аср"; Maghrib="Магриб"; Isha="Иша" }
$Order = @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")

function Log($m){ Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m) -Encoding UTF8 }

function Get-Timings {
  $today = (Get-Date).ToString("dd-MM-yyyy")
  if (Test-Path -LiteralPath $CacheFile) {
    try { $c = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
      if ($c.date -eq $today) { return $c.timings } } catch {}
  }
  try {
    $r = Invoke-RestMethod -Uri "https://api.aladhan.com/v1/timings/${today}?latitude=${Lat}&longitude=${Lon}&method=${Method}&school=${School}" -TimeoutSec 15
    $t = $r.data.timings
    @{ date = $today; timings = $t } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $CacheFile
    Log "Время загружено: Фаджр $($t.Fajr), Иша $($t.Isha)"
    return $t
  } catch { Log "API ошибка: $($_.Exception.Message)"; return $null }
}

function To-Date($t) { $parts = $t.Substring(0,5).Split(":"); $h = [int]$parts[0]; $mi = [int]$parts[1]; $d = Get-Date; return (Get-Date -Year $d.Year -Month $d.Month -Day $d.Day -Hour $h -Minute $mi -Second 0) }

$timings = Get-Timings
if (-not $timings) { [System.Windows.Forms.MessageBox]::Show("Нет интернета и нет кэша времени намаза."); exit 1 }

function New-CountdownIcon($text) {
  $bmp = New-Object System.Drawing.Bitmap(16,16)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::FromArgb(6,40,31))
  $f = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
  $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(212,175,55))
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
  $g.DrawString($text, $f, $br, (New-Object System.Drawing.RectangleF(0,0,16,16)), $sf)
  $g.Dispose(); $f.Dispose(); $br.Dispose()
  $ic = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
  $bmp.Dispose()
  return $ic
}

# Стартовая иконка: полумесяц из icon-192.png, иначе стандартная
$icon = [System.Drawing.SystemIcons]::Information
try { $p = Join-Path $ScriptDir "icon-192.png"
  if (Test-Path -LiteralPath $p) { $b0 = New-Object System.Drawing.Bitmap($p); $icon = [System.Drawing.Icon]::FromHandle($b0.GetHicon()) }
} catch {}

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $icon; $ni.Visible = $true
$ctx = New-Object System.Windows.Forms.ApplicationContext

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add("Открыть приложение"); $open.Add_Click({ Start-Process $AppUrl })
$ref = $menu.Items.Add("Обновить время"); $ref.Add_Click({ $script:timings = Get-Timings })
$script:userHidden = $false
$tog = $menu.Items.Add("Скрыть панель"); $tog.Add_Click({ $script:userHidden = -not $script:userHidden; $tog.Text = if ($script:userHidden) { "Показать панель" } else { "Скрыть панель" } })
$exit = $menu.Items.Add("Выход"); $exit.Add_Click({ $ni.Visible = $false; $sched.Close(); $panel.Close(); $ctx.ExitThread() })
$ni.ContextMenuStrip = $menu
$ni.Add_DoubleClick({ Start-Process $AppUrl })

# Мини-панель в стиле виджета погоды: иконка + две строки, слева внизу рядом с погодой
$pic = New-Object System.Windows.Forms.PictureBox
$pic.Size = New-Object System.Drawing.Size(32, 32)
$pic.Location = New-Object System.Drawing.Point(8, 8)
$pic.SizeMode = "StretchImage"
try { $ip = Join-Path $ScriptDir "icon-192.png"
  if (Test-Path -LiteralPath $ip) { $pic.Image = [System.Drawing.Image]::FromFile($ip) }
} catch {}
$lblMain = New-Object System.Windows.Forms.Label
$lblMain.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblMain.ForeColor = [System.Drawing.Color]::White
$lblMain.AutoSize = $true
$lblMain.Location = New-Object System.Drawing.Point(48, 3)
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(170,170,170)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(48, 24)
$panel = New-Object System.Windows.Forms.Form
$panel.FormBorderStyle = "None"
$panel.TopMost = $true
$panel.ShowInTaskbar = $false
$panel.BackColor = [System.Drawing.Color]::FromArgb(43,43,43)
$panel.Opacity = 0.85
$panel.Size = New-Object System.Drawing.Size(210, 48)
$panel.Controls.Add($pic)
$panel.Controls.Add($lblMain)
$panel.Controls.Add($lblSub)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$panel.Location = New-Object System.Drawing.Point(($wa.Left + 140), $wa.Bottom)
$openApp = { $sched.Hide(); Start-Process $AppUrl }

# Всплывающая панель дня в стиле Awqat: шапка, статусы молитв, аят
$HijriMonths = @("Мухаррам","Сафар","Раби I","Раби II","Джумада I","Джумада II","Раджаб","Шаабан","Рамадан","Шавваль","Зуль-каада","Зуль-хиджа")
$WeekDays = @("воскресенье","понедельник","вторник","среда","четверг","пятница","суббота")
$sched = New-Object System.Windows.Forms.Form
$sched.FormBorderStyle = "None"
$sched.TopMost = $true
$sched.ShowInTaskbar = $false
$sched.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$sched.Opacity = 0.95
$sched.Size = New-Object System.Drawing.Size(220, 352)
$shTitle = New-Object System.Windows.Forms.Label
$shTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$shTitle.ForeColor = [System.Drawing.Color]::FromArgb(212,175,55)
$shTitle.AutoSize = $true
$shTitle.Location = New-Object System.Drawing.Point(12, 8)
$shTitle.Text = "Намаз"
$sched.Controls.Add($shTitle)
$shDay = New-Object System.Windows.Forms.Label
$shDay.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$shDay.ForeColor = [System.Drawing.Color]::FromArgb(170,170,170)
$shDay.AutoSize = $true
$shDay.Location = New-Object System.Drawing.Point(12, 32)
$sched.Controls.Add($shDay)
$shHijri = New-Object System.Windows.Forms.Label
$shHijri.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$shHijri.ForeColor = [System.Drawing.Color]::FromArgb(170,170,170)
$shHijri.AutoSize = $true
$shHijri.Location = New-Object System.Drawing.Point(12, 50)
$sched.Controls.Add($shHijri)
$shPlace = New-Object System.Windows.Forms.Label
$shPlace.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$shPlace.ForeColor = [System.Drawing.Color]::FromArgb(170,170,170)
$shPlace.AutoSize = $true
$shPlace.Location = New-Object System.Drawing.Point(12, 68)
$sched.Controls.Add($shPlace)
$sSt = @{}; $sNm = @{}; $sTm = @{}
$y = 96
foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) {
  $l1 = New-Object System.Windows.Forms.Label
  $l1.Font = New-Object System.Drawing.Font("Segoe UI", 11)
  $l1.AutoSize = $true
  $l1.Location = New-Object System.Drawing.Point(12, $y)
  $l2 = New-Object System.Windows.Forms.Label
  $l2.Font = New-Object System.Drawing.Font("Segoe UI", 11)
  $l2.ForeColor = [System.Drawing.Color]::White
  $l2.AutoSize = $true
  $l2.Location = New-Object System.Drawing.Point(38, $y)
  $l2.Text = $RU[$k]
  $l3 = New-Object System.Windows.Forms.Label
  $l3.Font = New-Object System.Drawing.Font("Segoe UI", 11)
  $l3.ForeColor = [System.Drawing.Color]::White
  $l3.Size = New-Object System.Drawing.Size(70, 20)
  $l3.Location = New-Object System.Drawing.Point(136, $y)
  $l3.TextAlign = "MiddleRight"
  $sched.Controls.Add($l1); $sched.Controls.Add($l2); $sched.Controls.Add($l3)
  $sSt[$k] = $l1; $sNm[$k] = $l2; $sTm[$k] = $l3
  $y += 30
}
$ayah = New-Object System.Windows.Forms.Label
$ayah.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$ayah.ForeColor = [System.Drawing.Color]::FromArgb(255,233,168)
$ayah.Size = New-Object System.Drawing.Size(196, 56)
$ayah.Location = New-Object System.Drawing.Point(12, 284)
$ayah.TextAlign = "MiddleCenter"
$ayah.Text = "إن الصلاة كانت على المؤمنين كتابا موقوتا"
$sched.Controls.Add($ayah)
$dayClick = {
  $now2 = Get-Date
  $nextK = $null
  foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) { if ((To-Date $script:timings.$k) -gt $now2) { $nextK = $k; break } }
  if (-not $nextK) { $nextK = "Fajr" }
  $hc = New-Object System.Globalization.HijriCalendar
  $shDay.Text = $WeekDays[[int]$now2.DayOfWeek]
  $shHijri.Text = "{0} {1} {2}" -f $hc.GetDayOfMonth($now2), $HijriMonths[$hc.GetMonth($now2)-1], $hc.GetYear($now2)
  $shPlace.Text = $Place
  $gold = [System.Drawing.Color]::FromArgb(212,175,55)
  $gray = [System.Drawing.Color]::FromArgb(150,150,150)
  $white = [System.Drawing.Color]::White
  foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) {
    $sTm[$k].Text = $script:timings.$k.Substring(0,5)
    if ($k -eq $nextK) { $sSt[$k].Text = "→"; $sSt[$k].ForeColor = $gold; $sNm[$k].ForeColor = $gold; $sTm[$k].ForeColor = $gold }
    elseif ((To-Date $script:timings.$k) -lt $now2) { $sSt[$k].Text = "✓"; $sSt[$k].ForeColor = $gray; $sNm[$k].ForeColor = $gray; $sTm[$k].ForeColor = $gray }
    else { $sSt[$k].Text = "○"; $sSt[$k].ForeColor = $white; $sNm[$k].ForeColor = $white; $sTm[$k].ForeColor = $white }
  }
  $sched.Location = New-Object System.Drawing.Point($panel.Left, ($panel.Top - 362))
  if ($sched.Visible) { $sched.Hide() } else { $sched.Show() }
}
foreach ($c in @($panel, $pic, $lblMain, $lblSub)) { $c.Add_Click($dayClick); $c.Add_DoubleClick($openApp) }
$sched.Add_Deactivate({ $sched.Hide() })
# Плашка зафиксирована: перетаскивание отключено, позиция только рядом с погодой

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({
try {
  $now = Get-Date
  if ((Get-Date).ToString("dd-MM-yyyy") -ne $script:day) { $script:timings = Get-Timings; $script:day = (Get-Date).ToString("dd-MM-yyyy") }
  $next = $null
  foreach ($k in $Order) { $d = To-Date $script:timings.$k; if ($d -gt $now) { $next = @{ key=$k; date=$d }; break } }
  if (-not $next) { $d = (To-Date $script:timings.Fajr).AddDays(1); $next = @{ key="Fajr"; date=$d } }
  $s = [int]($next.date - $now).TotalSeconds
  $cd = "{0:00}:{1:00}:{2:00}" -f ($s/3600), (($s%3600)/60), ($s%60)
  $scr = [System.Windows.Forms.Screen]::PrimaryScreen
  $b = $scr.Bounds; $w = $scr.WorkingArea
  if ($w.Bottom -lt $b.Bottom) { $panel.Location = New-Object System.Drawing.Point(($w.Left + 140), $w.Bottom) }
  elseif ($w.Top -gt $b.Top) { $panel.Location = New-Object System.Drawing.Point(($w.Left + 140), ($w.Top - 48)) }
  elseif ($w.Left -gt $b.Left) { $panel.Location = New-Object System.Drawing.Point($w.Left, ($w.Bottom - 58)) }
  else { $panel.Location = New-Object System.Drawing.Point(($w.Right - 220), ($w.Bottom - 58)) }
  $show = $true
  if ($b.Equals($w)) { $show = $false }
  else {
    $fg = [WinApi]::GetForegroundWindow()
    $rc = New-Object WinApi+RECT
    if ([WinApi]::GetWindowRect($fg, [ref]$rc)) {
      if (($rc.Right - $rc.Left) -ge $b.Width -and ($rc.Bottom - $rc.Top) -ge $b.Height) { $show = $false }
    }
  }
  $vis = ($show -and -not $script:userHidden)
  if ($panel.Visible -ne $vis) { $panel.Visible = $vis; Log ("panel visible -> " + $vis) }
  if ($panel.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { try { $panel.WindowState = [System.Windows.Forms.FormWindowState]::Normal; Log "panel restored from minimized" } catch {} }
  if ($vis) { try { [void][WinApi]::SetWindowPos($panel.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0033) } catch {} }
  $ni.Text = "{0} {1} -{2}" -f $RU[$next.key], $next.date.ToString("HH:mm"), $cd
  $short = if ($s -ge 3600) { "{0}ч" -f [int]($s/3600) } else { "{0}м" -f [int]($s/60) }
  try { $old = $ni.Icon; $ni.Icon = New-CountdownIcon $short; if ($old) { $old.Dispose() } } catch {}
  $lblMain.Text = "{0} {1}" -f $RU[$next.key], $next.date.ToString("HH:mm")
  $hh = [int]($s/3600); $mm = [int](($s%3600)/60)
  if ($hh -gt 0) { $lblSub.Text = "осталось {0} ч {1} мин" -f $hh, $mm } else { $lblSub.Text = "осталось {0} мин" -f $mm }
  $dk = "{0}_{1}" -f $next.key, (Get-Date).ToString("yyyy-MM-dd")
  if ($s -le 600 -and $s -gt 540 -and $next.key -ne "Sunrise" -and $script:last10 -ne $dk) { $script:last10 = $dk
    $ni.ShowBalloonTip(10000, "Подготовка к молитве", ("{0} через 10 минут ({1}). Соверши вуду." -f $RU[$next.key], $next.date.ToString("HH:mm")), [System.Windows.Forms.ToolTipIcon]::Info) }
  if ($s -le 5 -and $script:last0 -ne $dk) { $script:last0 = $dk
    if ($next.key -eq "Sunrise") { $ni.ShowBalloonTip(10000, "Восход", "Время Фаджра вышло.", [System.Windows.Forms.ToolTipIcon]::Info) }
    else { $ni.ShowBalloonTip(10000, "Время намаза", ("Начался: {0}." -f $RU[$next.key]), [System.Windows.Forms.ToolTipIcon]::Info) } }
} catch { Log ("TICK-ERR: " + $_.Exception.Message) }
})
$script:day = (Get-Date).ToString("dd-MM-yyyy")
$script:last10 = ""; $script:last0 = ""
$timer.Start()
$panel.Show()
try { $ex = [WinApi]::GetWindowLongPtr($panel.Handle, -20); [void][WinApi]::SetWindowLongPtr($panel.Handle, -20, [IntPtr](([int64]$ex -bor 0x80))) } catch {}
Log "Виджет запущен"
$ni.ShowBalloonTip(5000, "Намаз-виджет", "Виджет запущен. Наведи на значок в трее.", [System.Windows.Forms.ToolTipIcon]::Info)
[System.Windows.Forms.Application]::Run($ctx)
$timer.Stop(); $ni.Dispose()
Log "Виджет остановлен"
