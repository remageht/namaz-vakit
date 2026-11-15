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

rem Kill only the widget process by PID (never all PowerShell/wscript sessions)
set "WIDGET_PID="
if exist "%~dp0widget.pid" set /p WIDGET_PID=<"%~dp0widget.pid"
if defined WIDGET_PID (
    tasklist /FI "PID eq %WIDGET_PID%" /FI "IMAGENAME eq powershell.exe" 2>nul | findstr /R "^powershell" >nul && taskkill /F /PID %WIDGET_PID% 2>nul
)
if exist "%~dp0widget.pid" del "%~dp0widget.pid" 2>nul

echo Uninstall complete.
pause