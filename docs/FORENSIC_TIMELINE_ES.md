# Cronología Forense: Congelamiento al Iniciar en Intel Arc B580 (`Event ID 1011` + Deadlock de `PresentMonAPI2.dll` / `dxgkrnl.sys`) — v2.0

Este documento registra la evidencia forense exacta (al milisegundo) extraída del Visor de Eventos de Windows, volcados de kernel (`WATCHDOG-*.dmp`) y análisis de archivos `.inf` a lo largo de cuatro incidentes reales (`05/10/2026`, `11/10/2026`, `26/10/2026` y `01/11/2026`) en una PC con **AMD Ryzen 5 7600 + ASRock B650M-H/M.2+ (BIOS 4.43) + Intel Arc B580 (12 GB, Drivers `32.0.101.9030` y `32.0.101.9150`) + Interfaz de Audio USB MOTU (`MOTUCoreUAC`)** bajo **Windows 11 24H2 (Build 26100)**.

---

## 1. Topología PCIe Interna de la Intel Arc B580 (Battlemage)

A diferencia de una placa PCIe de un solo nodo, la Intel Arc B580 incorpora un switch PCIe interno conectado detrás del Root Port PCIe del procesador (`PCI\VEN_1022&DEV_14DB`):
1. **Puerto Upstream del Switch PCIe:** `PCI\VEN_8086&DEV_E2FF` (`memcntrl.inf`)
2. **Puerto Downstream del Switch PCIe (Video):** `PCI\VEN_8086&DEV_E2F0` (`memcntrl.inf`)
   - **Controladora Gráfica (GPU):** `PCI\VEN_8086&DEV_E20B&SUBSYS_18771025&REV_00` (`iigd_dch_d.inf` $\rightarrow$ `igfxnd` / `igdkmdnd64.sys`)
     - Nodo hijo PnP: `VIDEO\INTC_HECI_2` (`gscheci.inf` $\rightarrow$ `GSCx64` / `TeeDriverGSCW8x64.sys`)
     - Nodo hijo PnP: `VIDEO\INTC_PMT` (`PmtChildDriver.inf`)
3. **Puerto Downstream del Switch PCIe (Audio):** `PCI\VEN_8086&DEV_E2F1` (`memcntrl.inf`)
   - **Controladora de Audio HD:** `PCI\VEN_8086&DEV_E2F7` (`hdaudbus.inf` + `HdBusExt.inf` *"Intel(R) HD Graphics D3COLD"*)

---

## 2. Las 3 Trampas Ocultas en los `.inf` de Intel en Windows 11 24H2 (`wNext`)

Al inspeccionar `iigd_dch_d.inf`, `memcntrl.inf`, `HdBusExt.inf` y `C:\Windows\INF\pci.inf`, descubrimos tres mecanismos ocultos que hacen fallar los ajustes de registro convencionales:

### Trampa A: En Windows 11 24H2 (`[BMG_IAG_E20B_FWU_WNEXT.HW]`), Intel usa `[DMAr_AddReg1]` por dispositivo en lugar de `[DMAr_AddReg3]`
En `iigd_dch_d.inf`:
- En Windows 10 y Windows 11 22H2/23H2 (`[BMG_W11_IAG_E20B_FWU.Services]`), Intel usa `[DMAr_AddReg3]`, que escribe `Services\igfxnd\Parameters\DmaRemappingCompatible = 3`.
- En **Windows 11 24H2 Build 26100+ (`[BMG_IAG_E20B_FWU_WNEXT.HW]`, líneas 2609–2625)**, Intel cambió a **`[DMAr_AddReg1]`** (líneas 4246–4250):
  ```ini
  [BMG_IAG_E20B_FWU_WNEXT.HW]
  Include = pci.inf
  Needs = PciD3ColdSupported.Hw
  AddReg = DMAr_AddReg1

  [DMAr_AddReg1]
  HKR,"DMA Management","RemappingSupported",0x00010001, 1
  HKR,"DMA Management","RemappingFlags",0x00010001, 1
  ```
  Como `[BMG_IAG_E20B_FWU_WNEXT.HW]` es una sección `.HW`, `HKR` escribe directamente dentro de `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_E20B...\Device Parameters\DMA Management` (una clave cuyos permisos pertenecen exclusivamente a `NT AUTHORITY\SYSTEM`). Por eso, poner `Services\igfxnd\Parameters\DmaRemappingCompatible = 0` **no desactiva** el remapeo DMA del IOMMU en Windows 11 24H2.

