# Forensic Timeline: Intel Arc B580 Startup Freeze (`Event ID 1011` + `Overlay.exe` Deadlock)

This document records the exact, millisecond-level Windows Event Log and WMI telemetry captured across three separate freeze events (`2026-10-05`, `2026-10-11`, and `2026-10-26`) on an **AMD Ryzen 5 7600 + ASRock B650M-H/M.2+ (BIOS 4.43) + Intel Arc B580 (12 GB, Driver `32.0.101.9030` & `32.0.101.9150`)** running **Windows 11 24H2 (Build 26100)**.

---

## 1. The Hardware PCIe Topology of the Intel Arc B580 (Battlemage)

Unlike simple single-endpoint PCIe devices, the Intel Arc B580 uses an internal PCIe Switch hierarchy:
1. **PCIe Upstream Switch Port:** `PCI\VEN_8086&DEV_E2FF`
2. **PCIe Downstream Switch Port (Display):** `PCI\VEN_8086&DEV_E2F0`
   - **Display Controller (GPU):** `PCI\VEN_8086&DEV_E20B&SUBSYS_18771025&REV_00` (`igfxnd` / `igdkmdnd64.sys`)
3. **PCIe Downstream Switch Port (Audio):** `PCI\VEN_8086&DEV_E2F1`
   - **HD Audio Controller:** `PCI\VEN_8086&DEV_E2F7`

### What Intel's INF (`iigd_dch_d.inf`) Configures by Default
In section `[BMG_W11_IAG_E20B_FWU.Services]` and `[BMG_W11_IAG_E20B_FWU.HW]`:
```ini
[BMG_W11_IAG_E20B_FWU.Services]
AddService = igfxnd, 0x00000002, igfx_Service_Inst, igfx_EventLog_Inst
AddReg = DMAr_AddReg3

[DMAr_AddReg3]
; Opts igdkmdnd64.sys into Kernel DMA Remapping (IOMMU page table isolation)
HKR,Parameters,DmaRemappingCompatible,0x00010001,3

[BMG_W11_IAG_E20B_FWU.HW]
Needs = PciD3ColdSupported.Hw
```

---

## 2. Millisecond Correlation of Stage 1 (`Event ID 1011` Surprise Removal)

Across all three freeze incidents, `Microsoft-Windows-Kernel-PnP/Device Management` logged **`Event ID 1011`** (`Device PCI\VEN_8086&DEV_E20B... has been surprise removed as it was reported to be failing`) **~138 to 222 ms** before `Microsoft-Windows-Wininit` initialized VBS / Credential Guard (`lsaiso.exe`):

| Incident Date | `Kernel-PnP` Event 1011 (`DEV_E20B` Surprise Removed) | PnP Instance ID (Changes After Every DDU Run) | `Wininit` Event 13 (`lsaiso.exe`) & `Hyper-V` Event 129 (`IOMMU`) |
| :--- | :--- | :--- | :--- |
| **2026-08-19** | `19:01:18.652` | `6&81e8c03&0&00080009` | Cold boot surprise removal |
| **2026-08-26** | `18:13:12.697` (`+3` warm reboots at `18:34`, `18:45`, `18:53`) | `6&81e8c03&0&00080009` | 4 consecutive freezes until DDU in Safe Mode |
| **2026-09-12** | `17:36:34.397` | `6&1bb74b5d&0&00080009` | Cold boot surprise removal |
| **2026-09-19** | `17:07:05.878` | `6&1bb74b5d&0&00080009` | Cold boot surprise removal |
| **2026-10-05** | `11:41:20.129` | `6&1ddf9734&0&00080009` | `11:41:20.267` (**+138 ms**) |
| **2026-10-11** | `14:20:11.677` | `6&1ddf9734&0&00080009` | `14:20:11.883` (**+206 ms**) |
| **2026-10-26** | `10:59:06.879` | `6&a46d7da&0&00080009` | `10:59:07.101` (**+222 ms**) |

