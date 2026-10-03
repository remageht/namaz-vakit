@echo off
rem Uninstall Namaz Widget
echo Removing Namaz Widget...

rem Remove Startup shortcut
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Namaz Widget.lnk" (
    del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Namaz Widget.lnk"
    echo Removed Startup shortcut.
)

rem Remove desktop shortcut
if exist "%USERPROFILE%\Desktop\Namaz Vakit.lnk" (
    del "%USERPROFILE%\Desktop\Namaz Vakit.lnk"
    echo Removed Desktop shortcut.
)

rem Kill any running widget processes
taskkill /F /IM powershell.exe 2>nul
taskkill /F /IM wscript.exe 2>nul

echo Uninstall complete.
pause