@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "HELPER=%~dp0_internal\tools\run-remote-deploy.ps1"
if not exist "%HELPER%" (
  echo [ERROR] Internal deploy helper not found:
  echo         %HELPER%
  echo         Please extract the entire ZIP before running this file.
  exit /b 2
)

if /i "%~1"=="--status" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action status -ScriptPath "%~2"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action deploy -ScriptPath "%~1"
)
exit /b %ERRORLEVEL%