### Why Disabling "Memory Integrity (HVCI)" in the Windows GUI Did Not Stop Stage 1
On `2026-10-11`, `HypervisorEnforcedCodeIntegrity\Enabled` was set to `0`. However, on Windows 11 24H2:
- `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\EnableVirtualizationBasedSecurity` remained `1`.
- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LsaCfgFlagsDefault` remained `2` (Credential Guard enabled by default).
- Consequently, on `2026-10-26 10:59:05`, the kernel still logged:
  - `Hyper-V-Hypervisor Event ID 129`: *"Hypervisor initialized I/O remapping (IOMMU)."*
  - `DeviceGuard Event ID 153`: *"Virtualization-based security (policies: VBS Enabled, VSM Required) is enabled."*
  - `Wininit Event ID 13`: *"Credential Guard (lsaiso.exe) was started and is protecting LSA credentials."*

---

## 3. Millisecond Correlation of Stage 2 (The 35-Second Post-Login Kernel Deadlock)

When `Event ID 1011` occurs at `10:59:06.879`, **Windows is NOT frozen**.
A WMI hardware snapshot captured at `11:01:46.203` (`Devices.xml.bak`) proves the exact device state during the post-boot window:
```xml
<Device>
  <Title>Intel(R) Arc(TM) B580 Graphics</Title>
  <DeviceID>PCI\VEN_8086&amp;DEV_E20B&amp;SUBSYS_18771025&amp;REV_00\6&amp;951E780&amp;0&amp;00080009</DeviceID>
  <DriverVersion>32.0.101.9150</DriverVersion>
  <ConfigManagerErrorCode>43</ConfigManagerErrorCode>
  <Availability>8</Availability>
</Device>
```

Here is the exact sequence from `Intel-IGS-Logs/Service`, `Intel-IGS-Logs/App`, and `Intel-IGS-Logs/Overlay` showing what freezes the PC ~35 seconds after boot:

### Boot 1 (`2026-10-26 10:59 AM` — Cold Boot where `Event ID 1011` occurred)
- **`10:59:06.879`:** `Kernel-PnP Event ID 1011` puts `DEV_E20B` into `ConfigManagerErrorCode = 43`.
- **`10:59:06.921`:** `IntelGraphicsSoftware.Service.exe` starts, calls `ctlEnumerateDevices`, receives `result=1073741825` (`0x40000001` — No display adapter found), and sleeps.
- **`10:59:08.500`:** User logs into Windows desktop (running on `BasicDisplay`). PC works normally for 32 seconds.
- **`10:59:40.068`:** Windows `Run` (`HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run\IntelGraphicsSoftware`) executes `"C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe" -s`.
- **`10:59:40.295`:** `IntelGraphicsSoftware.exe` spawns `IntelGraphicsSoftware.Overlay.exe`.
- **`10:59:41.787`:** `Overlay.exe` loads `PresentMonAPI2.dll` (connecting to `PresentMonSharedService` / `PresentMonService.exe`).
- **`10:59:41.805`:** `Overlay.exe` logs its final line before the kernel freezes solid:
  ```text
  [Overlay ID:44] ctlEnumerateDevices, result=1073741836
  ```
  **At `10:59:41.805`, all disk I/O and event logging halt abruptly. The PC is frozen solid.**

### Boot 2 (`2026-10-26 11:01 AM` — Warm Reboot after pressing the physical Reset button)
- **`11:01:23.000`:** System boots after Reset button (`Kernel-Power Event ID 41`). Because a warm reset does not remove ATX/PCIe slot power, the Battlemage PCIe switch (`DEV_E2FF` / `DEV_E2F0` / `DEV_E20B`) wakes up **still latched in `ConfigManagerErrorCode = 43`** (confirmed in `Devices.xml.bak` at `11:01:46.203`).
- **`11:01:50.112`:** Windows `Run` launches `IntelGraphicsSoftware.exe -s` $\rightarrow$ spawns `IntelGraphicsSoftware.Overlay.exe`.
- **`11:01:51.784`:** `Overlay.exe` loads `PresentMonAPI2.dll` and calls `[Overlay ID:44] ctlEnumerateDevices, result=1073741836`.
- **At `11:01:51.784`, the PC freezes solid a second time.**
