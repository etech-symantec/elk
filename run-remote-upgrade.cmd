@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1
title ELK Stack Remote Auto Upgrade
set "HELPER=%~dp0_internal\tools\run-remote-upgrade.ps1"
set "ACTION=upgrade"
set "VERSION=latest"
set "RC=0"
if not exist "%HELPER%" (
  echo [ERROR] Missing _internal\tools\run-remote-upgrade.ps1
  set "RC=2"
  goto :finish
)
if /i "%~1"=="--check" (
  set "ACTION=check"
  goto :run
)
if /i "%~1"=="--status" (
  set "ACTION=status"
  goto :run
)
if /i "%~1"=="--plan" (
  set "ACTION=plan"
  if not "%~2"=="" set "VERSION=%~2"
  goto :run
)
if /i "%~1"=="--upgrade" (
  if not "%~2"=="" set "VERSION=%~2"
  goto :run
)
if /i "%~1"=="--help" goto :help
if not "%~1"=="" set "VERSION=%~1"
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action "%ACTION%" -Version "%VERSION%"
set "RC=%ERRORLEVEL%"
goto :finish
:help
echo [ELK Stack remote auto upgrade]
echo Double-click / no argument: upgrade to the latest version within the installed major.
echo --check            Check current and APT candidate versions
 echo --plan 9.5.5       Dry run a specific version
 echo --plan             Dry run latest
 echo --upgrade 9.5.5    Automatically upgrade to a specific version
 echo --status           Reconnect to current/previous upgrade status
set "RC=0"
:finish
echo.
if "%RC%"=="0" (
  powershell.exe -NoProfile -Command "Write-Host '[DONE] ELK upgrade command finished successfully.' -ForegroundColor Green"
) else (
  powershell.exe -NoProfile -Command "Write-Host '[FAILED] ELK upgrade command failed. Review the output above.' -ForegroundColor Yellow"
)
if not defined ELK_NO_PAUSE pause
exit /b %RC%