### Trampa B: `pci.sys` lee `D3ColdSupported` y `ASPMOptOut` desde la subclave GUID `e5b3b5ac-9725-4f78-963f-03dfb1d828c7`
Tanto `iigd_dch_d.inf` (`DEV_E20B`) como `memcntrl.inf` (`DEV_E2FF`, `DEV_E2F0`, `DEV_E2F1`) incluyen `Needs = PciD3ColdSupported.Hw` desde `C:\Windows\INF\pci.inf`.
En `C:\Windows\INF\pci.inf` (líneas 110–255), `pci.sys` **no** lee `Device Parameters\D3ColdSupported`, sino la subclave GUID:
```ini
[PciD3ColdSupported.Hw.AddReg]
HKR,"e5b3b5ac-9725-4f78-963f-03dfb1d828c7","D3ColdSupported",0x00010001,1

[PciD3ColdUnsupported.Hw.AddReg]
HKR,"e5b3b5ac-9725-4f78-963f-03dfb1d828c7","D3ColdSupported",0x00010001,0

[PciASPMOptOut.Hw.AddReg]
HKR,"e5b3b5ac-9725-4f78-963f-03dfb1d828c7","ASPMOptOut",0x00010001,1

[PciExtraSettleTimeRequired.Hw.AddReg]
HKR,"e5b3b5ac-9725-4f78-963f-03dfb1d828c7","SettleTimeRequired",0x00010001,1

[PciIgnoreErrorsDuringPLDR.Hw.AddReg]
HKR,"e5b3b5ac-9725-4f78-963f-03dfb1d828c7","IgnoreErrorsDuringPLDR",0x00010001,1
```

### Trampa C: `HdBusExt.inf` ("Intel(R) HD Graphics D3COLD") fuerza D3Cold en el audio PCIe (`DEV_E2F7`)
`HdBusExt.inf` escribe `PowerSettings\EnableD3Cold = 1` en `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e97d-e325-11ce-bfc1-08002be10318}\0066` y `hdaudbus.inf` escribe `Device Parameters\WDF\IdleInWorkingState = 1` y `WdfDirectedPowerTransitionEnable = 1` sobre `PCI\VEN_8086&DEV_E2F7`.

---

## 3. Reconstrucción al Milisegundo del Congelamiento del `01/11/2026` (`16:59:39` – `17:06:30`)

El `01/11/2026`, con VBS e Hyper-V ya desactivados (`0`), la placa volvió a caer en `Código 43` a las `16:59:50.766` y congeló la PC en 3 arranques seguidos. Al cruzar `Microsoft-Windows-Kernel-PnP/Driver Watchdog`, `Microsoft-Windows-PCI/Operational`, `Microsoft-Windows-WerKernel/Operational`, `ArcBootGuard.log` y `C:\ProgramData\Intel\IGS\Logs\App20261101.log`, reconstruimos la cadena exacta:

