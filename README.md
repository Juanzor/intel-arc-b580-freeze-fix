# Intel Arc B580 / Battlemage & Alchemist — Startup Freeze, Code 43 (`Event ID 1011`) & DDU Loop: Forensic Root Cause & Permanent Fix (v2.0)
# Intel Arc B580 — Congelamiento al Iniciar Windows, Código 43 (`Event ID 1011`) y Bucle de DDU: Causa Raíz Forense y Solución Definitiva (v2.0)

[![Platform](https://img.shields.io/badge/OS-Windows%2011%2024H2%20%2F%2023H2%20%2F%2010-0078D6?logo=windows)](https://github.com/Juanzor/intel-arc-b580-freeze-fix)
[![GPU](https://img.shields.io/badge/GPU-Intel%20Arc%20B580%20%7C%20B570%20%7C%20A770%20%7C%20A750-0068B5?logo=intel)](https://github.com/Juanzor/intel-arc-b580-freeze-fix)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

> **TL;DR (English — Updated v2.0):** If your **Intel Arc B580** (or other Arc GPU) works fine for days after a clean driver install, then suddenly **freezes Windows solid ~30–40 seconds after booting**, and **every reboot keeps freezing** until you boot into **Safe Mode and run DDU (Display Driver Uninstaller)** — **your GPU hardware is NOT dying, and your driver files are NOT corrupted.**
> By analyzing millisecond-level Windows Kernel Event Logs, `WATCHDOG-*.dmp` kernel dumps, and Intel's DCH INF files (`iigd_dch_d.inf`, `memcntrl.inf`, `HdBusExt.inf`, and `C:\Windows\INF\pci.inf`), we proved it is a **two-stage software deadlock**:
> 1. **Stage 1 (Silent Boot Drop to `Code 43` / `Event ID 1011`):**
>    - **Windows 11 24H2 (`wNext`) Per-Device IOMMU DMA Remapping (`[DMAr_AddReg1]`):** On Windows 11 24H2 (`Build 26100+`), `iigd_dch_d.inf` (`[BMG_IAG_E20B_FWU_WNEXT.HW]`) sets `Device Parameters\DMA Management\RemappingSupported = 1` and `RemappingFlags = 1` directly inside the `SYSTEM`-owned `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_E20B...` key (ignoring `Services\igfxnd\Parameters\DmaRemappingCompatible = 0`).
>    - **Hidden `pci.sys` GUID Subkey (`e5b3b5ac-9725-4f78-963f-03dfb1d828c7`):** Both `iigd_dch_d.inf` and `memcntrl.inf` (`VEN_8086&DEV_E2FF`, `DEV_E2F0`, `DEV_E2F1`) include `Needs = PciD3ColdSupported.Hw` from `pci.inf`, which enables `D3ColdSupported = 1` under the `pci.sys` GUID subkey `Device Parameters\e5b3b5ac-9725-4f78-963f-03dfb1d828c7`, while `HdBusExt.inf` enables `PowerSettings\EnableD3Cold = 1` and `WDF\IdleInWorkingState = 1` on the card's PCIe Audio controller (`DEV_E2F7`).
>    - **Kernel-PnP Device Start Contention (`dxgkrnl.sys` `STATUS_TIMEOUT`):** If a slow USB/audio driver (e.g., `MOTUCoreUAC` stalling the Kernel-PnP Device Start thread for `5,034 ms`, `Event ID 902/903`) delays child PnP enumeration (`GSCx64` / `VIDEO\INTC_HECI_2`) while `IntelGFXFWupdateTool` probes GSC firmware at boot, `dxgkrnl.sys` hits `STATUS_TIMEOUT` and surprise-removes `DEV_E20B` (`Event ID 1011` $\rightarrow$ `Code 43`). Windows is **not** frozen yet — it boots to the desktop on `BasicDisplay`.
> 2. **Stage 2 (The 35-Second Post-Login Kernel Deadlock):**
>    - ~30–35 seconds after login, `intelgraphicssoftwareservice` (`IntelGraphicsSoftware.Service.exe`) or the Windows `Run` key launches `IntelGraphicsSoftware.exe --minimized` / `IntelGraphicsSoftware.Overlay.exe`, which loads **`PresentMonAPI2.dll`** and calls `ControlLib.dll` (`ctlInit()` / `ctlEnumerateDevices()`) against the `Code 43` GPU — **deadlocking `igdkmdnd64.sys` and freezing the entire PC solid**.
>    - **Critical Trap:** Calling `pnputil /restart-device` or `/disable-device` on `PCI\VEN_8086&DEV_E20B` while it is in `Code 43` **also deadlocks `dxgkrnl.sys` inside `System` (`PID 4`)**!

> **Resumen Ejecutivo (Español — Actualizado v2.0):** Si tu **Intel Arc B580** funciona perfecto durante varios días tras instalar el driver y de repente **congela Windows por completo unos ~30–40 segundos después de iniciar sesión**, obligándote a entrar en **Modo Seguro y pasar DDU** porque cada reinicio vuelve a congelar la PC, **no es una falla física de tu placa ni archivos corruptos del driver.**
> Este repositorio contiene el análisis forense milisegundo a milisegundo de los registros del kernel de Windows, los archivos `.inf` de Intel y los volcados `WATCHDOG-*.dmp`, junto con el **instalador + blindaje automático v2.0 (`IntelArcBootGuard`)** que soluciona ambas fases del problema de raíz.

---

# 🌎 [English] Complete Forensic Analysis & Permanent Fix (v2.0)

## 1. Symptoms Checklist
- **Hardware:** Intel Arc B580 (`PCI\VEN_8086&DEV_E20B`), B570, A770, or A750 (especially common on AMD AM5 Ryzen 7000/9000 + B650/X670 motherboards).
- **OS:** Windows 11 (24H2 / 23H2 / IoT Enterprise LTSC / Pro / Home).
- **The Cycle:**
  1. You run DDU in Safe Mode and cleanly install the latest Intel Arc WHQL driver (`32.0.101.9030`, `32.0.101.9150`, etc.).
  2. The PC works flawlessly for **5 to 15 days** (heavy gaming, 144Hz+, zero crashes).
  3. One day, you turn on the PC, log into Windows, the desktop works for **~30 to 40 seconds**, and suddenly the **entire PC freezes solid**.
  4. Pressing the **Reset** button results in another freeze ~35 seconds after login on every reboot, until you boot into **Safe Mode and run DDU**.

---

## 2. Everything We Tried That Did NOT Work Permanently (And Why)

| # | Attempted Fix | Result | Why It Failed (Forensic Loophole) |
| :--- | :--- | :--- | :--- |
| **1** | **Disabling Fast Startup (`powercfg /h off`) & BIOS ReBAR / Above 4G / CSM** | ❌ **Failed** | Necessary baseline settings, but `Event ID 1011` occurs during a true cold boot inside Windows Kernel-PnP. |
| **2** | **Disabling Memory Integrity (`HVCI = 0`) in Windows Security GUI** | ❌ **Failed after ~10 days** | On Windows 11 24H2, turning off HVCI in the GUI leaves `EnableVirtualizationBasedSecurity = 1` and `LsaCfgFlagsDefault = 2` (`lsaiso.exe` Credential Guard) active, so Hyper-V IOMMU (`Event ID 129`) still initializes at boot. |
| **3** | **Setting `Services\igfxnd\Parameters\DmaRemappingCompatible = 0` & `Device Parameters\D3ColdSupported = 0`** | ⚠️ **Failed after 6 days (`v1.0` Loopholes)** | **Three hidden INF traps:**<br>1. On Windows 11 24H2 (`wNext`), `iigd_dch_d.inf` uses `[DMAr_AddReg1]`, which enables IOMMU DMA remapping per-device under `Device Parameters\DMA Management\RemappingSupported = 1` (`SYSTEM`-only key).<br>2. `pci.inf` & `memcntrl.inf` store `D3ColdSupported = 1` inside the `pci.sys` GUID subkey `Device Parameters\e5b3b5ac-9725-4f78-963f-03dfb1d828c7`.<br>3. `HdBusExt.inf` enables `PowerSettings\EnableD3Cold = 1` on `DEV_E2F7`. |
| **4** | **Auto-restarting the GPU via `pnputil /restart-device` when `Code 43` is detected** | ❌ **Caused instant kernel deadlock** | Calling `pnputil /restart-device` or `/disable-device` on `PCI\VEN_8086&DEV_E20B` while `igfxnd.sys` is in `Code 43` deadlocks `dxgkrnl.sys` inside `System` (`PID 4`). |
| **5** | **Removing `IntelGraphicsSoftware` from `HKLM\...\Run` while leaving `intelgraphicssoftwareservice` enabled** | ❌ **Still froze 33s after boot** | `intelgraphicssoftwareservice` (`IntelGraphicsSoftware.Service.exe`) still launches `IntelGraphicsSoftware.exe --minimized` on logon, which loads `PresentMonAPI2.dll` and calls `ctlInit()` on the `Code 43` GPU. |

---

## 3. How the Permanent Fix v2.0 Works

Our v2.0 solution ([`scripts/Install-IntelArcFix.ps1`](./scripts/Install-IntelArcFix.ps1) + [`scripts/ArcBootGuard.ps1`](./scripts/ArcBootGuard.ps1)) closes every single loophole above:

1. **Closes All Stage 1 (`Event ID 1011` / `Code 43`) Vectors:**
   - **Disables Windows 11 24H2 Per-Device IOMMU DMA Remapping (`[DMAr_AddReg1]`):** Running as `NT AUTHORITY\SYSTEM`, sets `Device Parameters\DMA Management\RemappingSupported = 0` and `RemappingFlags = 0` on all `VEN_8086` PCIe nodes, plus `DmaRemappingCompatible = 0` on `igfxnd`, `HDAudBus`, `GSCx64`, and `PmtChildDriver`.
   - **Enforces the `pci.sys` Hardware GUID Subkey (`e5b3b5ac-9725-4f78-963f-03dfb1d828c7`):** Sets `D3ColdSupported = 0`, `ASPMOptOut = 1`, `SettleTimeRequired = 1`, and `IgnoreErrorsDuringPLDR = 1` on all Battlemage PCIe Switch/GPU/Audio nodes (`E2FF`, `E2F0`, `E2F1`, `E20B`, `E2F7`) and the parent CPU PCIe Root Port (`VEN_1022&DEV_14DB`).
   - **Overrides `HdBusExt.inf` & WDF Directed Power Transitions on `DEV_E2F7`:** Sets `PowerSettings\EnableD3Cold = 0`, `WDF\IdleInWorkingState = 0`, and `WDF\WdfDirectedPowerTransitionEnable = 0`.
   - **Enforces 30-Second DirectX Kernel Watchdog (`dxgkrnl.sys` TDR) Tolerance & Disables Boot Firmware Probes:** Sets `TdrDelay = 30`, `TdrDdiDelay = 30`, `TdrLevel = 3`, and disables `IntelGFXFWupdateTool` (`DisableGfxFWUpdate = 1`) so 5-second USB Audio (`MOTUCoreUAC`) PnP device start stalls at boot never trigger `dxgkrnl.sys` `STATUS_TIMEOUT`.
   - **Disables VBS, Credential Guard (`lsaiso.exe`), and Hyper-V IOMMU.**
2. **Closes All Stage 2 (Post-Login Total Freeze) Vectors:**
   - **Disables `intelgraphicssoftwareservice`, `PresentMonSharedService`, `IGSDSserviceDiscrete`, and `IntelGFXFWupdateTool`** (`Start = 4` Disabled) and neutralizes `PresentMonAPI2.dll`, `PresentMonService.exe`, `IntelGraphicsSoftware.Service.exe`, and `IntelGraphicsSoftware.Overlay.exe`.
   - **Never Calls `pnputil /restart-device` on a `Code 43` GPU:** Prevents the `System` (`PID 4`) `dxgkrnl.sys` kernel deadlock.

---

# 🇦🇷 [Español] Análisis Forense Completo y Solución Definitiva (v2.0)

## 1. Por qué se producía el congelamiento y por qué falló la v1.0 después de 6 días

Al auditar los registros del kernel de los congelamientos del `05/10/2026`, `11/10/2026`, `26/10/2026` y `01/11/2026` junto con los archivos `.inf` del driver WHQL `32.0.101.9150` (`iigd_dch_d.inf`, `memcntrl.inf`, `HdBusExt.inf` y `C:\Windows\INF\pci.inf`), identificamos las **6 causas exactas**:

1. **Windows 11 24H2 (`wNext`) activaba IOMMU DMA Remapping por dispositivo (`[DMAr_AddReg1]`):**
   - En `iigd_dch_d.inf` (línea 2616, sección `[BMG_IAG_E20B_FWU_WNEXT.HW]` exclusiva para Windows 11 24H2 Build 26100+), Intel dejó de usar `Services\igfxnd\Parameters\DmaRemappingCompatible` y pasó a usar `[DMAr_AddReg1]`, que escribe `RemappingSupported = 1` y `RemappingFlags = 1` directamente en `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_E20B...\Device Parameters\DMA Management` (una clave protegida que solo `NT AUTHORITY\SYSTEM` puede modificar).
2. **El switch PCIe interno de Battlemage (`memcntrl.inf`) tenía `D3ColdSupported = 1` oculto bajo una subclave GUID de `pci.sys`:**
   - Tanto `iigd_dch_d.inf` como `memcntrl.inf` (`DEV_E2FF`, `DEV_E2F0`, `DEV_E2F1`) incluyen `Needs = PciD3ColdSupported.Hw` de `pci.inf`. En `C:\Windows\INF\pci.inf`, `pci.sys` **no** lee `Device Parameters\D3ColdSupported`, sino la subclave GUID `Device Parameters\e5b3b5ac-9725-4f78-963f-03dfb1d828c7\D3ColdSupported = 1`.
3. **`HdBusExt.inf` ("Intel HD Graphics D3COLD") activaba D3Cold en el controlador de audio PCIe de la GPU (`DEV_E2F7`):**
   - Escribía `PowerSettings\EnableD3Cold = 1` en la clase `System` (`{4d36e97d-e325-11ce-bfc1-08002be10318}`) y `WDF\IdleInWorkingState = 1` + `WdfDirectedPowerTransitionEnable = 1` sobre `DEV_E2F7`.
4. **Bloqueo de 5.034 ms en el hilo PnP del kernel durante el arranque (`MOTUCoreUAC` $\rightarrow$ `STATUS_TIMEOUT` en `dxgkrnl.sys`):**
   - En el canal `Microsoft-Windows-Kernel-PnP/Driver Watchdog` (`Event ID 902` y `903`), la interfaz de audio USB (`MOTUCoreUAC`) retuvo el bloqueo global de inicio de dispositivos PnP durante **5,034 segundos** (`16:59:45.649` – `16:59:50.683`) mientras `igfxnd.sys` esperaba la enumeración de sus nodos hijos (`GSCx64`). Exactamente `83 ms` después (`16:59:50.766`), `dxgkrnl.sys` alcanzó el límite de 10s de `TdrDelay` (`WATCHDOG-20261101-1659.dmp`) y desconectó la placa con `Event ID 1011` (`Código 43`).
5. **`pnputil /restart-device` sobre una GPU Battlemage en `Código 43` clava el kernel (`System` PID 4):**
   - Cuando `ArcBootGuard.ps1` v1.0 detectó `ErrorCode = 43` y ejecutó `pnputil /restart-device` sobre `DEV_E20B`, el proceso `System` (`PID 4`) entró en deadlock dentro de `dxgkrnl.sys` (dejando `141` y `259` bytes nulos `\x00` en `ArcBootGuard.log`).
6. **`intelgraphicssoftwareservice` lanzaba `IntelGraphicsSoftware.exe --minimized` $\rightarrow$ `PresentMonAPI2.dll` $\rightarrow$ `ctlInit()`:**
   - Aunque se había borrado el autoarranque de la clave `Run`, el servicio `intelgraphicssoftwareservice` abrió `IntelGraphicsSoftware.exe --minimized` al iniciar sesión (`17:00:27`), el cual cargó `PresentMonAPI2.dll` (`17:00:32.854`) y llamó a `ctlInit()` / `ctlEnumerateDevices()` sobre la GPU en `Código 43`, congelando toda la PC a las `17:00:33`.

---

## 2. Qué Hace la Solución Definitiva v2.0

1. **Instalación limpia WHQL por INF (sin el bloatware `IntelGraphicsSoftware` / `PresentMon`) y desactivación total de servicios conflictivos:** Deshabilita `intelgraphicssoftwareservice`, `PresentMonSharedService`, `IGSDSserviceDiscrete`, `IntelGFXFWupdateTool` (`DisableGfxFWUpdate = 1`) y neutraliza `PresentMonAPI2.dll`.
2. **Desactivación de `DMA Management` por dispositivo en Windows 11 24H2 (`NT AUTHORITY\SYSTEM`):** Fuerza `Device Parameters\DMA Management\RemappingSupported = 0` y `RemappingFlags = 0` en todos los nodos `VEN_8086`, además de `DmaRemappingCompatible = 0` en `igfxnd`, `HDAudBus`, `GSCx64` y `PmtChildDriver`.
3. **Blindaje de la subclave GUID `e5b3b5ac-9725-4f78-963f-03dfb1d828c7` de `pci.sys`:** Fuerza `D3ColdSupported = 0`, `ASPMOptOut = 1`, `SettleTimeRequired = 1` e `IgnoreErrorsDuringPLDR = 1` en todos los nodos PCIe de la Arc B580 (`E2FF`, `E2F0`, `E2F1`, `E20B`, `E2F7`) y en el Root Port PCIe del CPU (`VEN_1022&DEV_14DB`), además de forzar `EnableD3Cold = 0` y `WDF\IdleInWorkingState = 0` en `DEV_E2F7`.
4. **Tolerancia de 30s en `TdrDelay` / `TdrDdiDelay`:** Impide que demoras de 5 segundos de periféricos USB en el arranque causen `STATUS_TIMEOUT` en `dxgkrnl.sys`.
5. **Eliminación de `pnputil /restart-device` en [`scripts/ArcBootGuard.ps1`](./scripts/ArcBootGuard.ps1):** Evita el deadlock del proceso `System` (PID 4).

---

## 3. Instalación en 1 Clic / 1-Click Installation

1. Descargá o cloná este repositorio / Clone or download this repository.
2. Hacé doble clic en **`Install-Fix.bat`** (o ejecutá `.\scripts\Install-IntelArcFix.ps1` como Administrador).
3. Verificá el estado en cualquier momento con **`Diagnose.bat`** (`.\scripts\Diagnose-IntelArc.ps1`).

---

## 📂 Repository Structure / Estructura del Repositorio

- [`Install-Fix.bat`](./Install-Fix.bat) — 1-click installer (auto-elevates to Administrator).
- [`Diagnose.bat`](./Diagnose.bat) — 1-click diagnostic report.
- [`scripts/Install-IntelArcFix.ps1`](./scripts/Install-IntelArcFix.ps1) — Complete v2.0 installer & `SYSTEM` task runner.
- [`scripts/ArcBootGuard.ps1`](./scripts/ArcBootGuard.ps1) — `NT AUTHORITY\SYSTEM` startup/logon shield v2.0.
- [`scripts/Diagnose-IntelArc.ps1`](./scripts/Diagnose-IntelArc.ps1) — Read-only v2.0 vulnerability & event log auditor.
- [`scripts/Uninstall-IntelArcFix.ps1`](./scripts/Uninstall-IntelArcFix.ps1) — Clean uninstaller / rollback script.
- [`docs/FORENSIC_TIMELINE_EN.md`](./docs/FORENSIC_TIMELINE_EN.md) — Millisecond-level forensic log breakdown v1.0 & v2.0 (English).
- [`docs/FORENSIC_TIMELINE_ES.md`](./docs/FORENSIC_TIMELINE_ES.md) — Cronología forense detallada v1.0 y v2.0 (Español).
- [`llms.txt`](./llms.txt) — Structured summary optimized for AI search engines and LLMs.
