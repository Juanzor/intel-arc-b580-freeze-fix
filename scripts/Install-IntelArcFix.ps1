# ==============================================================================
# Install-IntelArcFix.ps1 (v2.0)
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

Log-Step "=== STARTING INTEL ARC B580 PERMANENT ANTI-FREEZE INSTALLER v2.0 ==="

# ------------------------------------------------------------------------------
# STEP 1: Disable Fast Startup (Hiberboot) & PCIe ASPM in Power Plan
# ------------------------------------------------------------------------------
Log-Step "Step 1: Disabling Windows Fast Startup (Hiberboot) and PCIe ASPM..."
powercfg.exe /h off 2>$null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride /t REG_DWORD /d 0 /f | Out-Null
powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null
powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null
powercfg.exe /setactive SCHEME_CURRENT 2>$null

# ------------------------------------------------------------------------------
# STEP 2: Completely Disable VBS, Credential Guard (lsaiso.exe) & Hypervisor IOMMU
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
# STEP 3: Enforce 30s DirectX Watchdog (TDR) Tolerance & Disable DmaRemapping
# ------------------------------------------------------------------------------
Log-Step "Step 3: Enforcing 30s TDR Timeout Tolerance & Disabling DmaRemappingCompatible..."
foreach ($dmaSvc in @("igfxnd", "HDAudBus", "GSCx64", "PmtChildDriver")) {
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$dmaSvc") {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$dmaSvc\Parameters" /v DmaRemappingCompatible /t REG_DWORD /d 0 /f | Out-Null
    }
}

reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\PnP\Pci\Parameters" /v DisableD3Cold /t REG_DWORD /d 1 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrLevel /t REG_DWORD /d 3 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 30 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /t REG_DWORD /d 30 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrLimitTime /t REG_DWORD /d 60 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrLimitCount /t REG_DWORD /d 10 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v DisableBadDriverCheck /t REG_DWORD /d 1 /f | Out-Null

# ------------------------------------------------------------------------------
# STEP 4: Install & Execute ArcBootGuard v2.0 as NT AUTHORITY\SYSTEM
#         (Required to write HKLM\SYSTEM\CurrentControlSet\Enum\PCI\** keys:
#          e5b3b5ac-9725-4f78-963f-03dfb1d828c7 & DMA Management)
# ------------------------------------------------------------------------------
Log-Step "Step 4: Installing ArcBootGuard v2.0 and executing as NT AUTHORITY\SYSTEM..."
$SourceGuard = Join-Path $PSScriptRoot "ArcBootGuard.ps1"
$DestGuard = Join-Path $GuardDir "ArcBootGuard.ps1"
Copy-Item -Path $SourceGuard -Destination $DestGuard -Force

$TaskName = "IntelArcBootGuard"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestGuard`""
$TriggerBoot = New-ScheduledTaskTrigger -AtStartup
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($TriggerBoot, $TriggerLogon) -Principal $Principal -Settings $Settings -Description "Prevents Code 43 / Event 1011 and post-login kernel deadlocks on Intel Arc GPUs (v2.0)" -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 5
Log-Step "  -> Registered and executed Scheduled Task '$TaskName' as SYSTEM."

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
Write-Host "`nAll v2.0 fixes applied!" -ForegroundColor Green
