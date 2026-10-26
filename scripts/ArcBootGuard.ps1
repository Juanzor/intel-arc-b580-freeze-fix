# ==============================================================================
# Intel Arc B580 / Battlemage & Alchemist Self-Healing Boot Guard (ArcBootGuard.ps1)
# Runs as NT AUTHORITY\SYSTEM at Windows Startup and Logon via Scheduled Task.
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"
$LogDir = "C:\ProgramData\IntelArcGuard"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "ArcBootGuard.log"

function Write-GuardLog([string]$msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    "$ts - $msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-GuardLog "=== ArcBootGuard triggered (Context: $env:USERNAME) ==="

# 1. Neutralize startup auto-run & deadlock triggers (Stage 2 Prevention)
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

# Stop processes that trigger the IGCL ctlEnumerateDevices kernel deadlock on Code 43
Get-Process -Name "IntelGraphicsSoftware.Overlay", "PresentMonService", "igfxShaderDistributionService", "esrv_svc", "SurSvc", "collector_service", "telemetry_agent" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$igsDir = "C:\Program Files\Intel\Intel Graphics Software"
if (Test-Path $igsDir) {
    foreach ($exe in @("IntelGraphicsSoftware.Overlay.exe", "PresentMonService.exe")) {
        $fullPath = Join-Path $igsDir $exe
        if (Test-Path $fullPath) {
            Rename-Item -Path $fullPath -NewName "$exe.disabled" -Force -ErrorAction SilentlyContinue
            Write-GuardLog "Disabled background executable: $fullPath"
        }
    }
}

$pmSharedDir = "C:\Program Files\Intel\PresentMonSharedService"
if (Test-Path $pmSharedDir) {
    $pmExe = Join-Path $pmSharedDir "PresentMonService.exe"
    if (Test-Path $pmExe) {
        Rename-Item -Path $pmExe -NewName "PresentMonService.exe.disabled" -Force -ErrorAction SilentlyContinue
        Write-GuardLog "Disabled PresentMonSharedService executable: $pmExe"
    }
}

# Disable conflictive auxiliary & telemetry services (while keeping DSAService enabled for normal driver updates)
$toxicServices = @(
    "PresentMonSharedService",
    "IGSDSserviceDiscrete",
    "IntelGFXFWupdateTool",
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

# Keep DSAService & DSAUpdateService enabled (Delayed Auto-Start) so built-in driver updates in Intel Graphics Software work normally
foreach ($dsaSvc in @("DSAService", "DSAUpdateService")) {
    if (Get-Service -Name $dsaSvc -ErrorAction SilentlyContinue) {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$dsaSvc" /v Start /t REG_DWORD /d 2 /f | Out-Null
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$dsaSvc" /v DelayedAutoStart /t REG_DWORD /d 1 /f | Out-Null
        Start-Service -Name $dsaSvc -ErrorAction SilentlyContinue
    }
}

# Keep intelgraphicssoftwareservice on Manual (3) so it never races during boot
if (Get-Service -Name "intelgraphicssoftwareservice" -ErrorAction SilentlyContinue) {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\intelgraphicssoftwareservice" /v Start /t REG_DWORD /d 3 /f | Out-Null
}

# 2. Enforce DmaRemappingCompatible = 0 on igfxnd (Stage 1 Prevention: overrides INF's 3)
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters") {
    $curDma = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters" -Name "DmaRemappingCompatible" -ErrorAction SilentlyContinue).DmaRemappingCompatible
    if ($curDma -ne 0) {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters" -Name "DmaRemappingCompatible" -Value 0 -Type DWord -Force
        Write-GuardLog "Enforced igfxnd DmaRemappingCompatible = 0 (was $curDma)"
    }
}

# 3. Enforce D3ColdSupported = 0 on all Intel Arc PCIe Switch & GPU nodes (E2*, 56*, 4F*)
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\PnP\Pci\Parameters" /v DisableD3Cold /t REG_DWORD /d 1 /f | Out-Null
$pciEnum = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "VEN_8086&DEV_(E2|56|4F)" }
foreach ($devKey in $pciEnum) {
    Get-ChildItem $devKey.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
        $devParams = Join-Path $_.PSPath "Device Parameters"
        $wdfParams = Join-Path $devParams "WDF"
        if (Test-Path $devParams) {
            Set-ItemProperty -Path $devParams -Name "D3ColdSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $wdfParams) {
            Set-ItemProperty -Path $wdfParams -Name "D3ColdSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
}

# Enforce Display Class power settings
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" } | ForEach-Object {
    $p = $_.PSPath
    Set-ItemProperty -Path $p -Name "EnableUlps" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $p -Name "DisableD3Cold" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# 4. Check Intel Arc GPU Health & Auto-Heal Code 43 / Event 1011 Surprise Removal
$gpu = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E20B%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_E20%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_56A%'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gpu -or $gpu.ConfigManagerErrorCode -ne 0 -or $gpu.Status -ne "OK") {
    $errCode = if ($gpu) { $gpu.ConfigManagerErrorCode } else { "MISSING" }
    Write-GuardLog "WARNING: Intel Arc GPU reported unhealthy state (ErrorCode=$errCode, Status=$($gpu.Status)). Initiating automatic PCIe recovery!"

    Stop-Service -Name "intelgraphicssoftwareservice" -Force -ErrorAction SilentlyContinue
    Get-Process -Name "IntelGraphicsSoftware*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($gpu -and $gpu.DeviceID) {
        Write-GuardLog "Restarting GPU device $($gpu.DeviceID)..."
        pnputil.exe /restart-device "$($gpu.DeviceID)" | Out-Null
        Start-Sleep -Seconds 2
    }

    $gpu = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E20B%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_E20%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_56A%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $gpu -or $gpu.ConfigManagerErrorCode -ne 0) {
        $switchPort = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E2F0%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_4F8%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($switchPort -and $switchPort.DeviceID) {
            Write-GuardLog "Restarting parent PCIe Switch Port $($switchPort.DeviceID)..."
            pnputil.exe /restart-device "$($switchPort.DeviceID)" | Out-Null
            Start-Sleep -Seconds 2
        }
        if ($gpu -and $gpu.DeviceID) {
            Write-GuardLog "Cycling disable/enable on GPU $($gpu.DeviceID)..."
            pnputil.exe /disable-device "$($gpu.DeviceID)" | Out-Null
            Start-Sleep -Seconds 1
            pnputil.exe /enable-device "$($gpu.DeviceID)" | Out-Null
            Start-Sleep -Seconds 2
        }
        pnputil.exe /scan-devices | Out-Null
    }

    $gpuAfter = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'PCI\\VEN_8086&DEV_E20B%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_E20%' OR DeviceID LIKE 'PCI\\VEN_8086&DEV_56A%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-GuardLog "Post-recovery GPU state: Name=$($gpuAfter.Name), ErrorCode=$($gpuAfter.ConfigManagerErrorCode), Status=$($gpuAfter.Status)"
} else {
    Write-GuardLog "Intel Arc GPU is healthy (Name=$($gpu.Name), ErrorCode=0, Status=OK)."
    if (Get-Service -Name "intelgraphicssoftwareservice" -ErrorAction SilentlyContinue) {
        Start-Service -Name "intelgraphicssoftwareservice" -ErrorAction SilentlyContinue
    }
}