### Arranque 1 (`16:59:39` – `17:00:33`): Bloqueo PnP de 5.034 ms por `MOTUCoreUAC` $\rightarrow$ `STATUS_TIMEOUT` en `dxgkrnl.sys` $\rightarrow$ Congelamiento por `PresentMonAPI2.dll`
- **`16:59:43.917` – `16:59:43.949` (`PCI/Operational`):** `PCI\VEN_8086&DEV_E20B` pasa de `UNINITIALIZED` a `STARTED`. `igfxnd.sys` empieza a enumerar sus dispositivos hijos PnP (`VIDEO\INTC_HECI_2` $\rightarrow$ `GSCx64` / `TeeDriverGSCW8x64.sys`) mientras `IntelGFXFWupdateTool` consulta el firmware GSC/OPROM.
- **`16:59:45.649` – `16:59:50.683` (`Kernel-PnP/Driver Watchdog Event ID 902 y 903`):** El dispositivo `USB\VID_07FD&PID_000B&MI_00` (`Service: MOTUCoreUAC`, interfaz de audio USB MOTU) inicia en el hilo global de arranque de dispositivos PnP del kernel (`Thread ID 0x178`) y **bloquea el hilo PnP durante `5.034 milisegundos`**.
- **`16:59:50.766` (+83 ms después de que `MOTUCoreUAC` libera el hilo `0x178`):** Como `TdrDelay` / `TdrDdiDelay` estaba en `10s` y seguían activos `DMA Management\RemappingSupported = 1` + `e5b3b5ac-9725-4f78-963f-03dfb1d828c7\D3ColdSupported = 1`, `dxgkrnl.sys` registra `WerKernel Event ID 1001` (`BugcheckCode 0x1A8`, `Status: STATUS_TIMEOUT`, `WATCHDOG-20261101-1659.dmp`) y desconecta `PCI\VEN_8086&DEV_E20B` (`Kernel-PnP Event ID 1011`, `ConfigManagerErrorCode = 43`).
- **`17:00:02.486` – `17:00:11.026` (`ArcBootGuard.log` y `WerKernel`):** `ArcBootGuard.ps1` v1.0 detecta `ErrorCode = 43` y ejecuta `pnputil.exe /restart-device` sobre `DEV_E20B` y `DEV_E2F0`. Cada llamada a `pnputil` provoca un fallo de watchdog en el proceso `System` (`PID 4`) a las `17:00:03.067`, `17:00:05.444` y `17:00:08.613` (`WATCHDOG-20261101-1700.dmp` / `1700_01.dmp` / `1700_02.dmp`).
- **`17:00:27.235` (`Service20261101.log`):** Aunque habíamos borrado `IntelGraphicsSoftware` de la clave `Run`, el servicio de Windows **`intelgraphicssoftwareservice`** (`IntelGraphicsSoftware.Service.exe`) lanza automáticamente `IntelGraphicsSoftware.exe --minimized` al iniciar sesión.
- **`17:00:32.854` – `17:00:32.875` (`App20261101.log`):** `IntelGraphicsSoftware.exe` carga **`PresentMonAPI2.dll`** (`17:00:32.854`) e invoca `ctlInit()` (`result=1073741825`) y `ctlEnumerateDevices()` (`result=1073741836`) sobre la GPU en `Código 43`.
- **`17:00:33`:** **El kernel de Windows se congela por completo.**

### Arranque 2 (`17:05:53`) y Arranque 3 (`17:06:26`): Deadlock de Kernel en `System` (PID 4) al ejecutar `pnputil /restart-device`
- En el Arranque 2 (`17:05:53.878`) y Arranque 3 (`17:06:26.710`), el switch PCIe sigue trabado en `Código 43` tras el botón de Reset.
- Cuando `ArcBootGuard.ps1` v1.0 ejecuta `pnputil.exe /restart-device` sobre `DEV_E20B`, **el kernel se clava en el acto en mitad de la escritura en disco**, dejando `141` bytes nulos (`\x00`) en el Arranque 2 y `259` bytes nulos (`\x00`) en el Arranque 3 dentro de `ArcBootGuard.log`.
- Esto demuestra que **nunca se debe llamar a `pnputil /restart-device` ni `/disable-device` sobre una GPU Battlemage en `Código 43`**.
