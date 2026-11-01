# ==============================================================================
# Intel Arc B580 / Battlemage & Alchemist Boot Shield v2.0 (ArcBootGuard.ps1)
# Runs as NT AUTHORITY\SYSTEM at Windows Startup and Logon via Scheduled Task.
#
# Forensic v2.0 Fixes (2026-11-01):
# 1. Disables Windows 11 24H2 (wNext) per-device IOMMU DMA Remapping ([DMAr_AddReg1]:
#    Device Parameters\DMA Management\RemappingSupported = 0 & RemappingFlags = 0)
#    in addition to Services\igfxnd\Parameters\DmaRemappingCompatible = 0.
# 2. Enforces pci.sys hardware GUID subkey (e5b3b5ac-9725-4f78-963f-03dfb1d828c7):
#    D3ColdSupported = 0, ASPMOptOut = 1, SettleTimeRequired = 1, IgnoreErrorsDuringPLDR = 1
#    on all Intel Arc PCIe Switch/GPU/Audio nodes (E2FF, E2F0, E2F1, E20B, E2F7) and
#    parent AMD PCIe Root Port (VEN_1022&DEV_14DB), overriding pci.inf & memcntrl.inf.
# 3. Overrides HdBusExt.inf ("Intel(R) HD Graphics D3COLD") EnableD3Cold = 0 and WDF
#    IdleInWorkingState = 0 / WdfDirectedPowerTransitionEnable = 0 on DEV_E2F7.
# 4. Enforces TdrDelay = 30 / TdrDdiDelay = 30 so USB Audio (MOTUCoreUAC) 5s PnP device
#    start stalls at boot never cause dxgkrnl.sys STATUS_TIMEOUT (Event ID 1011).
# 5. Disables IntelGFXFWupdateTool (DisableGfxFWUpdate = 1), intelgraphicssoftwareservice,
#    PresentMonSharedService, and PresentMonAPI2.dll to prevent IGCL ctlInit() deadlocks.
# 6. NEVER calls pnputil /restart-device or /disable-device on a Code 43 GPU (which
#    deadlocks dxgkrnl.sys in System PID 4).
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"
$LogDir = "C:\ProgramData\IntelArcGuard"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "ArcBootGuard.log"

function Write-GuardLog([string]$msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    "$ts - $msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-GuardLog "=== ArcBootGuard v2.0 triggered (Context: $env:USERNAME) ==="

# ------------------------------------------------------------------------------
# 1. Neutralize IGCL / PresentMon / Firmware Update services & startup processes
#    (Prevents Stage 2 kernel freeze if GPU ever enters fallback state)
# ------------------------------------------------------------------------------
$runPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($rp in $runPaths) {
    if (Test-Path $rp) {
        if ($null -ne (Get-ItemProperty -Path $rp -Name "IntelGraphicsSoftware" -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -Path $rp -Name "IntelGraphicsSoftware" -ErrorAction SilentlyContinue
            Write-GuardLog "Removed IntelGraphicsSoftware auto-start from $rp"
        }
    }
}

$toxicServices = @(
    "intelgraphicssoftwareservice",
    "PresentMonSharedService",
    "PresentMonService",
    "IGSDSserviceDiscrete",
    "IntelGFXFWupdateTool",
    "OneApp.IGCC.WinService",
    "PRI-Driver",
    "ESRV_SVC_QUEENCREEK",
    "USER_ESRV_SVC_QUEENCREEK",
    "SystemUsageReportSvc_QUEENCREEK",
    "Intel(R) SUR QC SAM",
    "IntelCollectorService",
    "IntelTelemetryAgent"
)
foreach ($svc in $toxicServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$svc" /v Start /t REG_DWORD /d 4 /f | Out-Null
    }
}

# Disable boot-time GSC/OPROM firmware update probe in IntelGFXFWupdateTool
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\IntelGFXFWupdateTool") {
    $fwParamKey = "HKLM:\SYSTEM\CurrentControlSet\Services\IntelGFXFWupdateTool\Parameters"
    if (!(Test-Path $fwParamKey)) { New-Item -Path $fwParamKey -Force | Out-Null }
    Set-ItemProperty -Path $fwParamKey -Name "DisableGfxFWUpdate" -Value 1 -Type DWord -Force
}

