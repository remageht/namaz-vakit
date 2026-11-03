const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const appDir = 'C:\\dev\\namaz-app';
const vbsPath = path.join(appDir, 'Start-NamazWidget.vbs');

console.log('1. Configuring Windows Autostart...');

// Get paths from environment
const appData = process.env.APPDATA || path.join(process.env.USERPROFILE, 'AppData', 'Roaming');
const startupFolder = path.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
const desktopFolder = path.join(process.env.USERPROFILE, 'Desktop');

if (!fs.existsSync(startupFolder)) {
  fs.mkdirSync(startupFolder, { recursive: true });
}

// PowerShell script to create proper COM WScript.Shell .lnk shortcuts
const psScript = `
$ws = New-Object -ComObject WScript.Shell

# 1. Startup shortcut
$startupPath = [Environment]::GetFolderPath('Startup')
$scStartup = $ws.CreateShortcut("$startupPath\\Namaz Widget.lnk")
$scStartup.TargetPath = 'wscript.exe'
$scStartup.Arguments = '"${vbsPath}"'
$scStartup.WorkingDirectory = '${appDir}'
$scStartup.Description = 'Namaz Widget - Prayer times in Windows Tray'
$scStartup.Save()
Write-Host "Startup shortcut created at: $startupPath\\Namaz Widget.lnk"

# 2. Desktop shortcut
$desktopPath = [Environment]::GetFolderPath('Desktop')
$scDesktop = $ws.CreateShortcut("$desktopPath\\Namaz Vakit.lnk")
$scDesktop.TargetPath = 'wscript.exe'
$scDesktop.Arguments = '"${vbsPath}"'
$scDesktop.WorkingDirectory = '${appDir}'
$scDesktop.Description = 'Namaz Widget - Prayer times in Windows Tray'
$scDesktop.Save()
Write-Host "Desktop shortcut created at: $desktopPath\\Namaz Vakit.lnk"

# 3. Registry Run key
$regPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
Set-ItemProperty -Path $regPath -Name 'NamazWidget' -Value 'wscript.exe "${vbsPath}"' -Force
Write-Host "Registry autostart key set at HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run -> NamazWidget"
`;

const psFile = path.join(appDir, '_create_shortcuts.ps1');
fs.writeFileSync(psFile, psScript, 'utf8');

try {
  const out = execSync(`powershell -ExecutionPolicy Bypass -File "${psFile}"`, { encoding: 'utf8' });
  console.log(out);
} catch (e) {
  console.error('Error creating shortcuts:', e.message);
} finally {
  if (fs.existsSync(psFile)) fs.unlinkSync(psFile);
}

// Fix Install.bat so that running it manually also uses the correct COM shortcut creation
const installBatContent = `@echo off
rem Install Namaz Widget
echo Setting up Namaz Widget in Startup and Desktop...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Startup') + '\\Namaz Widget.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"C:\\dev\\namaz-app\\Start-NamazWidget.vbs\"'; $sc.WorkingDirectory = 'C:\\dev\\namaz-app'; $sc.Save()"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\\Namaz Vakit.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"C:\\dev\\namaz-app\\Start-NamazWidget.vbs\"'; $sc.WorkingDirectory = 'C:\\dev\\namaz-app'; $sc.Save()"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'NamazWidget' -Value 'wscript.exe \"C:\\dev\\namaz-app\\Start-NamazWidget.vbs\"' -Force"

echo Install complete. Starting widget...
wscript.exe "C:\\dev\\namaz-app\\Start-NamazWidget.vbs"
pause
`;
fs.writeFileSync(path.join(appDir, 'Install.bat'), installBatContent, 'utf8');
console.log('2. Updated Install.bat with robust autostart setup.');

// 3. Launch Namaz Widget right now
console.log('3. Launching Namaz Widget on the computer...');
try {
  // Check if already running and restart cleanly
  execSync('powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like \'*NamazWidget.ps1*\' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"', { stdio: 'ignore' });
} catch (e) {}

// Launch hidden via wscript
execSync(`wscript.exe "${vbsPath}"`);
console.log('Widget launched via wscript.exe!');
