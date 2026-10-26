# ==============================================================================
# Diagnose-IntelArc.ps1
# Read-only diagnostic tool to check if a Windows PC is vulnerable to the
# Intel Arc B580 / Battlemage 2-Stage Startup Freeze & Code 43 Deadlock.
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  INTEL ARC B580 / BATTLEMAGE STARTUP FREEZE DIAGNOSTIC REPORT" -ForegroundColor Cyan
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

# 2. Stage 1 Vulnerability Check (VBS, Credential Guard, DmaRemappingCompatible, D3Cold)
Write-Host "`n[2] Stage 1 Vulnerability Check (Boot Code 43 / Event ID 1011):" -ForegroundColor Yellow
$dg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
$lsa = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$igfx = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\igfxnd\Parameters"
$pci = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci\Parameters"

$vbsState = if ($dg.EnableVirtualizationBasedSecurity -eq 0) { "SAFE (0)" } else { "VULNERABLE ($($dg.EnableVirtualizationBasedSecurity))" }
$lsaState = if ($lsa.LsaCfgFlagsDefault -eq 0 -and ($null -eq $lsa.LsaCfgFlags -or $lsa.LsaCfgFlags -eq 0)) { "SAFE (0)" } else { "VULNERABLE (Default=$($lsa.LsaCfgFlagsDefault), Flags=$($lsa.LsaCfgFlags))" }
$dmaState = if ($igfx.DmaRemappingCompatible -eq 0) { "SAFE (0)" } else { "VULNERABLE ($($igfx.DmaRemappingCompatible))" }
$d3State  = if ($pci.DisableD3Cold -eq 1) { "SAFE (1)" } else { "VULNERABLE ($($pci.DisableD3Cold))" }

Write-Host "  VBS (EnableVirtualizationBasedSecurity) : $vbsState"
Write-Host "  Credential Guard (LsaCfgFlagsDefault)   : $lsaState"
Write-Host "  igfxnd DmaRemappingCompatible           : $dmaState"
Write-Host "  Global PCIe DisableD3Cold               : $d3State"

# 3. Stage 2 Vulnerability Check (Overlay.exe, PresentMonSharedService, Run key)
Write-Host "`n[3] Stage 2 Vulnerability Check (35s Post-Login Kernel Deadlock):" -ForegroundColor Yellow
$overlayActive = Test-Path "C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.Overlay.exe"
$pmSharedSvc = Get-CimInstance Win32_Service -Filter "Name='PresentMonSharedService'"
$esrvSvc = Get-CimInstance Win32_Service -Filter "Name='ESRV_SVC_QUEENCREEK'"

Write-Host "  IntelGraphicsSoftware.Overlay.exe       : $(if ($overlayActive) { 'VULNERABLE (Active)' } else { 'SAFE (Disabled/Not present)' })"
Write-Host "  PresentMonSharedService                 : $(if ($pmSharedSvc) { "$($pmSharedSvc.State) ($($pmSharedSvc.StartMode))" } else { 'Not installed' })"
Write-Host "  ESRV_SVC_QUEENCREEK (SUR Energy Server) : $(if ($esrvSvc) { "$($esrvSvc.State) ($($esrvSvc.StartMode))" } else { 'Not installed' })"

# 4. Historical Kernel-PnP Event ID 1011 Check
Write-Host "`n[4] Historical Kernel-PnP Event ID 1011 (Surprise Removal) Count:" -ForegroundColor Yellow
$events1011 = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1011} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($events1011) {
    Write-Host "  Found $($events1011.Count) recent Event ID 1011 surprise removal event(s):" -ForegroundColor Red
    foreach ($ev in $events1011) {
        Write-Host "    - $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.fff')) : $($ev.Message -replace '\r?\n', ' ')"
    }
} else {
    Write-Host "  0 recent Event ID 1011 occurrences found." -ForegroundColor Green
}

Write-Host "==================================================================" -ForegroundColor Cyan