# Stop any running background processes that invoke ctlInit() / PresentMonAPI2.dll
Get-Process -Name "IntelGraphicsSoftware*", "PresentMon*", "igfxShaderDistributionService", "IntelGFXFWupdateTool", "esrv_svc", "SurSvc", "collector_service", "telemetry_agent" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Neutralize PresentMon & IGS background binaries if installed
$igsDir = "C:\Program Files\Intel\Intel Graphics Software"
if (Test-Path $igsDir) {
    foreach ($bin in @("IntelGraphicsSoftware.Service.exe", "IntelGraphicsSoftware.Overlay.exe", "PresentMonService.exe", "PresentMon_x64.exe", "PresentMonAPI2.dll", "ControlLib.dll")) {
        $fullPath = Join-Path $igsDir $bin
        if (Test-Path $fullPath) {
            Rename-Item -Path $fullPath -NewName "$bin.disabled" -Force -ErrorAction SilentlyContinue
            Write-GuardLog "Neutralized IGS binary: $fullPath"
        }
    }
}

$pmSharedDir = "C:\Program Files\Intel\PresentMonSharedService"
if (Test-Path $pmSharedDir) {
    Get-ChildItem -Path $pmSharedDir -Filter "*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        Rename-Item -Path $_.FullName -NewName "$($_.Name).disabled" -Force -ErrorAction SilentlyContinue
        Write-GuardLog "Neutralized PresentMonSharedService binary: $($_.FullName)"
    }
}

# ------------------------------------------------------------------------------
# 2. Enforce DirectX Kernel Watchdog (dxgkrnl.sys TDR) 30s Timeout Tolerance
#    (Prevents 5-second USB Audio / MOTUCoreUAC PnP device start stalls from
#     causing STATUS_TIMEOUT / Event ID 1011 during boot)
# ------------------------------------------------------------------------------
$gfxDriversKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-ItemProperty -Path $gfxDriversKey -Name "TdrLevel" -Value 3 -Type DWord -Force
Set-ItemProperty -Path $gfxDriversKey -Name "TdrDelay" -Value 30 -Type DWord -Force
Set-ItemProperty -Path $gfxDriversKey -Name "TdrDdiDelay" -Value 30 -Type DWord -Force
Set-ItemProperty -Path $gfxDriversKey -Name "TdrLimitTime" -Value 60 -Type DWord -Force
Set-ItemProperty -Path $gfxDriversKey -Name "TdrLimitCount" -Value 10 -Type DWord -Force
Set-ItemProperty -Path $gfxDriversKey -Name "DisableBadDriverCheck" -Value 1 -Type DWord -Force

# ------------------------------------------------------------------------------
# 3. Enforce IOMMU DMA Remapping Disable (Service + Windows 11 24H2 Per-Device)
# ------------------------------------------------------------------------------
foreach ($dmaSvc in @("igfxnd", "HDAudBus", "GSCx64", "PmtChildDriver")) {
    $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$dmaSvc"
    if (Test-Path $svcPath) {
        $paramPath = Join-Path $svcPath "Parameters"
        if (!(Test-Path $paramPath)) { New-Item -Path $paramPath -Force | Out-Null }
        Set-ItemProperty -Path $paramPath -Name "DmaRemappingCompatible" -Value 0 -Type DWord -Force
    }
}

# ------------------------------------------------------------------------------
# 4. Enforce pci.sys GUID Subkey (e5b3b5ac-9725-4f78-963f-03dfb1d828c7),
#    Per-Device DMA Management, and WDF Power Settings on all Intel Arc PCIe
#    nodes (E2*, 56*, 4F*) and parent AMD PCIe Root Port (VEN_1022&DEV_14DB)
# ------------------------------------------------------------------------------
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\PnP\Pci\Parameters" /v DisableD3Cold /t REG_DWORD /d 1 /f | Out-Null
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride /t REG_DWORD /d 0 /f | Out-Null

$pciGuid = "e5b3b5ac-9725-4f78-963f-03dfb1d828c7"
$pciTargets = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI" -ErrorAction SilentlyContinue | Where-Object {
    $_.PSChildName -match "VEN_8086&DEV_(E2|56|4F)" -or $_.PSChildName -match "VEN_1022&DEV_14DB"
}

