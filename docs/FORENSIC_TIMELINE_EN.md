# Forensic Timeline: Intel Arc B580 Startup Freeze (`Event ID 1011` + `PresentMonAPI2.dll` / `dxgkrnl.sys` Deadlock) — v2.0

This document records the exact, millisecond-level Windows Event Log, Kernel Watchdog (`WATCHDOG-*.dmp`), and INF registry telemetry captured across four separate freeze incidents (`2026-10-05`, `2026-10-11`, `2026-10-26`, and `2026-11-01`) on an **AMD Ryzen 5 7600 + ASRock B650M-H/M.2+ (BIOS 4.43) + Intel Arc B580 (12 GB, Driver `32.0.101.9030` & `32.0.101.9150`) + MOTU USB Audio Interface (`MOTUCoreUAC`)** running **Windows 11 24H2 (Build 26100)**.

---

## 1. The Hardware PCIe Topology of the Intel Arc B580 (Battlemage)

Unlike single-endpoint PCIe devices, the Intel Arc B580 uses an internal PCIe Switch hierarchy connected behind the CPU's PCIe Root Port (`PCI\VEN_1022&DEV_14DB`):
1. **PCIe Upstream Switch Port:** `PCI\VEN_8086&DEV_E2FF` (`memcntrl.inf`)
2. **PCIe Downstream Switch Port (Display):** `PCI\VEN_8086&DEV_E2F0` (`memcntrl.inf`)
   - **Display Controller (GPU):** `PCI\VEN_8086&DEV_E20B&SUBSYS_18771025&REV_00` (`iigd_dch_d.inf` $\rightarrow$ `igfxnd` / `igdkmdnd64.sys`)
     - Child PnP Node: `VIDEO\INTC_HECI_2` (`gscheci.inf` $\rightarrow$ `GSCx64` / `TeeDriverGSCW8x64.sys`)
     - Child PnP Node: `VIDEO\INTC_PMT` (`PmtChildDriver.inf`)
3. **PCIe Downstream Switch Port (Audio):** `PCI\VEN_8086&DEV_E2F1` (`memcntrl.inf`)
   - **HD Audio Controller:** `PCI\VEN_8086&DEV_E2F7` (`hdaudbus.inf` + `HdBusExt.inf` *"Intel(R) HD Graphics D3COLD"*)

---

## 2. What Intel's INF Files Actually Write on Windows 11 24H2 (`wNext`)

Inspecting `iigd_dch_d.inf`, `memcntrl.inf`, `HdBusExt.inf`, and `C:\Windows\INF\pci.inf` revealed **three critical traps** that standard registry tweaks miss:

### Trap A: Windows 11 24H2 (`[BMG_IAG_E20B_FWU_WNEXT.HW]`) Uses Per-Device `[DMAr_AddReg1]` Instead of Service `[DMAr_AddReg3]`
In `iigd_dch_d.inf`:
- On Windows 10 and Windows 11 22H2/23H2 (`[BMG_W11_IAG_E20B_FWU.Services]`), Intel uses `[DMAr_AddReg3]`:
  ```ini
  [DMAr_AddReg3]
  HKR, Parameters, DmaRemappingCompatible, %REG_DWORD%, 3
  ```
- On **Windows 11 24H2 Build 26100+ (`[BMG_IAG_E20B_FWU_WNEXT.HW]`, lines 2609–2625)**, Intel switched to **`[DMAr_AddReg1]`** (lines 4246–4250):
  ```ini
  [BMG_IAG_E20B_FWU_WNEXT.HW]
  Include = pci.inf
  Needs = PciD3ColdSupported.Hw
  AddReg = DMAr_AddReg1

  [DMAr_AddReg1]
  HKR,"DMA Management","RemappingSupported",0x00010001, 1
  HKR,"DMA Management","RemappingFlags",0x00010001, 1
  ```
  Because `[BMG_IAG_E20B_FWU_WNEXT.HW]` is an `.HW` section, `HKR` maps to `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_E20B...\Device Parameters\DMA Management` (owned exclusively by `NT AUTHORITY\SYSTEM`). Setting `Services\igfxnd\Parameters\DmaRemappingCompatible = 0` does **not** disable per-device IOMMU DMA Remapping on Windows 11 24H2!

### Trap B: `pci.sys` Reads `D3ColdSupported` and `ASPMOptOut` from GUID Subkey `e5b3b5ac-9725-4f78-963f-03dfb1d828c7`
Both `iigd_dch_d.inf` (`DEV_E20B`) and `memcntrl.inf` (`DEV_E2FF`, `DEV_E2F0`, `DEV_E2F1`) include `Needs = PciD3ColdSupported.Hw` from `C:\Windows\INF\pci.inf`.
In `C:\Windows\INF\pci.inf` (lines 110–255), `pci.sys` does **not** read `Device Parameters\D3ColdSupported`; it reads the hardware GUID subkey:
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

