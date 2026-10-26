# ==============================================================================
# Install-IntelArcFix.ps1
# Complete Permanent Fix for Intel Arc B580 / Battlemage & Alchemist Startup
# Freeze, Code 43 (Kernel-PnP Event ID 1011), and Post-Login IGCL/PresentMon Deadlock
# ==============================================================================
$ErrorActionPreference = "Continue"

# Auto-elevate if not running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$GuardDir = "C:\ProgramData\IntelArcGuard"
if (!(Test-Path $GuardDir)) { New-Item -ItemType Directory -Path $GuardDir -Force | Out-Null }
$LogFile = Join-Path $GuardDir "InstallAndShield.log"

function Log-Step([string]$msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] $msg"
    Write-Host $line -ForegroundColor Cyan
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Log-Step "=== STARTING INTEL ARC B580 PERMANENT ANTI-FREEZE INSTALLER ==="

# ------------------------------------------------------------------------------
# STEP 1: Disable Fast Startup (Hiberboot)
# ------------------------------------------------------------------------------
Log-Step "Step 1: Disabling Windows Fast Startup (Hiberboot)..."
powercfg.exe /h off 2>$null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null

# ------------------------------------------------------------------------------
# STEP 2: Completely Disable VBS, Credential Guard (lsaiso.exe) & Hypervisor IOMMU
# (Fixes Stage 1: Kernel-PnP Event ID 1011 / Code 43 during cold boot)
# ------------------------------------------------------------------------------
Log-Step "Step 2: Disabling VBS, Credential Guard (lsaiso.exe), and Hypervisor IOMMU..."
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v RequirePlatformSecurityFeatures /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v HyperVVirtualizationBasedSecurityOptout /t REG_DWORD /d 1 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v Locked /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Locked /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard" /v Locked /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlagsDefault /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v LsaCfgFlags /t REG_DWORD /d 0 /f | Out-Null

bcdedit.exe /set hypervisorlaunchtype off | Out-Null
bcdedit.exe /set vsmlaunchtype Off | Out-Null

# ------------------------------------------------------------------------------
# STEP 3: Disable Kernel DMA Remapping (DmaRemappingCompatible = 0) & PCIe D3Cold
# ------------------------------------------------------------------------------
Log-Step "Step 3: Disabling DmaRemappingCompatible on igfxnd and D3Cold on Intel Arc PCIe tree..."
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters" -Name "DmaRemappingCompatible" -Value 0 -Type DWord -Force
    Log-Step "  -> Set igfxnd DmaRemappingCompatible = 0"
}

reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\PnP\Pci\Parameters" /v DisableD3Cold /t REG_DWORD /d 1 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 10 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /t REG_DWORD /d 10 /f | Out-Null

# ------------------------------------------------------------------------------
# STEP 4: Install & Execute ArcBootGuard (Neutralizes Overlay/PresentMon & Self-Heals PCIe)
# ------------------------------------------------------------------------------
Log-Step "Step 4: Installing ArcBootGuard self-healing watchdog..."
$SourceGuard = Join-Path $PSScriptRoot "ArcBootGuard.ps1"
$DestGuard = Join-Path $GuardDir "ArcBootGuard.ps1"
Copy-Item -Path $SourceGuard -Destination $DestGuard -Force

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DestGuard

$TaskName = "IntelArcBootGuard"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestGuard`""
$TriggerBoot = New-ScheduledTaskTrigger -AtStartup
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($TriggerBoot, $TriggerLogon) -Principal $Principal -Settings $Settings -Description "Prevents Code 43 / Event 1011 and post-login kernel deadlocks on Intel Arc GPUs" -Force | Out-Null
Log-Step "  -> Registered Scheduled Task '$TaskName' as SYSTEM (AtStartup + AtLogOn)."

# ------------------------------------------------------------------------------
# STEP 5: Disable Bloated Intel Event Channels & Clear Corrupt Logs
# ------------------------------------------------------------------------------
Log-Step "Step 5: Disabling Intel-IGS-Logs/Overlay & Telemetry channels..."
wevtutil.exe sl "Intel-IGS-Logs/Overlay" /e:false 2>$null
wevtutil.exe sl "Intel-IGS-Logs/Telemetry" /e:false 2>$null
wevtutil.exe cl "Intel-IGS-Logs/Overlay" 2>$null
wevtutil.exe cl "Intel-IGS-Logs/Telemetry" 2>$null

$finalGpu = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E20B%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_E20%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_56A%'" -ErrorAction SilentlyContinue | Select-Object -First 1
Log-Step "=== INSTALLATION COMPLETE: GPU=$($finalGpu.Name) | Status=$($finalGpu.Status) | ErrorCode=$($finalGpu.ConfigManagerErrorCode) ==="
Write-Host "`nAll fixes applied! Please restart your PC once to complete the VBS/IOMMU unload." -ForegroundColor Green
