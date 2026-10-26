# ==============================================================================
# Uninstall-IntelArcFix.ps1
# Restores default Windows / Intel settings and removes the IntelArcBootGuard task.
# ==============================================================================
$ErrorActionPreference = "Continue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Removing Scheduled Task 'IntelArcBootGuard'..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "IntelArcBootGuard" -Confirm:$false -ErrorAction SilentlyContinue

$igsDir = "C:\Program Files\Intel\Intel Graphics Software"
if (Test-Path $igsDir) {
    foreach ($exe in @("IntelGraphicsSoftware.Overlay.exe", "PresentMonService.exe")) {
        $disPath = Join-Path $igsDir "$exe.disabled"
        if (Test-Path $disPath) {
            Rename-Item -Path $disPath -NewName $exe -Force -ErrorAction SilentlyContinue
        }
    }
}

$pmSharedDir = "C:\Program Files\Intel\PresentMonSharedService"
if (Test-Path $pmSharedDir) {
    $disPm = Join-Path $pmSharedDir "PresentMonService.exe.disabled"
    if (Test-Path $disPm) {
        Rename-Item -Path $disPm -NewName "PresentMonService.exe" -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Uninstallation completed." -ForegroundColor Green
