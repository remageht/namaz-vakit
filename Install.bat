@echo off
rem Install Namaz Widget & App
echo Setting up Namaz in Startup and Desktop...

node "%~dp0setup-autostart.js"
echo Install complete. Starting widget...
wscript.exe "%~dp0Start-NamazWidget.vbs"
pause
