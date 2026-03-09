@echo off
setlocal

if "%~1"=="" (
  set "SRC=%~dp0bundle"
) else (
  set "SRC=%~1"
)

set "PACKROOT=%~dp0"
if "%PACKROOT:~-1%"=="\" set "PACKROOT=%PACKROOT:~0,-1%"

powershell -ExecutionPolicy Bypass -File "%~dp0set_login_banner.ps1" -PackageRoot "%PACKROOT%"
if errorlevel 1 (
  echo.
  echo Failed to update login banner text. Continuing deploy...
)

powershell -ExecutionPolicy Bypass -File "%~dp0hon_deploy_full_stringtables.ps1" -SourceDir "%SRC%"
echo.
pause
