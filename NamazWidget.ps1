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
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int n, IntPtr v);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { "C:\dev\namaz-app" }
if (-not $ScriptDir) { $ScriptDir = "C:\dev\namaz-app" }

$PidFile = Join-Path $ScriptDir "widget.pid"
try {
  $myId = $PID
  $myParent = 0
  try {
    $myProc = Get-CimInstance Win32_Process -Filter "ProcessId = $myId" -ErrorAction SilentlyContinue
    if ($myProc) { $myParent = $myProc.ParentProcessId }
  } catch {}

  if (Test-Path -LiteralPath $PidFile) {
    try {
      $oldPid = [int](Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue)
      if ($oldPid -and $oldPid -ne $myId -and $oldPid -ne $myParent) {
        $p = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -like "*powershell*") {
          Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        }
      }
    } catch {}
  }
  [System.IO.File]::WriteAllText($PidFile, $myId.ToString(), [System.Text.Encoding]::ASCII)
} catch {}
$ConfigFile = Join-Path $ScriptDir "config.json"
$Lat = 45.1342; $Lon = 33.60; $Method = 3; $School = 1; $Place = "Саки"
$Lang = "ru"; $StartupOn = $true; $ShowCD = $true; $ShowSec = $false; $Compact = $false; $RemMin = 10; $Theme = "gold"
if (Test-Path -LiteralPath $ConfigFile) {
  try { $cfg = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.latitude -ne $null) { $Lat = $cfg.latitude }
    if ($cfg.longitude -ne $null) { $Lon = $cfg.longitude }
    if ($cfg.method -ne $null) { $Method = $cfg.method }
    if ($cfg.school -ne $null) { $School = $cfg.school }
    if ($cfg.place -ne $null -and $cfg.place -ne "") { $Place = $cfg.place }
    if ($cfg.lang -ne $null) { $Lang = $cfg.lang }
    if ($cfg.startup -ne $null) { $StartupOn = [bool]$cfg.startup }
    if ($cfg.showCountdown -ne $null) { $ShowCD = [bool]$cfg.showCountdown }
    if ($cfg.showSeconds -ne $null) { $ShowSec = [bool]$cfg.showSeconds }
    if ($cfg.compact -ne $null) { $Compact = [bool]$cfg.compact }
    if ($cfg.reminderMinutes -ne $null) { $RemMin = [int]$cfg.reminderMinutes }
    if ($cfg.theme -ne $null -and $cfg.theme -ne "") { $Theme = [string]$cfg.theme }
  } catch {}
}
$STR = @{
  ru = @{ prep="Подготовка к молитве"; prepBody="{0} через {1} мин ({2}). Соверши вуду."; time="Время намаза"; started="Начался: {0}."; sunrise="Восход"; fajrOut="Время Фаджра вышло."; left="осталось"; h="ч"; m="мин" }
  tt = @{ prep="Намазга әзерлек"; prepBody="{0} {1} минуттан соң ({2}). Тәһарәт ал."; time="Намаз вакыты"; started="Башланды: {0}."; sunrise="Кояш чыгу"; fajrOut="Иртәнге намаз вакыты чыкты."; left="калды"; h="сәг"; m="мин" }
  en = @{ prep="Prayer reminder"; prepBody="{0} in {1} min ({2}). Make wudu."; time="Prayer time"; started="{0} started."; sunrise="Shuruq"; fajrOut="Fajr time is over."; left="left"; h="h"; m="min" }
}
$NamesRU = @{ Fajr="Фаджр"; Sunrise="Восход"; Dhuhr="Зухр"; Asr="Аср"; Maghrib="Магриб"; Isha="Иша" }
$NamesTT = @{ Fajr="Иртәнге"; Sunrise="Кояш чыгу"; Dhuhr="Өйлә"; Asr="Икенде"; Maghrib="Ахшам"; Isha="Ястү" }
$NamesEN = @{ Fajr="Fajr"; Sunrise="Shuruq"; Dhuhr="Dhuhr"; Asr="Asr"; Maghrib="Maghrib"; Isha="Isha" }
function Update-Lang {
  if ($Lang -eq "tt") { $script:Names = $NamesTT; $script:T = $STR.tt }
  elseif ($Lang -eq "en") { $script:Names = $NamesEN; $script:T = $STR.en }
  else { $script:Names = $NamesRU; $script:T = $STR.ru }
}
Update-Lang
# Саки, Egypt-метод (сверен с islam.global), Ханафи
$AppUrl = "https://remageht.github.io/namaz-vakit/"

