# ==============================================================================
# Instalador Limpio WHQL + Blindaje Forense v2.0 para Intel Arc B580 (Battlemage)
# ==============================================================================
$ErrorActionPreference = "Continue"
$GuardDir = "C:\ProgramData\IntelArcGuard"
if (!(Test-Path $GuardDir)) { New-Item -ItemType Directory -Path $GuardDir -Force | Out-Null }
$StatusFile = Join-Path $GuardDir "install_v2_status.txt"
$TranscriptFile = Join-Path $GuardDir "install_v2_transcript.log"
Start-Transcript -Path $TranscriptFile -Force | Out-Null

"RUNNING" | Out-File -FilePath $StatusFile -Encoding UTF8 -Force

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " 1. Instalando Driver WHQL 32.0.101.9150 Limpio (Sin Bloatware IGS/PresentMon)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$GfxDir = "C:\ProgramData\IntelArcGuard\driver_cache\extracted\Graphics"
if (!(Test-Path "$GfxDir\iigd_dch_d.inf")) {
    $ExePath = "C:\ProgramData\IntelArcGuard\driver_cache\gfx_win_101.9150.exe"
    $SevenZip = "$env:LOCALAPPDATA\Microsoft\WindowsApps\7z.exe"
    if ((Test-Path $ExePath) -and (Test-Path $SevenZip)) {
        Write-Host "Extrayendo paquete WHQL desde $ExePath..." -ForegroundColor Yellow
        & $SevenZip x $ExePath "-oC:\ProgramData\IntelArcGuard\driver_cache\extracted" -y | Out-Null
    }
}

$InfList = @(
    "$GfxDir\memcntrl.inf",
    "$GfxDir\gscheci.inf",
    "$GfxDir\GSCAuxDriver.inf",
    "$GfxDir\PmtChildDriver\PmtChildDriver.inf",
    "$GfxDir\I2CDriver\Intel_NF_I2C_Child.inf",
    "$GfxDir\CtaChildDriver\CtaChildDriver.inf",
    "$GfxDir\HdBusExt.inf",
    "$GfxDir\MSHdaDac.inf",
    "$GfxDir\DisplayAudio\12.1\IntcDAud.inf",
    "$GfxDir\iigd_dch_d.inf"
)

foreach ($inf in $InfList) {
    if (Test-Path $inf) {
        Write-Host " -> Instalando INF: $(Split-Path $inf -Leaf)..." -ForegroundColor Gray
        pnputil.exe /add-driver "$inf" /install
    }
}

pnputil.exe /scan-devices | Out-Null
Start-Sleep -Seconds 3

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 2. Instalando ArcBootGuard v2.0 y Tarea Programada (NT AUTHORITY\SYSTEM)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$SourceGuard = Join-Path $PSScriptRoot "ArcBootGuard.ps1"
$DestGuard = Join-Path $GuardDir "ArcBootGuard.ps1"
if (Test-Path $SourceGuard) {
    Copy-Item -Path $SourceGuard -Destination $DestGuard -Force
    Write-Host " -> ArcBootGuard.ps1 v2.0 copiado a $DestGuard" -ForegroundColor Green
}

# Configurar plan de energia PCIe ASPM = Off (0)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null

# Registrar Tarea Programada como SYSTEM (AtStartup + AtLogOn, sin repeticiones cada 15 min)
$TaskName = "IntelArcBootGuard"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestGuard`""
$TriggerBoot = New-ScheduledTaskTrigger -AtStartup
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($TriggerBoot, $TriggerLogon) -Principal $Principal -Settings $Settings -Force | Out-Null

# Permitir lectura y ejecucion de la tarea para verificacion sin UAC
try {
    $sch = New-Object -ComObject "Schedule.Service"
    $sch.Connect()
    $root = $sch.GetFolder("\")
    $taskObj = $root.GetTask($TaskName)
    $sddl = $taskObj.GetSecurityDescriptor(0xF)
    if ($sddl -notmatch "A;;GRGX;;;AU") {
        $taskObj.SetSecurityDescriptor($sddl + "(A;;GRGX;;;AU)(A;;GRGX;;;BU)", 0)
    }
} catch {}

Write-Host " -> Ejecutando IntelArcBootGuard como NT AUTHORITY\SYSTEM para blindar Enum\PCI..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 5

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 3. Verificando Estado Final de la GPU y Blindaje de Registro" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$vc = Get-CimInstance Win32_VideoController | Select-Object Name, Status, ConfigManagerErrorCode, DriverVersion, CurrentRefreshRate
$vc | Format-List

"DONE: $($vc.Name) | Version=$($vc.DriverVersion) | ErrorCode=$($vc.ConfigManagerErrorCode) | Refresh=$($vc.CurrentRefreshRate)Hz" | Out-File -FilePath $StatusFile -Encoding UTF8 -Force
Stop-Transcript | Out-Null
Write-Host "`n[COMPLETADO] Todo listo. Esta ventana se cerrara en 3 segundos..." -ForegroundColor Green
Start-Sleep -Seconds 3
