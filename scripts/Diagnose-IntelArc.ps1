# ==============================================================================
# Diagnose-IntelArc.ps1 (v2.0)
# Read-only diagnostic tool to check if a Windows PC is vulnerable to the
# Intel Arc B580 / Battlemage Startup Freeze, Code 43 (Event ID 1011),
# Windows 11 24H2 Per-Device DMA Remapping, pci.sys GUID D3Cold, and IGCL Deadlock.
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  INTEL ARC B580 / BATTLEMAGE STARTUP FREEZE DIAGNOSTIC v2.0" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. GPU Status
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "Intel|Arc|Basic" }
Write-Host "`n[1] Display Adapter Status:" -ForegroundColor Yellow
foreach ($g in $gpu) {
    Write-Host "  Name          : $($g.Name)"
    Write-Host "  DriverVersion : $($g.DriverVersion)"
    Write-Host "  Status / Code : $($g.Status) (ErrorCode: $($g.ConfigManagerErrorCode))"
    Write-Host "  Video Mode    : $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate)Hz"
}

# 2. Stage 1 Vulnerability Check (VBS, DMA Management, pci.sys GUID D3Cold/ASPM, TDR)
Write-Host "`n[2] Stage 1 Vulnerability Check (Boot Code 43 / Event ID 1011):" -ForegroundColor Yellow
$dg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
$lsa = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$igfx = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters"
$gfx = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

Write-Host "  VBS (EnableVirtualizationBasedSecurity) : $(if ($dg.EnableVirtualizationBasedSecurity -eq 0) { 'SAFE (0)' } else { "VULNERABLE ($($dg.EnableVirtualizationBasedSecurity))" })"
Write-Host "  Credential Guard (LsaCfgFlagsDefault)   : $(if ($lsa.LsaCfgFlagsDefault -eq 0) { 'SAFE (0)' } else { "VULNERABLE ($($lsa.LsaCfgFlagsDefault))" })"
Write-Host "  igfxnd Service DmaRemappingCompatible   : $(if ($igfx.DmaRemappingCompatible -eq 0) { 'SAFE (0)' } else { "VULNERABLE ($($igfx.DmaRemappingCompatible))" })"
Write-Host "  dxgkrnl TDR Timeout (TdrDelay/DdiDelay) : $(if ($gfx.TdrDelay -ge 20) { "SAFE ($($gfx.TdrDelay)s)" } else { "VULNERABLE ($($gfx.TdrDelay)s)" })"

$pciGuid = "e5b3b5ac-9725-4f78-963f-03dfb1d828c7"
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI" | Where-Object { $_.PSChildName -match "VEN_8086&DEV_E2" } | ForEach-Object {
    $devId = $_.PSChildName
    Get-ChildItem $_.PSPath | ForEach-Object {
        $dp = Join-Path $_.PSPath "Device Parameters"
        $g = Get-ItemProperty (Join-Path $dp $pciGuid)
        $d = Get-ItemProperty (Join-Path $dp "DMA Management")
        Write-Host "  $devId -> pci.sys GUID [D3Cold=$($g.D3ColdSupported), ASPMOptOut=$($g.ASPMOptOut)] | Win11 24H2 DMA [RemappingSupported=$($d.RemappingSupported)]"
    }
}

# 3. Stage 2 Vulnerability Check (Services & PresentMon / IGS)
Write-Host "`n[3] Stage 2 Vulnerability Check (Post-Login Kernel Deadlock):" -ForegroundColor Yellow
foreach ($svcName in @("intelgraphicssoftwareservice", "PresentMonSharedService", "IntelGFXFWupdateTool", "IGSDSserviceDiscrete", "ESRV_SVC_QUEENCREEK")) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$svcName'"
    Write-Host "  Service $svcName : $(if ($s) { "$($s.State) ($($s.StartMode))" } else { 'SAFE (Not installed)' })"
}

# 4. Historical Kernel-PnP Event ID 1011 & PnP Watchdog Event ID 902/903 Check
Write-Host "`n[4] Historical Kernel-PnP Event ID 1011 (Surprise Removal):" -ForegroundColor Yellow
$events1011 = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1011} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($events1011) {
    foreach ($ev in $events1011) {
        Write-Host "    - $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.fff')) : $($ev.Message -replace '\r?\n', ' ')" -ForegroundColor Red
    }
} else {
    Write-Host "  0 recent Event ID 1011 occurrences found." -ForegroundColor Green
}
Write-Host "==================================================================" -ForegroundColor Cyan
