@echo off
REM eurozone Windows launcher — ASCII only, works on cmd.exe
setlocal
set "SCRIPT=%~dp0eurozone.ps1"
if not exist "%SCRIPT%" (
  echo error: eurozone.ps1 missing next to eurozone.cmd
  exit /b 1
)
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
