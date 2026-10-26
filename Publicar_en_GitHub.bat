@echo off
title Publicar Repositorio en GitHub (intel-arc-b580-freeze-fix)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Publish-To-GitHub.ps1"
pause
