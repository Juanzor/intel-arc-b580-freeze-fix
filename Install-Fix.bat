@echo off
title Intel Arc B580 Anti-Freeze Permanent Installer
echo ============================================================================
echo   Intel Arc B580 / Battlemage Startup Freeze ^& Code 43 Permanent Fix
echo ============================================================================
echo Requesting Administrator privileges...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0scripts\Install-IntelArcFix.ps1\"' -Verb RunAs -Wait"
echo.
echo Done! You may close this window.
pause
