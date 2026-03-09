@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0hon_check_translation_update.ps1"
echo.
pause
