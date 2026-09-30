@echo off
if exist "%~dp0config-wizard.html" (
  start "" "%~dp0config-wizard.html"
) else (
  start "" "%~dp0..\..\config-wizard.html"
)
