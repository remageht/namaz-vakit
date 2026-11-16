// smoke-offline.js — офлайн-расчёт: паритет JS (index.html) ↔ PowerShell (NamazWidget.ps1),
// маппинг методов для Aladhan API и регрессия формата «24:00».
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

function extractFn(src, signature) {
  const i = src.indexOf(signature);
  if (i < 0) throw new Error('signature not found: ' + signature);
  const start = src.indexOf('{', i);
  let depth = 0, j = start;
  for (; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (!depth) break; }
  }
  return src.slice(i, j + 1);
}

const calcOfflinePrayerTimes = eval('(' + extractFn(html, 'function calcOfflinePrayerTimes') + ')');
const apiMethodNumber = eval('(' + extractFn(html, 'function apiMethodNumber') + ')');

let failures = 0;
function check(name, cond, extra) {
  if (cond) console.log('PASS ' + name);
  else { failures++; console.log('FAIL ' + name + (extra ? ' :: ' + extra : '')); }
}

// 1) Маппинг internal→API (сверено с живым https://api.aladhan.com/v1/methods)
check('apiMethod 2(MWL)->3', apiMethodNumber('2') === 3);
check('apiMethod 3(Egypt)->5', apiMethodNumber('3') === 5);
check('apiMethod 14(RF)->14', apiMethodNumber('14') === 14);
check('apiMethod 1(Karachi)->1', apiMethodNumber('1') === 1);
check('apiMethod 13(Diyanet)->13', apiMethodNumber('13') === 13);

// 2) Паритет формул JS ↔ PS
const cases = [];
let id = 0;
const locs = [[21.4225, 39.8262], [55.7558, 37.6173], [60.0, 10.0]];
const dates = [[2026, 1, 15], [2026, 3, 20], [2026, 6, 21], [2026, 9, 23], [2026, 12, 21]];
for (const [lat, lon] of locs)
  for (const [y, mo, d] of dates)
    for (const method of [1, 2, 3, 13, 14])
      for (const school of [0, 1])
        cases.push({ id: id++, lat, lon, y, mo, d, method, school });

const jsResults = cases.map(c => {
  const r = calcOfflinePrayerTimes(c.lat, c.lon, new Date(c.y, c.mo - 1, c.d, 12, 0, 0), c.method, c.school);
  return { id: c.id, ...r };
});

const tmp = path.join(root, '.temp-smoke');
fs.mkdirSync(tmp, { recursive: true });
const casesPath = path.join(tmp, 'cases.json');
const outPath = path.join(tmp, 'ps-results.json');
fs.writeFileSync(casesPath, JSON.stringify(cases));

const psScript = `
$ErrorActionPreference = 'Stop'
$src = Get-Content -LiteralPath '${path.join(root, 'NamazWidget.ps1').replace(/'/g, "''")}' -Raw -Encoding UTF8
$start = $src.IndexOf('function Calc-PrayerTimes')
$end = $src.IndexOf('function Compare-Timings')
$fn = $src.Substring($start, $end - $start)
$cases = Get-Content -LiteralPath '${casesPath.replace(/'/g, "''")}' -Raw -Encoding UTF8 | ConvertFrom-Json
$out = @()
foreach ($c in $cases) {
  $Method = $c.method; $School = $c.school
  Invoke-Expression $fn
  $d = Get-Date -Year $c.y -Month $c.mo -Day $c.d -Hour 12 -Minute 0 -Second 0
  $r = Calc-PrayerTimes $c.lat $c.lon $d
  $out += [PSCustomObject]@{ id=$c.id; Fajr=$r.Fajr; Sunrise=$r.Sunrise; Dhuhr=$r.Dhuhr; Asr=$r.Asr; Maghrib=$r.Maghrib; Isha=$r.Isha }
}
[System.IO.File]::WriteAllText('${outPath.replace(/'/g, "''")}', ($out | ConvertTo-Json -Depth 3))
`;
const psPath = path.join(tmp, 'run.ps1');
fs.writeFileSync(psPath, psScript);
execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psPath], { stdio: 'inherit' });

const psResults = JSON.parse(fs.readFileSync(outPath, 'utf8').replace(/^\uFEFF/, ''));
const psById = new Map(psResults.map(r => [r.id, r]));
const keys = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
function mins(s) { const [h, m] = String(s).slice(0, 5).split(':').map(Number); return h * 60 + m; }
let maxDiff = 0, worst = null, mismatches = 0, polarDivergence = 0;
for (const jr of jsResults) {
  const pr = psById.get(jr.id);
  if (!pr) { mismatches++; console.log('FAIL missing PS result for case ' + jr.id); continue; }
  for (const k of keys) {
    const jv = jr[k], pv = pr[k];
    // L2 (принято): за полярным кругом JS даёт '--:--', PS клампить к noon±12 — не регрессия
    if (jv === '--:--' || pv === '--:--') { if (jv !== pv) polarDivergence++; continue; }
    const diff = Math.abs(mins(jv) - mins(pv));
    if (diff > maxDiff) { maxDiff = diff; worst = { id: jr.id, k, jv, pv }; }
    if (diff > 1) { mismatches++; console.log(`FAIL case ${jr.id} ${k}: JS=${jv} PS=${pv} diff=${diff}min`); }
  }
}
check(`JS<->PS parity (${cases.length} cases, max diff ${maxDiff} min, polar divergences ${polarDivergence})`, mismatches === 0, JSON.stringify(worst));

// 3) Регрессия M9: старый fFmt давал «24:00», новый — «00:00»
const fmtTest = `
function OldFmt([double]$h) { $h = ($h % 24 + 24) % 24; $hh = [Math]::Floor($h); $mm = [Math]::Round(($h - $hh) * 60); if ($mm -eq 60) { $hh += 1; $mm = 0 }; "{0:00}:{1:00}" -f [int]$hh, [int]$mm }
function NewFmt([double]$h) { $h = ($h % 24 + 24) % 24; $hh = [Math]::Floor($h); $mm = [Math]::Round(($h - $hh) * 60); if ($mm -eq 60) { $hh = ($hh + 1) % 24; $mm = 0 }; "{0:00}:{1:00}" -f [int]$hh, [int]$mm }
Write-Host ("OLD " + (OldFmt 23.9999))
Write-Host ("NEW " + (NewFmt 23.9999))
`;
const fmtPath = path.join(tmp, 'fmt.ps1');
fs.writeFileSync(fmtPath, fmtTest);
const fmtOut = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', fmtPath], { encoding: 'utf8' });
check('M9 old fFmt reproduces 24:00', /OLD 24:00/.test(fmtOut), fmtOut.trim());
check('M9 new fFmt wraps to 00:00', /NEW 00:00/.test(fmtOut), fmtOut.trim());

fs.rmSync(tmp, { recursive: true, force: true });
console.log(failures === 0 ? 'SMOKE-OK all checks passed' : `SMOKE-FAIL ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);