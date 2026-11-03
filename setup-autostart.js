const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const appDir = 'C:\\dev\\namaz-app';
const vbsPath = path.join(appDir, 'Start-NamazWidget.vbs');
const exePath = path.join(appDir, 'desktop', 'dist', 'win-unpacked', 'Namaz.exe');

console.log('1. Configuring Windows Autostart and Shortcuts...');

const appData = process.env.APPDATA || path.join(process.env.USERPROFILE, 'AppData', 'Roaming');
const startupFolder = path.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
const desktopFolder = path.join(process.env.USERPROFILE, 'Desktop');

if (!fs.existsSync(startupFolder)) {
  fs.mkdirSync(startupFolder, { recursive: true });
}

const psScript = `
$ws = New-Object -ComObject WScript.Shell

# 1. Startup shortcut (widget in tray + floating panel)
$startupPath = [Environment]::GetFolderPath('Startup')
$scStartup = $ws.CreateShortcut("$startupPath\\Namaz Widget.lnk")
$scStartup.TargetPath = 'wscript.exe'
$scStartup.Arguments = '"${vbsPath}"'
$scStartup.WorkingDirectory = '${appDir}'
$scStartup.Description = 'Виджет времени намаза в трее Windows'
$scStartup.Save()
Write-Host "Startup shortcut created: $startupPath\\Namaz Widget.lnk"

# 2. Desktop shortcuts
$desktopPath = [Environment]::GetFolderPath('Desktop')

# Widget shortcut
$scWidget = $ws.CreateShortcut("$desktopPath\\Namaz Widget.lnk")
$scWidget.TargetPath = 'wscript.exe'
$scWidget.Arguments = '"${vbsPath}"'
$scWidget.WorkingDirectory = '${appDir}'
$scWidget.Description = 'Виджет времени намаза (плашка и трей)'
$scWidget.Save()
Write-Host "Desktop shortcut created: $desktopPath\\Namaz Widget.lnk"

# Namaz Vakit shortcut (compatibility)
$scOld = $ws.CreateShortcut("$desktopPath\\Namaz Vakit.lnk")
$scOld.TargetPath = 'wscript.exe'
$scOld.Arguments = '"${vbsPath}"'
$scOld.WorkingDirectory = '${appDir}'
$scOld.Description = 'Виджет времени намаза (плашка и трей)'
$scOld.Save()

# Full App shortcut (if Namaz.exe exists)
if (Test-Path -LiteralPath '${exePath}') {
  $scApp = $ws.CreateShortcut("$desktopPath\\Намаз (Приложение).lnk")
  $scApp.TargetPath = '${exePath}'
  $scApp.WorkingDirectory = [System.IO.Path]::GetDirectoryName('${exePath}')
  $scApp.Description = 'Намаз — Полное Windows приложение'
  $scApp.Save()
  Write-Host "Desktop app shortcut created: $desktopPath\\Намаз (Приложение).lnk"
}

# 3. Registry Run key
$regPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
Set-ItemProperty -Path $regPath -Name 'NamazWidget' -Value 'wscript.exe "${vbsPath}"' -Force
Write-Host "Registry autostart key set."
`;

const psFile = path.join(appDir, '_create_shortcuts.ps1');
fs.writeFileSync(psFile, '\uFEFF' + psScript, 'utf8');

try {
  const out = execSync(`powershell -ExecutionPolicy Bypass -File "${psFile}"`, { encoding: 'utf8' });
  console.log(out);
} catch (e) {
  console.error('Error creating shortcuts:', e.message);
} finally {
  if (fs.existsSync(psFile)) fs.unlinkSync(psFile);
}

// 4. Update Install.bat
const installBatContent = `@echo off
rem Install Namaz Widget & App
echo Setting up Namaz in Startup and Desktop...

node "%~dp0setup-autostart.js"
echo Install complete. Starting widget...
wscript.exe "%~dp0Start-NamazWidget.vbs"
pause
`;
fs.writeFileSync(path.join(appDir, 'Install.bat'), installBatContent, 'utf8');
console.log('2. Updated Install.bat.');

// 5. Terminate old instances & launch widget cleanly
console.log('3. Launching widget...');
try {
  execSync(`wscript.exe "${vbsPath}"`);
  console.log('Widget launched successfully via wscript.exe!');
} catch (e) {
  console.error('Launch error:', e.message);
}
