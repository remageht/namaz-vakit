@echo off
rem Install Namaz Widget
echo Setting up Namaz Widget in Startup and Desktop...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Startup') + '\Namaz Widget.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '"C:\dev\namaz-app\Start-NamazWidget.vbs"'; $sc.WorkingDirectory = 'C:\dev\namaz-app'; $sc.Save()"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Namaz Vakit.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '"C:\dev\namaz-app\Start-NamazWidget.vbs"'; $sc.WorkingDirectory = 'C:\dev\namaz-app'; $sc.Save()"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'NamazWidget' -Value 'wscript.exe "C:\dev\namaz-app\Start-NamazWidget.vbs"' -Force"

echo Install complete. Starting widget...
wscript.exe "C:\dev\namaz-app\Start-NamazWidget.vbs"
pause
