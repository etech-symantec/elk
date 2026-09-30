@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "RC=0"
set "HELPER=%~dp0_internal\tools\run-remote-deploy.ps1"
if not exist "%HELPER%" goto :nohelper
if /i "%~1"=="--status" goto :status

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action deploy -ScriptPath "%~1"
set "RC=%ERRORLEVEL%"
goto :finish

:status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action status -ScriptPath "%~2"
set "RC=%ERRORLEVEL%"
goto :finish

:nohelper
echo [ERROR] Internal deploy helper not found:
echo         %HELPER%
echo         Please extract the entire ZIP before running this file.
set "RC=2"
goto :finish

:finish
echo.
if "%RC%"=="0" goto :done
powershell.exe -NoProfile -Command "Write-Host '[FAILED] run-remote-deploy stopped with an error (exit code %RC%). Check the messages above.' -ForegroundColor Yellow"
goto :end

:done
powershell.exe -NoProfile -Command "Write-Host '[DONE] run-remote-deploy finished (exit code 0). Check the messages above for details.' -ForegroundColor Yellow"

:end
rem Keep the window open. Set ELK_NO_PAUSE=1 to skip (for automation).
if not defined ELK_NO_PAUSE pause
exit /b %RC%
