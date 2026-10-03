# NamazWidget.ps1 — виджет времени намаза в трее Windows (рядом с часами)
# Показывает следующий намаз + обратный отсчёт, балуны за 10 мин и в начале.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Lat = 45.1342; $Lon = 33.60; $Method = 3; $School = 1   # Саки, Egypt-метод (сверен с islam.global), Ханафи
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

# Иконка: полумесяц из icon-192.png, иначе стандартная
$icon = [System.Drawing.SystemIcons]::Information
try { $p = Join-Path $ScriptDir "icon-192.png"
  if (Test-Path -LiteralPath $p) { $bmp = New-Object System.Drawing.Bitmap($p); $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon()) }
} catch {}

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $icon; $ni.Visible = $true
$ctx = New-Object System.Windows.Forms.ApplicationContext

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add("Открыть приложение"); $open.Add_Click({ Start-Process $AppUrl })
$ref = $menu.Items.Add("Обновить время"); $ref.Add_Click({ $script:timings = Get-Timings })
$exit = $menu.Items.Add("Выход"); $exit.Add_Click({ $ni.Visible = $false; $ctx.ExitThread() })
$ni.ContextMenuStrip = $menu
$ni.Add_DoubleClick({ Start-Process $AppUrl })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({
  $now = Get-Date
  if ((Get-Date).ToString("dd-MM-yyyy") -ne $script:day) { $script:timings = Get-Timings; $script:day = (Get-Date).ToString("dd-MM-yyyy") }
  $next = $null
  foreach ($k in $Order) { $d = To-Date $script:timings.$k; if ($d -gt $now) { $next = @{ key=$k; date=$d }; break } }
  if (-not $next) { $d = (To-Date $script:timings.Fajr).AddDays(1); $next = @{ key="Fajr"; date=$d } }
  $s = [int]($next.date - $now).TotalSeconds
  $cd = "{0:00}:{1:00}:{2:00}" -f ($s/3600), (($s%3600)/60), ($s%60)
  $ni.Text = "{0} {1} -{2}" -f $RU[$next.key], $next.date.ToString("HH:mm"), $cd
  $dk = "{0}_{1}" -f $next.key, (Get-Date).ToString("yyyy-MM-dd")
  if ($s -le 600 -and $s -gt 540 -and $next.key -ne "Sunrise" -and $script:last10 -ne $dk) { $script:last10 = $dk
    $ni.ShowBalloonTip(10000, "Подготовка к молитве", ("{0} через 10 минут ({1}). Соверши вуду." -f $RU[$next.key], $next.date.ToString("HH:mm")), [System.Windows.Forms.ToolTipIcon]::Info) }
  if ($s -le 5 -and $script:last0 -ne $dk) { $script:last0 = $dk
    if ($next.key -eq "Sunrise") { $ni.ShowBalloonTip(10000, "Восход", "Время Фаджра вышло.", [System.Windows.Forms.ToolTipIcon]::Info) }
    else { $ni.ShowBalloonTip(10000, "Время намаза", ("Начался: {0}." -f $RU[$next.key]), [System.Windows.Forms.ToolTipIcon]::Info) } }
})
$script:day = (Get-Date).ToString("dd-MM-yyyy")
$script:last10 = ""; $script:last0 = ""
$timer.Start()
Log "Виджет запущен"
$ni.ShowBalloonTip(5000, "Намаз-виджет", "Виджет запущен. Наведи на значок в трее.", [System.Windows.Forms.ToolTipIcon]::Info)
[System.Windows.Forms.Application]::Run($ctx)
$timer.Stop(); $ni.Dispose()
Log "Виджет остановлен"
