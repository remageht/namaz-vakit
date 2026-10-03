@echo off
rem Install Namaz Widget
echo Setting up Namaz Widget...

rem Create shortcut in Startup
mkdir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
copy "C:\dev\namaz-app\Start-NamazWidget.vbs" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Namaz Widget.lnk" /y

rem Create desktop shortcut
mkdir "%USERPROFILE%\Desktop"
powershell -Command "" &
pushd "C:\dev\namaz-app"
powershell -Command "
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut('%USERPROFILE%\Desktop\Namaz Vakit.lnk')
$sc.TargetPath = 'wscript.exe'
$sc.Arguments = '"C:\dev\namaz-app\Start-NamazWidget.vbs"'
$sc.WorkingDirectory = 'C:\dev\namaz-app'
$sc.Description = 'Namaz Widget - время намаза в трее Windows'
$sc.Save()
"
popd

rem Create taskbar shortcut (pin to taskbar)
echo Install complete. You can find the widget on your desktop and in the startup folder.
pause