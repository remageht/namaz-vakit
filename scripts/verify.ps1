# verify.ps1 — синтаксис PowerShell-виджета + кодировки + JSON проекта
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fail = 0

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'NamazWidget.ps1'), [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count) {
  $fail = 1
  foreach ($e in $errors) { Write-Host ("PS-PARSE-ERR line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
} else { Write-Host 'PS-PARSE-OK NamazWidget.ps1' }

$bytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'NamazWidget.ps1'))
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  Write-Host 'BOM-OK NamazWidget.ps1 (UTF-8 EF BB BF)'
} else { Write-Host 'BOM-MISSING NamazWidget.ps1'; $fail = 1 }

foreach ($j in @('manifest.json', 'config.json', '.well-known\assetlinks.json', 'desktop\package.json', 'android\app\src\main\assets\namaz\manifest.json')) {
  $p = Join-Path $root $j
  if (Test-Path -LiteralPath $p) {
    try { [void](Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json); Write-Host "JSON-OK $j" }
    catch { Write-Host "JSON-ERR $j : $($_.Exception.Message)"; $fail = 1 }
  }
}
exit $fail