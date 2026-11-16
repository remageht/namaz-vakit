param([string]$Out)
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WEnum {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static List<RECT> FindByPids(HashSet<uint> pids) {
    var list = new List<RECT>();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      uint p; GetWindowThreadProcessId(h, out p);
      if (!pids.Contains(p)) return true;
      RECT r; GetWindowRect(h, out r);
      int w = r.Right - r.Left, ht = r.Bottom - r.Top;
      if (w > 200 && ht > 200 && w < 2000 && ht < 2000) list.Add(r);
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@
# Only the MAIN electron process (no --type= child) that runs our app owns the app windows.
$main = Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*namaz-app*desktop*' -and $_.CommandLine -notlike '*--type=*' }
$ids = New-Object 'System.Collections.Generic.HashSet[uint32]'
foreach ($p in $main) { [void]$ids.Add([uint32]$p.ProcessId) }
if ($ids.Count -eq 0) { Write-Host 'no-main-pid'; exit 2 }
$rects = [WEnum]::FindByPids($ids)
if (-not $rects -or $rects.Count -eq 0) { Write-Host 'no-window'; exit 2 }
$best = $rects[0]; $area = 0
foreach ($r in $rects) { $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top); if ($a -gt $area) { $area = $a; $best = $r } }
$w = $best.Right - $best.Left; $ht = $best.Bottom - $best.Top
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($best.Left, $best.Top, 0, 0, (New-Object System.Drawing.Size $w, $ht))
$bmp.Save($Out)
$g.Dispose(); $bmp.Dispose()
Write-Host ("captured " + $w + "x" + $ht + " -> " + $Out)