function Get-NamazAppExe {
  # 0) распакованное приложение в desktop/dist/win-unpacked
  $unpacked = Join-Path $ScriptDir "desktop\dist\win-unpacked\Namaz.exe"
  if (Test-Path -LiteralPath $unpacked) { return $unpacked }
  # 1) ярлык на рабочем столе от установщика
  try {
    $desk = [Environment]::GetFolderPath("Desktop")
    foreach ($nm in @("Намаз.lnk", "Namaz.lnk")) {
      $lnk = Join-Path $desk $nm
      if (Test-Path -LiteralPath $lnk) {
        $ws = New-Object -ComObject WScript.Shell
        $tp = $ws.CreateShortcut($lnk).TargetPath
        if ($tp -and (Test-Path -LiteralPath $tp)) { return $tp }
      }
    }
  } catch {}
  # 2) записи установщика в реестре
  foreach ($root in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    try {
      $hit = $null
      Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.DisplayName -match "Namaz" -and $p.InstallLocation) {
          $exe = Join-Path $p.InstallLocation "Namaz.exe"
          if (Test-Path -LiteralPath $exe) { $hit = $exe }
        }
      }
      if ($hit) { return $hit }
    } catch {}
  }
  # 3) типовые папки установки
  foreach ($c in @(
      (Join-Path $env:LOCALAPPDATA "Programs\Namaz\Namaz.exe"),
      (Join-Path $env:LOCALAPPDATA "Programs\namaz-desktop\Namaz.exe"),
      (Join-Path $env:ProgramFiles "Namaz\Namaz.exe"))) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Open-NamazApp {
  $exe = Get-NamazAppExe
  if ($exe) { Start-Process -FilePath $exe; return }
  # dev-режим: Electron из папки desktop
  $devDir = Join-Path $ScriptDir "desktop"
  $dev = Join-Path $devDir "node_modules\electron\dist\electron.exe"
  if (Test-Path -LiteralPath $dev) {
    if (-not (Test-Path -LiteralPath (Join-Path $devDir "app\index.html"))) {
      try { Start-Process -FilePath "node" -ArgumentList "sync-assets.js" -WorkingDirectory $devDir -Wait -WindowStyle Hidden } catch {}
    }
    if (Test-Path -LiteralPath (Join-Path $devDir "app\index.html")) {
      Start-Process -FilePath $dev -ArgumentList @("`"$devDir`"") -WorkingDirectory $devDir
      return
    }
  }
  Start-Process $AppUrl
}
$LogFile = Join-Path $ScriptDir "widget.log"
$CacheFile = Join-Path $env:TEMP "namaz_timings.json"
$Order = @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")

function Log($m){
  try {
    Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m) -Encoding UTF8
  } catch {}
}

function Calc-PrayerTimes([double]$lat, [double]$lon, [datetime]$date) {
  $pi = [Math]::PI; $dr = $pi / 180.0
  $yr = $date.Year; $mo = $date.Month; $dy = $date.Day
  if ($mo -le 2) { $yr -= 1; $mo += 12 }
  $A = [Math]::Floor($yr / 100); $B = 2 - $A + [Math]::Floor($A / 4)
  $jd = [Math]::Floor(365.25 * ($yr + 4716)) + [Math]::Floor(30.6001 * ($mo + 1)) + $dy + $B - 1524.5
  $D = $jd - 2451545.0
  $g = (357.529 + 0.98560028 * $D) % 360; if ($g -lt 0) { $g += 360 }
  $q = (280.459 + 0.98564736 * $D) % 360; if ($q -lt 0) { $q += 360 }
  $L = ($q + 1.915 * [Math]::Sin($g * $dr) + 0.020 * [Math]::Sin(2 * $g * $dr)) % 360; if ($L -lt 0) { $L += 360 }
  $e = 23.439 - 0.00000036 * $D
  $dec = [Math]::Asin([Math]::Sin($e * $dr) * [Math]::Sin($L * $dr)) / $dr
  $RA = [Math]::Atan2([Math]::Cos($e * $dr) * [Math]::Sin($L * $dr), [Math]::Cos($L * $dr)) / $dr
  $RA = ($RA % 360 + 360) % 360
  $EqT = ($q - $RA) / 15.0
  while ($EqT -gt 12) { $EqT -= 24 }; while ($EqT -lt -12) { $EqT += 24 }

  $tz = [TimeZoneInfo]::Local.GetUtcOffset($date).TotalHours
  $Tnoon = 12.0 + $tz - ($lon / 15.0) - $EqT

  function fHA([double]$altDeg) {
    $cosH = ([Math]::Sin($altDeg * $dr) - [Math]::Sin($lat * $dr) * [Math]::Sin($dec * $dr)) / ([Math]::Cos($lat * $dr) * [Math]::Cos($dec * $dr))
    if ($cosH -gt 1.0) { $cosH = 1.0 } elseif ($cosH -lt -1.0) { $cosH = -1.0 }
    return [Math]::Acos($cosH) / $dr / 15.0
  }

  $asrFactor = if ($School -eq 0) { 1.0 } else { 2.0 }
  $asrAlt = [Math]::Atan(1.0 / ($asrFactor + [Math]::Tan([Math]::Abs($lat - $dec) * $dr))) / $dr

  # Углы Fajr и Isha в соответствии с выбранным методом
  $fajrAngle = if ($Method -eq 3) { 19.5 } elseif ($Method -eq 14) { 16.0 } elseif ($Method -eq 1) { 18.0 } else { 18.0 }
  $ishaAngle = if ($Method -eq 3) { 17.5 } elseif ($Method -eq 14) { 15.0 } elseif ($Method -eq 1) { 18.0 } else { 17.0 }

  $fajr    = $Tnoon - (fHA (-$fajrAngle))
  $sunrise = $Tnoon - (fHA (-0.8333))
  $dhuhr   = $Tnoon
  $asr     = $Tnoon + (fHA ($asrAlt))
  $maghrib = $Tnoon + (fHA (-0.8333))
  $isha    = $Tnoon + (fHA (-$ishaAngle))

  function fFmt([double]$h) {
    $h = ($h % 24 + 24) % 24
    $hh = [Math]::Floor($h); $mm = [Math]::Round(($h - $hh) * 60)
    if ($mm -eq 60) { $hh += 1; $mm = 0 }
    "{0:00}:{1:00}" -f [int]$hh, [int]$mm
  }

  return [PSCustomObject]@{
    Fajr    = fFmt $fajr
    Sunrise = fFmt $sunrise
    Dhuhr   = fFmt $dhuhr
    Asr     = fFmt $asr
    Maghrib = fFmt $maghrib
    Isha    = fFmt $isha
  }
}
function Compare-Timings($a, $b) {
  $maxDiff = 0
  foreach ($k in @("Fajr","Dhuhr","Asr","Maghrib","Isha")) {
    try {
      $p1 = $a.$k.Substring(0,5).Split(":"); $p2 = $b.$k.Substring(0,5).Split(":")
      $diff = [Math]::Abs([int]$p1[0]*60+[int]$p1[1] - ([int]$p2[0]*60+[int]$p2[1]))
      if ($diff -gt $maxDiff) { $maxDiff = $diff }
    } catch {}
  }
  return $maxDiff
}

function Get-Timings {
  $today = (Get-Date).ToString("dd-MM-yyyy")
  if (Test-Path -LiteralPath $CacheFile) {
    try { $c = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
      if ($c.date -eq $today) { return $c.timings } } catch {}
  }
  try {
    $r = Invoke-RestMethod -Uri "https://api.aladhan.com/v1/timings/${today}?latitude=${Lat}&longitude=${Lon}&method=${Method}&school=${School}" -TimeoutSec 15
    $t = $r.data.timings
    try { $off = Calc-PrayerTimes $Lat $Lon (Get-Date); $maxD = Compare-Timings $t $off
      if ($maxD -gt 2) { Log "WARN офлайн-расхождение ${maxD} мин" } else { Log "Офлайн сверка OK лтч${maxD} мин" }
    } catch {}
    @{ date = $today; timings = $t } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $CacheFile
    Log "Время загружено: Фаджр $($t.Fajr), Иша $($t.Isha)"
    return $t
  } catch {
    Log "API ошибка: $($_.Exception.Message) — офлайн-расчёт"
    $off = Calc-PrayerTimes $Lat $Lon (Get-Date)
    Log "Офлайн: Фаджр $($off.Fajr), Иша $($off.Isha)"
    return $off
  }
}

$script:timings = Get-Timings
$timings = $script:timings
if (-not $timings) { [System.Windows.Forms.MessageBox]::Show("Ошибка расчёта времени намаза."); exit 1 }

function To-Date($t) {
  if (-not $t) { return (Get-Date) }
  try {
    $parts = $t.Substring(0,5).Split(":")
    $h = [int]$parts[0]; $mi = [int]$parts[1]; $d = Get-Date
    return (Get-Date -Year $d.Year -Month $d.Month -Day $d.Day -Hour $h -Minute $mi -Second 0)
  } catch {
    return (Get-Date)
  }
}

# Стартовая иконка: полумесяц из icon-192.png, иначе стандартная
$icon = [System.Drawing.SystemIcons]::Information
try {
  $p = Join-Path $ScriptDir "icon-192.png"
  if (Test-Path -LiteralPath $p) {
    $b0 = New-Object System.Drawing.Bitmap($p)
    $icon = [System.Drawing.Icon]::FromHandle($b0.GetHicon())
    $b0.Dispose()
  }
} catch {}

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $icon; $ni.Visible = $true
$ctx = New-Object System.Windows.Forms.ApplicationContext

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add("Открыть приложение"); $open.Add_Click({ Open-NamazApp })
$ref = $menu.Items.Add("Обновить время"); $ref.Add_Click({ $script:timings = Get-Timings })
$script:userHidden = $false
$tMenu = $menu.Items.Add("Тема оформления")
$tG = $tMenu.DropDownItems.Add("Золотая (Gold)"); $tG.Add_Click({ Apply-Theme "gold"; Save-Config })
$tGr = $tMenu.DropDownItems.Add("Изумрудная (Green)"); $tGr.Add_Click({ Apply-Theme "green"; Save-Config })
$tM = $tMenu.DropDownItems.Add("Монохром (Mono)"); $tM.Add_Click({ Apply-Theme "mono"; Save-Config })
$lMenu = $menu.Items.Add("Язык / Тел / Language")
$lRu = $lMenu.DropDownItems.Add("Русский (RU)"); $lRu.Add_Click({ $script:Lang = "ru"; Update-Lang; Save-Config })
$lTt = $lMenu.DropDownItems.Add("Татарча (TT)"); $lTt.Add_Click({ $script:Lang = "tt"; Update-Lang; Save-Config })
$lEn = $lMenu.DropDownItems.Add("English (EN)"); $lEn.Add_Click({ $script:Lang = "en"; Update-Lang; Save-Config })
$tog = $menu.Items.Add("Скрыть панель"); $tog.Add_Click({ $script:userHidden = -not $script:userHidden; $tog.Text = if ($script:userHidden) { "Показать панель" } else { "Скрыть панель" } })
$exit = $menu.Items.Add("Выход"); $exit.Add_Click({ try { Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue } catch {}; $ni.Visible = $false; $sched.Close(); $panel.Close(); $ctx.ExitThread() })
$ni.ContextMenuStrip = $menu
$ni.Add_DoubleClick({ Open-NamazApp })

# Мини-панель в стиле виджета погоды: иконка + две строки, слева внизу рядом с погодой
function New-AppFont($size, $bold) {
  try {
    if ($bold) { return New-Object System.Drawing.Font("Segoe UI Variable Display", $size, [System.Drawing.FontStyle]::Bold) }
    return New-Object System.Drawing.Font("Segoe UI Variable Text", $size)
  } catch {}
  if ($bold) { return New-Object System.Drawing.Font("Segoe UI", $size, [System.Drawing.FontStyle]::Bold) }
  return New-Object System.Drawing.Font("Segoe UI", $size)
}
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
$panel.BackColor = [System.Drawing.Color]::FromArgb(16, 32, 26)
$panel.Opacity = 0.94
$panel.Size = New-Object System.Drawing.Size(160, 48)
$panel.Controls.Add($pic)
$panel.Controls.Add($lblMain)
$panel.Controls.Add($lblSub)
$scr = [System.Windows.Forms.Screen]::PrimaryScreen
$b = $scr.Bounds
$w = $scr.WorkingArea
$wa = $w
$panel.Location = New-Object System.Drawing.Point(($wa.Left + 20), ($wa.Bottom - $panel.Height - 10))
$lblMain.Text = "Загрузка..."
$panel.Show()
try { [void][WinApi]::ShowWindow($panel.Handle, 5); [void][WinApi]::SetWindowPos($panel.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0053) } catch {}
$openApp = { $sched.Hide(); Open-NamazApp }

# Всплывающая панель дня в стиле Awqat: шапка, статусы молитв, аят
$HijriMonths = @("Мухаррам","Сафар","Раби I","Раби II","Джумада I","Джумада II","Раджаб","Шаабан","Рамадан","Шавваль","Зуль-каада","Зуль-хиджа")
$WeekDays = @("воскресенье","понедельник","вторник","среда","четверг","пятница","суббота")
$AN = @(
@("الله","Аллах","Бог — Единственный, достойный поклонения"),
@("الرحمن","Ар-Рахман","Милостивый ко всем творениям"),
@("الرحيم","Ар-Рахим","Милосердный к верующим"),
@("الملك","Аль-Малик","Властелин всего сущего"),
@("القدوس","Аль-Куддус","Святой, Пречистый от недостатков"),
@("السلام","Ас-Салям","Дарующий мир и благополучие"),
@("المؤمن","Аль-Мумин","Дарующий безопасность и веру"),
@("المهيمن","Аль-Мухаймин","Хранитель и Наблюдающий за всем"),
@("العزيز","Аль-Азиз","Могущественный, Непобедимый"),
@("الجبار","Аль-Джаббар","Подчиняющий всё Своей воле"),
@("المتكبر","Аль-Мутакаббир","Превознесённый над недостатками"),
@("الخالق","Аль-Халик","Творец всего"),
@("البارئ","Аль-Бари","Создатель из небытия"),
@("المصور","Аль-Мусаввир","Дарующий облик творениям"),
@("الغفار","Аль-Гаффар","Всепрощающий"),
@("القهار","Аль-Каххар","Всеподчиняющий Своему могуществу"),
@("الوهاب","Аль-Ваххаб","Дарующий безмерно"),
@("الرزاق","Ар-Раззак","Наделяющий уделом"),
@("الفتاح","Аль-Фаттах","Открывающий милость и победу"),
@("العليم","Аль-Алим","Всезнающий"),
@("القابض","Аль-Кабид","Удерживающий удел"),
@("الباسط","Аль-Басит","Простирающий удел"),
@("الخافض","Аль-Хафид","Унижающий высокомерных"),
@("الرافع","Ар-Рафи","Возвышающий достойных"),
@("المعز","Аль-Муизз","Дарующий могущество"),
@("المذل","Аль-Музилль","Принижающий ослушников"),
@("السميع","Ас-Сами","Всеслышащий"),
@("البصير","Аль-Басир","Всевидящий"),
@("الحكم","Аль-Хакам","Справедливый Судья"),
@("العدل","Аль-Адль","Абсолютно Справедливый"),
@("اللطيف","Аль-Латиф","Добрый и Проницательный"),
@("الخبير","Аль-Хабир","Всесведущий о сокровенном"),
@("الحليم","Аль-Халим","Снисходительный к ослушникам"),
@("العظيم","Аль-Азым","Великий"),
@("الغفور","Аль-Гафур","Много прощающий"),
@("الشكور","Аш-Шакур","Воздающий за малое многим"),
@("العلي","Аль-Алий","Всевышний"),
@("الكبير","Аль-Кабир","Величайший"),
@("الحفيظ","Аль-Хафиз","Хранящий всё"),
@("المقيت","Аль-Мукит","Дарующий пропитание, Всевластный"),
@("الحسيب","Аль-Хасиб","Достаточный, Требующий отчёта"),
@("الجليل","Аль-Джалиль","Величественный"),
@("الكريم","Аль-Карим","Щедрый"),
@("الرقيب","Ар-Ракиб","Наблюдающий за всем"),
@("المجيب","Аль-Муджиб","Отвечающий на мольбы"),
@("الواسع","Аль-Васи","Всеобъемлющий"),
@("الحكيم","Аль-Хаким","Мудрый"),
@("الودود","Аль-Вадуд","Любящий Своих рабов"),
@("المجيد","Аль-Маджид","Славный"),
@("الباعث","Аль-Баис","Воскрешающий мёртвых"),
@("الشهيد","Аш-Шахид","Свидетель всего"),
@("الحق","Аль-Хакк","Истинный, Вечная истина"),
@("الوكيل","Аль-Вакиль","Попечитель, на Кого полагаются"),
@("القوي","Аль-Кавий","Сильный"),
@("المتين","Аль-Матин","Незыблемый, Прочный"),
@("الولي","Аль-Валий","Покровитель верующих"),
@("الحميد","Аль-Хамид","Достохвальный"),
@("المحصي","Аль-Мухси","Исчисляющий всё"),
@("المبدئ","Аль-Мубди","Начинающий творение"),
@("المعيد","Аль-Муид","Возвращающий к жизни"),
@("المحيي","Аль-Мухйи","Оживляющий"),
@("المميت","Аль-Мумит","Умерщвляющий"),
@("الحي","Аль-Хайй","Вечно Живой"),
@("القيوم","Аль-Каййум","Сущий, Держатель всего"),
@("الواجد","Аль-Ваджид","Находящий, ни в чём не нуждающийся"),
@("الماجد","Аль-Маджид","Благородный"),
@("الواحد","Аль-Вахид","Единственный"),
@("الصمد","Ас-Самад","Самодостаточный, к Кому обращаются"),
@("القادر","Аль-Кадир","Всемогущий"),
@("المقتدر","Аль-Муктадир","Могущественный во всём"),
@("المقدم","Аль-Мукаддим","Выдвигающий вперёд, кого пожелает"),
@("المؤخر","Аль-Муаххир","Отодвигающий, кого пожелает"),
@("الأول","Аль-Авваль","Первый — до Него ничего не было"),
@("الآخر","Аль-Ахир","Последний — после Него ничего не будет"),
@("الظاهر","Аз-Захир","Явный, Очевидный"),
@("الباطن","Аль-Батин","Скрытый от взоров"),
@("الوالي","Аль-Вали","Правитель всего"),
@("المتعالي","Аль-Мутаали","Превознесённый над всем"),
@("البر","Аль-Барр","Благодетельный"),
@("التواب","Ат-Тавваб","Принимающий покаяние"),
@("المنتقم","Аль-Мунтаким","Воздающий непокорным"),
@("العفو","Аль-Афувв","Изглаживающий грехи"),
@("الرؤوف","Ар-Рауф","Сострадательный"),
@("مالك الملك","Малик-уль-Мульк","Владыка всякого владычества"),
@("ذو الجلال والإكرام","Зу-ль-Джаляли валь-Икрам","Обладатель величия и почёта"),
@("المقسط","Аль-Муксит","Воздающий по справедливости"),
@("الجامع","Аль-Джами","Собирающий людей в Судный день"),
@("الغني","Аль-Ганий","Богатый, ни в чём не нуждающийся"),
@("المغني","Аль-Мугни","Обогащающий, кого пожелает"),
@("المانع","Аль-Мани","Удерживающий зло и вред"),
@("الضار","Ад-Дарр","Вредящий по Своей мудрости"),
@("النافع","Ан-Нафи","Приносящий пользу"),
@("النور","Ан-Нур","Свет небес и земли"),
@("الهادي","Аль-Хади","Ведущий прямым путём"),
@("البديع","Аль-Бади","Бесподобный Творец"),
@("الباقي","Аль-Баки","Вечный, Пребывающий"),
@("الوارث","Аль-Варис","Наследующий всё сущее"),
@("الرشيد","Ар-Рашид","Направляющий к правильному"),
@("الصبور","Ас-Сабур","Терпеливый к ослушникам")
)
$NamesStartFile = Join-Path $ScriptDir "names_start.txt"
if (-not (Test-Path -LiteralPath $NamesStartFile)) { (Get-Date).ToString("yyyy-MM-dd") | Set-Content -LiteralPath $NamesStartFile -Encoding UTF8 }
function Get-NameIdx {
  try { $ns = [datetime]::ParseExact(((Get-Content -LiteralPath $NamesStartFile -Raw).Trim()), "yyyy-MM-dd", $null) }
  catch { $ns = (Get-Date).Date }
  $d = [int](((Get-Date).Date - $ns).TotalDays)
  return ((($d % $AN.Count) + $AN.Count) % $AN.Count)
}
$sched = New-Object System.Windows.Forms.Form
$sched.FormBorderStyle = "None"
$sched.StartPosition = "Manual"
$sched.TopMost = $true
$sched.ShowInTaskbar = $false
$sched.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$sched.Opacity = 0.95
$sched.Size = New-Object System.Drawing.Size(220, 400)
$shName = New-Object System.Windows.Forms.Label
$shName.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$shName.ForeColor = [System.Drawing.Color]::FromArgb(212,175,55)
$shName.AutoSize = $true
$shName.MaximumSize = New-Object System.Drawing.Size(196, 0)
$shName.Location = New-Object System.Drawing.Point(12, 86)
$sched.Controls.Add($shName)
$shTitle = New-Object System.Windows.Forms.Label
$shTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$shTitle.ForeColor = [System.Drawing.Color]::FromArgb(212,175,55)
$shTitle.AutoSize = $true
$shTitle.Location = New-Object System.Drawing.Point(12, 8)
$shTitle.Text = "Намаз"
$sched.Controls.Add($shTitle)
$gear = New-Object System.Windows.Forms.Label
$gear.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$gear.ForeColor = [System.Drawing.Color]::FromArgb(170,170,170)
$gear.AutoSize = $true
$gear.Location = New-Object System.Drawing.Point(192, 6)
$gear.Text = "⚙"
$gear.Cursor = "Hand"
$sched.Controls.Add($gear)
$gear.Add_Click({ Show-Settings })
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
$y = 140
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
  $l2.Text = $Names[$k]
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
$ayah.Location = New-Object System.Drawing.Point(12, 330)
$ayah.TextAlign = "MiddleCenter"
$ayah.Text = "إن الصلاة كانت على المؤمنين كتابا موقوتا"
$sched.Controls.Add($ayah)
$dayClick = {
  try {
    $now2 = Get-Date
    $nextK = $null
    foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) {
      if ((To-Date $script:timings.$k) -gt $now2) { $nextK = $k; break }
    }
    if (-not $nextK) { $nextK = "Fajr" }
    $hc = New-Object System.Globalization.HijriCalendar
    $shDay.Text = $WeekDays[[int]$now2.DayOfWeek]
    $hMonthIdx = [Math]::Max(0, [Math]::Min(11, ($hc.GetMonth($now2) - 1)))
    $shHijri.Text = "{0} {1} {2}" -f $hc.GetDayOfMonth($now2), $HijriMonths[$hMonthIdx], $hc.GetYear($now2)
    $shPlace.Text = $Place
    $nn = Get-NameIdx
    $shName.Text = "☝ №{0} · {1} · {2} — {3}" -f ($nn + 1), $AN[$nn][0], $AN[$nn][1], $AN[$nn][2]
    $gold = [System.Drawing.Color]::FromArgb(212,175,55)
    $gray = [System.Drawing.Color]::FromArgb(150,150,150)
    $white = [System.Drawing.Color]::White
    foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) {
      $nm = if ($script:Names -and $script:Names[$k]) { $script:Names[$k] } else { $NamesRU[$k] }
      $sNm[$k].Text = $nm
      $rawT = if ($script:timings -and $script:timings.$k) { $script:timings.$k } else { "00:00" }
      $sTm[$k].Text = if ($rawT.Length -ge 5) { $rawT.Substring(0,5) } else { $rawT }
      if ($k -eq $nextK) {
        $sSt[$k].Text = "→"; $sSt[$k].ForeColor = $gold; $sNm[$k].ForeColor = $gold; $sTm[$k].ForeColor = $gold
      } elseif ((To-Date $rawT) -lt $now2) {
        $sSt[$k].Text = "✓"; $sSt[$k].ForeColor = $gray; $sNm[$k].ForeColor = $gray; $sTm[$k].ForeColor = $gray
      } else {
        $sSt[$k].Text = "○"; $sSt[$k].ForeColor = $white; $sNm[$k].ForeColor = $white; $sTm[$k].ForeColor = $white
      }
    }
    [void]$sched.Handle
    $y2 = $shName.Bottom + 6
    $i = 0
    foreach ($k in @("Fajr","Sunrise","Dhuhr","Asr","Maghrib","Isha")) {
      $sSt[$k].Top = $y2 + $i * 30
      $sNm[$k].Top = $y2 + $i * 30
      $sTm[$k].Top = $y2 + $i * 30
      $i++
    }
    $ayah.Top = $y2 + 180 + 8
    $sched.Height = $ayah.Bottom + 12
    $schedX = [Math]::Min([Math]::Max($w.Left + 10, $panel.Left), ($w.Right - $sched.Width - 10))
    $schedY = [Math]::Max($w.Top + 10, ($panel.Top - $sched.Height - 10))
    $sched.Location = New-Object System.Drawing.Point($schedX, $schedY)
    if ($sched.Visible) {
      $sched.Hide()
    } else {
      $sched.Show()
      $sched.BringToFront()
      try { [void][WinApi]::SetWindowPos($sched.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0053) } catch {}
      $sched.Activate()
    }
  } catch {
    Log ("dayClick error: " + $_.Exception.Message)
  }
}
$ni.Add_Click({
  param($s, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { & $dayClick }
})
$script:userMoved = $false
$script:isDragging = $false
$script:hasMoved = $false
$script:dragStart = New-Object System.Drawing.Point(0, 0)
$onMouseDown = {
  param($sender, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    $script:isDragging = $true
    $script:hasMoved = $false
    $script:dragStart = [System.Windows.Forms.Cursor]::Position
    $script:dragOrigin = $panel.Location
  }
}
$onMouseMove = {
  param($sender, $e)
  if ($script:isDragging) {
    $cur = [System.Windows.Forms.Cursor]::Position
    $dx = $cur.X - $script:dragStart.X
    $dy = $cur.Y - $script:dragStart.Y
    if ([Math]::Abs($dx) -gt 6 -or [Math]::Abs($dy) -gt 6) {
      $panel.Location = New-Object System.Drawing.Point(($script:dragOrigin.X + $dx), ($script:dragOrigin.Y + $dy))
      $script:userMoved = $true
      $script:hasMoved = $true
    }
  }
}
$onMouseUp = {
  param($sender, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    $wasDragging = $script:isDragging
    $moved = $script:hasMoved
    $script:isDragging = $false
    $script:hasMoved = $false
    if ($wasDragging -and -not $moved) {
      & $dayClick
    }
  }
}
foreach ($c in @($panel, $pic, $lblMain, $lblSub)) {
  $c.ContextMenuStrip = $menu
  $c.Add_MouseDown($onMouseDown)
  $c.Add_MouseMove($onMouseMove)
  $c.Add_MouseUp($onMouseUp)
  $c.Add_DoubleClick({ & $dayClick })
}
$sched.Add_Deactivate({
  try {
    $pt = [System.Windows.Forms.Cursor]::Position
    if ($panel.Bounds.Contains($pt)) { return }
    $sched.Hide()
  } catch {}
})

function Apply-Compact {
  if ($Compact) {
    $panel.Size = New-Object System.Drawing.Size(130, 40)
    $pic.Size = New-Object System.Drawing.Size(24, 24)
    $pic.Location = New-Object System.Drawing.Point(6, 8)
    $lblMain.Font = New-AppFont 9 $true
    $lblMain.Location = New-Object System.Drawing.Point(36, 1)
    $lblSub.Font = New-AppFont 8 $false
    $lblSub.Location = New-Object System.Drawing.Point(36, 19)
  } else {
    $panel.Size = New-Object System.Drawing.Size(160, 48)
    $pic.Size = New-Object System.Drawing.Size(32, 32)
    $pic.Location = New-Object System.Drawing.Point(8, 8)
    $lblMain.Font = New-AppFont 11 $true
    $lblMain.Location = New-Object System.Drawing.Point(48, 3)
    $lblSub.Font = New-AppFont 9 $false
    $lblSub.Location = New-Object System.Drawing.Point(48, 24)
  }
}

function Apply-Theme($t) {
  $script:Theme = $t
  switch ($t) {
    "green" {
      $script:ThemeAccent = [System.Drawing.Color]::FromArgb(34, 197, 94)
      $script:ThemeSub    = [System.Drawing.Color]::FromArgb(159, 195, 181)
    }
    "mono" {
      $script:ThemeAccent = [System.Drawing.Color]::FromArgb(235, 235, 235)
      $script:ThemeSub    = [System.Drawing.Color]::FromArgb(161, 161, 170)
    }
    default {
      $script:ThemeAccent = [System.Drawing.Color]::FromArgb(212, 175, 55)
      $script:ThemeSub    = [System.Drawing.Color]::FromArgb(247, 232, 164)
    }
  }
  if ($shTitle) { $shTitle.ForeColor = $script:ThemeAccent }
  if ($shName)  { $shName.ForeColor = $script:ThemeAccent }
  if ($lblMain) { $lblMain.ForeColor = $script:ThemeAccent }
  if ($lblSub)  { $lblSub.ForeColor = $script:ThemeSub }
}

function Save-Config {
  @{ latitude=$Lat; longitude=$Lon; method=$Method; school=$School; place=$Place; lang=$Lang; startup=$StartupOn; showCountdown=$ShowCD; showSeconds=$ShowSec; compact=$Compact; reminderMinutes=$RemMin; theme=$Theme } | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

function Set-Startup($on) {
  $lnk = Join-Path ([Environment]::GetFolderPath("Startup")) "Namaz Widget.lnk"
  if ($on) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = "wscript.exe"
    $vbsPath = Join-Path $ScriptDir "Start-NamazWidget.vbs"
    $sc.Arguments = ('"{0}"' -f $vbsPath)
    $sc.WorkingDirectory = $ScriptDir
    $sc.Description = "Namaz Widget"
    $sc.Save()
  } else { if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force } }
}

$settings = New-Object System.Windows.Forms.Form
$settings.Text = "Настройки"
$settings.StartPosition = "CenterScreen"
$settings.FormBorderStyle = "FixedDialog"
$settings.MaximizeBox = $false
$settings.MinimizeBox = $false
$settings.TopMost = $true
$settings.ShowInTaskbar = $false
$settings.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$settings.ForeColor = [System.Drawing.Color]::White
$settings.Size = New-Object System.Drawing.Size(320, 340)
function Add-CB($text, $y) {
  $c = New-Object System.Windows.Forms.CheckBox
  $c.Text = $text; $c.AutoSize = $true
  $c.Location = New-Object System.Drawing.Point(14, $y)
  $c.ForeColor = [System.Drawing.Color]::White
  $c.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
  $settings.Controls.Add($c)
  return $c
}
$slLang = New-Object System.Windows.Forms.Label
$slLang.Text = "Язык / Language"; $slLang.AutoSize = $true
$slLang.Location = New-Object System.Drawing.Point(14, 12)
$slLang.ForeColor = [System.Drawing.Color]::White
$settings.Controls.Add($slLang)
$cbLang = New-Object System.Windows.Forms.ComboBox
$cbLang.Items.Add("Русский") | Out-Null; $cbLang.Items.Add("Татарча") | Out-Null; $cbLang.Items.Add("English") | Out-Null
$cbLang.DropDownStyle = "DropDownList"
$cbLang.Location = New-Object System.Drawing.Point(14, 32)
$cbLang.Width = 200
$settings.Controls.Add($cbLang)
$cbStartup = Add-CB "Автозапуск Windows" 64
$cbCD = Add-CB "Показывать обратный отсчёт" 92
$cbSec = Add-CB "Показывать секунды" 120
$cbCompact = Add-CB "Компактный режим" 148
$slRem = New-Object System.Windows.Forms.Label
$slRem.Text = "Напоминание за (мин, 0=выкл)"; $slRem.AutoSize = $true
$slRem.Location = New-Object System.Drawing.Point(14, 178)
$slRem.ForeColor = [System.Drawing.Color]::White
$settings.Controls.Add($slRem)
$numRem = New-Object System.Windows.Forms.NumericUpDown
$numRem.Minimum = 0; $numRem.Maximum = 60
$numRem.Location = New-Object System.Drawing.Point(14, 198)
$numRem.Width = 80
$settings.Controls.Add($numRem)
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Сохранить"; $btnSave.Location = New-Object System.Drawing.Point(14, 240)
$btnSave.DialogResult = "OK"
$settings.Controls.Add($btnSave)
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Отмена"; $btnCancel.Location = New-Object System.Drawing.Point(110, 240)
$btnCancel.DialogResult = "Cancel"
$settings.Controls.Add($btnCancel)
$settings.AcceptButton = $btnSave
$settings.CancelButton = $btnCancel
function Show-Settings {
  if ($Lang -eq "tt") { $cbLang.SelectedIndex = 1 } elseif ($Lang -eq "en") { $cbLang.SelectedIndex = 2 } else { $cbLang.SelectedIndex = 0 }
  $cbStartup.Checked = $StartupOn
  $cbCD.Checked = $ShowCD
  $cbSec.Checked = $ShowSec
  $cbCompact.Checked = $Compact
  $numRem.Value = $RemMin
  if ($settings.ShowDialog() -eq "OK") {
    if ($cbLang.SelectedIndex -eq 1) { $script:Lang = "tt" } elseif ($cbLang.SelectedIndex -eq 2) { $script:Lang = "en" } else { $script:Lang = "ru" }
    $script:StartupOn = $cbStartup.Checked
    $script:ShowCD = $cbCD.Checked
    $script:ShowSec = $cbSec.Checked
    $script:Compact = $cbCompact.Checked
    $script:RemMin = [int]$numRem.Value
    Update-Lang
    Apply-Compact
Apply-Theme $Theme
    Set-Startup $StartupOn
    Save-Config
    Log "Настройки сохранены"
  }
}
$st = $menu.Items.Add("Настройки")
$st.Add_Click({ Show-Settings })



$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
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
  if (-not $script:userMoved) {
    $defX = $w.Left + 20
    $defY = $w.Bottom - $panel.Height - 10
    if ($panel.Left -ne $defX -or $panel.Top -ne $defY) {
      $panel.Location = New-Object System.Drawing.Point($defX, $defY)
    }
  }
  $vis = (-not $script:userHidden)
  if ($panel.Visible -ne $vis) { $panel.Visible = $vis; Log ("panel visible -> " + $vis) }
  if ($panel.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { try { $panel.WindowState = [System.Windows.Forms.FormWindowState]::Normal; Log "panel restored from minimized" } catch {} }
  if ($vis) { try { [void][WinApi]::SetWindowPos($panel.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0033) } catch {} }
  $nidx = Get-NameIdx
  $tipText = "{0} {1} -{2}" -f $Names[$next.key], $next.date.ToString("HH:mm"), $cd
  if ($tipText.Length -gt 63) { $tipText = $tipText.Substring(0, 63) }
  $ni.Text = $tipText
  $lblMain.Text = "{0} {1}" -f $Names[$next.key], $next.date.ToString("HH:mm")
  $hh = [int]($s/3600); $mm = [int](($s%3600)/60); $ss = [int]($s%60)
  if ($ShowCD) {
    if ($ShowSec) { $lblSub.Text = "{0:00}:{1:00}:{2:00}" -f $hh, $mm, $ss }
    else { $lblSub.Text = "{0:00}:{1:00}" -f $hh, $mm }
  } else { $lblSub.Text = "" }
  $dk = "{0}_{1}" -f $next.key, (Get-Date).ToString("yyyy-MM-dd")
  $rw = $RemMin * 60
  if ($RemMin -gt 0 -and $s -le $rw -and $s -gt ($rw - 60) -and $next.key -ne "Sunrise" -and $script:last10 -ne $dk) { $script:last10 = $dk
    $ni.ShowBalloonTip(10000, $T.prep, ($T.prepBody -f $Names[$next.key], $RemMin, $next.date.ToString("HH:mm")), [System.Windows.Forms.ToolTipIcon]::Info) }
  if ($s -le 5 -and $script:last0 -ne $dk) { $script:last0 = $dk
    if ($next.key -eq "Sunrise") { $ni.ShowBalloonTip(10000, $T.sunrise, $T.fajrOut, [System.Windows.Forms.ToolTipIcon]::Info) }
    else { $ni.ShowBalloonTip(10000, $T.time, ($T.started -f $Names[$next.key]), [System.Windows.Forms.ToolTipIcon]::Info) } }
  # Утреннее уведомление с именем дня — утром (с 06:00 до 11:59)
  $morningKey = "morning_" + (Get-Date).ToString("yyyy-MM-dd")
  if ($now.Hour -ge 6 -and $now.Hour -le 11 -and $script:lastMorning -ne $morningKey) {
    $script:lastMorning = $morningKey
    $ni.ShowBalloonTip(12000, "Имя дня ☝ — №$($nidx+1)", "$($AN[$nidx][0]) · $($AN[$nidx][1])`r`n$($AN[$nidx][2])", [System.Windows.Forms.ToolTipIcon]::Info)
    Log "Утреннее имя: №$($nidx+1) $($AN[$nidx][1])"
  }
} catch { Log ("TICK-ERR: " + $_.Exception.Message) }
})
$script:day = (Get-Date).ToString("dd-MM-yyyy")
$script:last10 = ""; $script:last0 = ""; $script:lastMorning = ""
$timer.Start()
Apply-Compact
Apply-Theme $Theme
try { $ex = [WinApi]::GetWindowLongPtr($panel.Handle, -20); [void][WinApi]::SetWindowLongPtr($panel.Handle, -20, [IntPtr](([int64]$ex -bor 0x80))) } catch {}
try {
  $corner = 2
  [void][WinApi]::DwmSetWindowAttribute($panel.Handle, 33, [ref]$corner, 4)
} catch {}
Log "Виджет запущен"
$ni.ShowBalloonTip(6000, "Намаз — Время молитвы", "Виджет запущен в левом нижнем углу и в трее.", [System.Windows.Forms.ToolTipIcon]::Info)
[System.Windows.Forms.Application]::Run($ctx)
$timer.Stop(); $ni.Dispose(); try { Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue } catch {}
Log "Виджет остановлен"
