@echo off
title Intel Arc B580 Startup Freeze Diagnostic
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Diagnose-IntelArc.ps1"
echo.
pause