$patchedNodes = 0
foreach ($devKey in $pciTargets) {
    $isIntel = $devKey.PSChildName -match "VEN_8086"
    Get-ChildItem $devKey.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
        $instPath = $_.PSPath
        $devParams = Join-Path $instPath "Device Parameters"
        if (Test-Path $devParams) {
            # Direct Device Parameters D3ColdSupported
            Set-ItemProperty -Path $devParams -Name "D3ColdSupported" -Value 0 -Type DWord -Force

            # pci.sys Hardware GUID Subkey (overrides pci.inf & memcntrl.inf PciD3ColdSupported.Hw)
            $guidKey = Join-Path $devParams $pciGuid
            if (!(Test-Path $guidKey)) { New-Item -Path $guidKey -Force | Out-Null }
            Set-ItemProperty -Path $guidKey -Name "D3ColdSupported" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $guidKey -Name "ASPMOptOut" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $guidKey -Name "SettleTimeRequired" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $guidKey -Name "IgnoreErrorsDuringPLDR" -Value 1 -Type DWord -Force

            if ($isIntel) {
                # Windows 11 24H2 (wNext) Per-Device IOMMU DMA Remapping (overrides [DMAr_AddReg1])
                $dmaKey = Join-Path $devParams "DMA Management"
                if (!(Test-Path $dmaKey)) { New-Item -Path $dmaKey -Force | Out-Null }
                Set-ItemProperty -Path $dmaKey -Name "RemappingSupported" -Value 0 -Type DWord -Force
                Set-ItemProperty -Path $dmaKey -Name "RemappingFlags" -Value 0 -Type DWord -Force

                # WDF Idle / Directed Power Transitions (overrides hdaudbus.inf on DEV_E2F7)
                $wdfKey = Join-Path $devParams "WDF"
                if (!(Test-Path $wdfKey)) { New-Item -Path $wdfKey -Force | Out-Null }
                Set-ItemProperty -Path $wdfKey -Name "D3ColdSupported" -Value 0 -Type DWord -Force
                Set-ItemProperty -Path $wdfKey -Name "IdleInWorkingState" -Value 0 -Type DWord -Force
                Set-ItemProperty -Path $wdfKey -Name "WdfDirectedPowerTransitionEnable" -Value 0 -Type DWord -Force
            }
            $patchedNodes++
        }
    }
}
Write-GuardLog "Enforced pci.sys GUID ($pciGuid), DMA Management (0), and WDF (0) across $patchedNodes PCIe instances."

# ------------------------------------------------------------------------------
# 5. Override HdBusExt.inf ("Intel(R) HD Graphics D3COLD") in System Class
#    & ULPS/D3Cold in Display Class
# ------------------------------------------------------------------------------
# System Class {4d36e97d-e325-11ce-bfc1-08002be10318} (hosts PCI\VEN_8086&DEV_E2F7 HD Audio Controller)
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97d-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" } | ForEach-Object {
    $clsPath = $_.PSPath
    $props = Get-ItemProperty -Path $clsPath -ErrorAction SilentlyContinue
    $pwrPath = Join-Path $clsPath "PowerSettings"
    if (($props.MatchingDeviceId -match "8086") -or (Test-Path $pwrPath)) {
        if (!(Test-Path $pwrPath)) { New-Item -Path $pwrPath -Force | Out-Null }
        Set-ItemProperty -Path $pwrPath -Name "EnableD3Cold" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $pwrPath -Name "ConservationIdleTime" -Value ([byte[]](0,0,0,0)) -Type Binary -Force
        Set-ItemProperty -Path $pwrPath -Name "PerformanceIdleTime" -Value ([byte[]](0,0,0,0)) -Type Binary -Force
    }
}

# Display Class {4d36e968-e325-11ce-bfc1-08002be10318} (hosts PCI\VEN_8086&DEV_E20B)
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" } | ForEach-Object {
    $p = $_.PSPath
    Set-ItemProperty -Path $p -Name "EnableUlps" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $p -Name "DisableD3Cold" -Value 1 -Type DWord -Force
}

# ------------------------------------------------------------------------------
# 6. Passive Health Check (NEVER call pnputil /restart-device on Code 43!)
# ------------------------------------------------------------------------------
$gpu = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E20B%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_E20%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_56A%'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gpu -or $gpu.ConfigManagerErrorCode -ne 0 -or $gpu.Status -ne "OK") {
    $errCode = if ($gpu) { $gpu.ConfigManagerErrorCode } else { "MISSING" }
    Write-GuardLog "WARNING: Intel Arc GPU reported ErrorCode=$errCode, Status=$($gpu.Status). Keeping user-mode IGCL/PresentMon blocked and avoiding pnputil /restart-device to prevent dxgkrnl.sys deadlock."
} else {
    Write-GuardLog "Intel Arc GPU is healthy (Name=$($gpu.Name), ErrorCode=0, Status=OK)."
}