### Trap C: `HdBusExt.inf` ("Intel(R) HD Graphics D3COLD") Forces `DEV_E2F7` into D3Cold
`HdBusExt.inf` writes `PowerSettings\EnableD3Cold = 1` under `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e97d-e325-11ce-bfc1-08002be10318}\0066` and `hdaudbus.inf` writes `Device Parameters\WDF\IdleInWorkingState = 1` and `WdfDirectedPowerTransitionEnable = 1` on `PCI\VEN_8086&DEV_E2F7`.

---

## 3. Millisecond Reconstruction of the `2026-11-01` Crash (`16:59:39` – `17:06:30`)

On `2026-11-01`, VBS and Hyper-V were already disabled (`0`), yet the GPU still dropped into `Code 43` at `16:59:50.766` and froze across 3 consecutive boots. Cross-referencing `Microsoft-Windows-Kernel-PnP/Driver Watchdog`, `Microsoft-Windows-PCI/Operational`, `Microsoft-Windows-WerKernel/Operational`, `ArcBootGuard.log`, and `C:\ProgramData\Intel\IGS\Logs\App20261101.log` exposed the exact chain of events:

### Boot 1 (`16:59:39` – `17:00:33`): `MOTUCoreUAC` 5,034ms PnP Stall $\rightarrow$ `dxgkrnl.sys` `STATUS_TIMEOUT` $\rightarrow$ `PresentMonAPI2.dll` Freeze
- **`16:59:43.917` – `16:59:43.949` (`PCI/Operational`):** `PCI\VEN_8086&DEV_E20B` transitions from `UNINITIALIZED` to `STARTED`. `igfxnd.sys` begins enumerating child PnP devices (`VIDEO\INTC_HECI_2` $\rightarrow$ `GSCx64` / `TeeDriverGSCW8x64.sys`) while `IntelGFXFWupdateTool` probes GSC/OPROM firmware.
- **`16:59:45.649` – `16:59:50.683` (`Kernel-PnP/Driver Watchdog Event ID 902 & 903`):** `USB\VID_07FD&PID_000B&MI_00` (`Service: MOTUCoreUAC`, MOTU USB Audio Interface) starts on the Windows Kernel PnP Device Start worker thread (`Thread ID 0x178`) and **blocks the global PnP Device Start thread for `5,034 milliseconds`**.
- **`16:59:50.766` (+83 ms after `MOTUCoreUAC` releases Thread `0x178`):** Because `TdrDelay` / `TdrDdiDelay` was only `10s` and `DMA Management\RemappingSupported = 1` + `e5b3b5ac-9725-4f78-963f-03dfb1d828c7\D3ColdSupported = 1` were still active, `dxgkrnl.sys` logs `WerKernel Event ID 1001` (`BugcheckCode 0x1A8`, `Status: STATUS_TIMEOUT`, `WATCHDOG-20261101-1659.dmp`) and surprise-removes `PCI\VEN_8086&DEV_E20B` (`Kernel-PnP Event ID 1011`, `ConfigManagerErrorCode = 43`).
- **`17:00:02.486` – `17:00:11.026` (`ArcBootGuard.log` & `WerKernel`):** `ArcBootGuard.ps1` v1.0 detects `ErrorCode = 43` and executes `pnputil.exe /restart-device` on `DEV_E20B` and `DEV_E2F0`. Each `pnputil` call triggers a kernel watchdog fault inside `ProcessID = 4` (`System`) at `17:00:03.067`, `17:00:05.444`, and `17:00:08.613` (`WATCHDOG-20261101-1700.dmp` / `1700_01.dmp` / `1700_02.dmp`).
- **`17:00:27.235` (`Service20261101.log`):** Even though `IntelGraphicsSoftware` was removed from `HKLM\...\Run`, the Windows service **`intelgraphicssoftwareservice`** (`IntelGraphicsSoftware.Service.exe`) automatically launches `IntelGraphicsSoftware.exe --minimized` on user logon.
- **`17:00:32.854` – `17:00:32.875` (`App20261101.log`):** `IntelGraphicsSoftware.exe` loads **`PresentMonAPI2.dll`** (`17:00:32.854`) and calls `ctlInit()` (`result=1073741825`) and `ctlEnumerateDevices()` (`result=1073741836`) against the broken `Code 43` GPU.
- **`17:00:33`:** **The Windows kernel deadlocks solid.**

### Boot 2 (`17:05:53`) & Boot 3 (`17:06:26`): `pnputil /restart-device` Kernel Deadlock in `System` (PID 4)
- On Boot 2 (`17:05:53.878`) and Boot 3 (`17:06:26.710`), the PCIe switch is still latched in `Code 43` from the warm reset.
- When `ArcBootGuard.ps1` v1.0 calls `pnputil.exe /restart-device` on `DEV_E20B`, **the kernel deadlocks mid-write**, leaving `141` null bytes (`\x00`) on Boot 2 and `259` null bytes (`\x00`) on Boot 3 inside `ArcBootGuard.log`!
- This proves beyond doubt that **calling `pnputil /restart-device` or `/disable-device` on a `Code 43` Battlemage GPU deadlocks `dxgkrnl.sys` inside `System` (PID 4)**.
