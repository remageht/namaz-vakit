$sr = 22050
$notes = @(523.25, 392.00, 440.00, 349.23)
$lenSec = 0.62
$tail = 0.4
$total = $notes.Count * $lenSec + $tail
$samples = [int]($total * $sr)
$bytes = New-Object byte[] ($samples * 2)

for ($i = 0; $i -lt $samples; $i++) {
    $t = $i / $sr
    $noteIdx = [math]::Floor($t / $lenSec)
    $within = $t - ($noteIdx * $lenSec)
    $f = $notes[[math]::Min($noteIdx, $notes.Count - 1)]
    $amp = 0.0
    if ($noteIdx -lt $notes.Count) {
        if ($within -lt 0.03) { $amp = $within / 0.03 }
        elseif ($within -gt ($lenSec - 0.25)) { $amp = [math]::Max(0, ($lenSec - $within) / 0.25) }
        else { $amp = 1.0 }
        $amp = $amp * 0.42
    } else {
        $amp = [math]::Max(0, 1 - ($t - $notes.Count * $lenSec) / $tail) * 0.15
    }
    $v = [math]::Sin(2 * [math]::PI * $f * $t) + 0.35 * [math]::Sin(4 * [math]::PI * $f * $t)
    $sample = [int16]([math]::Max(-32767, [math]::Min(32767, $v * $amp * 32767)))
    $b = [BitConverter]::GetBytes($sample)
    $bytes[$i * 2] = $b[0]
    $bytes[$i * 2 + 1] = $b[1]
}

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([char[]]"RIFF"); $bw.Write([int](36 + $bytes.Length)); $bw.Write([char[]]"WAVE")
$bw.Write([char[]]"fmt "); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
$bw.Write([int]$sr); $bw.Write([int]($sr * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
$bw.Write([char[]]"data"); $bw.Write([int]$bytes.Length); $bw.Write($bytes)
$bw.Flush()
$dir = "C:\dev\namaz-app\android\app\src\main\res\raw"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[System.IO.File]::WriteAllBytes("$dir\adhan.wav", $ms.ToArray())
Write-Output ("wav " + (Get-Item "$dir\adhan.wav").Length + " bytes")
