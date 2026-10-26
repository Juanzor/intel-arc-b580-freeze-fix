# Cronología Forense: Congelamiento al Iniciar en Intel Arc B580 (`Event ID 1011` + Deadlock de `Overlay.exe`)

Este documento detalla la correlación exacta (al milisegundo) extraída del Visor de Eventos de Windows y de instantáneas WMI durante tres congelamientos reales (`05/10/2026`, `11/10/2026` y `26/10/2026`) en una PC con **AMD Ryzen 5 7600 + ASRock B650M-H/M.2+ (BIOS 4.43) + Intel Arc B580 (12 GB, Drivers `32.0.101.9030` y `32.0.101.9150`)** bajo **Windows 11 24H2 (Build 26100)**.

---

## 1. Topología PCIe Interna de la Intel Arc B580 (Battlemage)

A diferencia de una placa PCIe de un solo nodo, la Intel Arc B580 incorpora un switch PCIe interno:
1. **Puerto Upstream del Switch PCIe:** `PCI\VEN_8086&DEV_E2FF`
2. **Puerto Downstream del Switch PCIe (Video):** `PCI\VEN_8086&DEV_E2F0`
   - **Controladora Gráfica (GPU):** `PCI\VEN_8086&DEV_E20B&SUBSYS_18771025&REV_00` (`igfxnd` / `igdkmdnd64.sys`)
3. **Puerto Downstream del Switch PCIe (Audio):** `PCI\VEN_8086&DEV_E2F1`
   - **Controladora de Audio HD:** `PCI\VEN_8086&DEV_E2F7`

### Qué Configura por Defecto el INF de Intel (`iigd_dch_d.inf`)
En las secciones `[BMG_W11_IAG_E20B_FWU.Services]` y `[BMG_W11_IAG_E20B_FWU.HW]`:
```ini
[BMG_W11_IAG_E20B_FWU.Services]
AddService = igfxnd, 0x00000002, igfx_Service_Inst, igfx_EventLog_Inst
AddReg = DMAr_AddReg3

[DMAr_AddReg3]
; Activa Kernel DMA Remapping (aislamiento de tablas DMA vía IOMMU)
HKR,Parameters,DmaRemappingCompatible,0x00010001,3

[BMG_W11_IAG_E20B_FWU.HW]
Needs = PciD3ColdSupported.Hw
```

---

## 2. Correlación de la Fase 1 (`Event ID 1011` — Desconexión por Sorpresa en el Boot)

En los tres incidentes registrados, el canal `Microsoft-Windows-Kernel-PnP/Device Management` registró el **`Event ID 1011`** (`Device PCI\VEN_8086&DEV_E20B... has been surprise removed as it was reported to be failing`) exactamente **entre 138 y 222 milisegundos** antes de que `Microsoft-Windows-Wininit` inicializara VBS / Credential Guard (`lsaiso.exe`):

| Fecha del Incidente | `Kernel-PnP` Event 1011 (`DEV_E20B` Surprise Removed) | ID de Instancia PnP (Cambia Tras Cada DDU) | `Wininit` Event 13 (`lsaiso.exe`) e `Hyper-V` Event 129 (`IOMMU`) |
| :--- | :--- | :--- | :--- |
| **19/08/2026** | `19:01:18.652` | `6&81e8c03&0&00080009` | Desconexión por sorpresa en arranque |
| **26/08/2026** | `18:13:12.697` (`+3` reinicios a las `18:34`, `18:45`, `18:53`) | `6&81e8c03&0&00080009` | 4 congelamientos seguidos hasta pasar DDU |
| **12/09/2026** | `17:36:34.397` | `6&1bb74b5d&0&00080009` | Desconexión por sorpresa en arranque |
| **19/09/2026** | `17:07:05.878` | `6&1bb74b5d&0&00080009` | Desconexión por sorpresa en arranque |
| **05/10/2026** | `11:41:20.129` | `6&1ddf9734&0&00080009` | `11:41:20.267` (**+138 ms**) |
| **11/10/2026** | `14:20:11.677` | `6&1ddf9734&0&00080009` | `14:20:11.883` (**+206 ms**) |
| **26/10/2026** | `10:59:06.879` | `6&a46d7da&0&00080009` | `10:59:07.101` (**+222 ms**) |

### Por qué apagar "Integridad de memoria (HVCI)" desde la interfaz de Windows NO detuvo la Fase 1
El `11/10/2026` se desactivó `HypervisorEnforcedCodeIntegrity\Enabled = 0`. Sin embargo, en Windows 11 24H2:
- `EnableVirtualizationBasedSecurity` siguió en `1`.
- `LsaCfgFlagsDefault` siguió en `2` (Credential Guard activo por defecto).
- Por eso, el `26/10/2026` a las `10:59:05`, el kernel volvió a levantar:
  - `Hyper-V-Hypervisor Event ID 129`: *"Hypervisor initialized I/O remapping (IOMMU)."*
  - `DeviceGuard Event ID 153`: *"Virtualization-based security (policies: VBS Enabled, VSM Required) is enabled."*
  - `Wininit Event ID 13`: *"Credential Guard (lsaiso.exe) was started and is protecting LSA credentials."*

---

## 3. Correlación de la Fase 2 (El Deadlock Mortal a los 35 Segundos de Iniciar Sesión)

Cuando ocurre el `Event ID 1011` a las `10:59:06.879`, **Windows todavía NO se congela**.
La instantánea WMI (`Devices.xml.bak`) capturada a las `11:01:46.203` durante el segundo arranque demuestra cómo queda la GPU en ese intervalo:
```xml
<Device>
  <Title>Intel(R) Arc(TM) B580 Graphics</Title>
  <DeviceID>PCI\VEN_8086&amp;DEV_E20B&amp;SUBSYS_18771025&amp;REV_00\6&amp;951E780&amp;0&amp;00080009</DeviceID>
  <DriverVersion>32.0.101.9150</DriverVersion>
  <ConfigManagerErrorCode>43</ConfigManagerErrorCode>
  <Availability>8</Availability>
</Device>
```

Secuencia exacta en `Intel-IGS-Logs/Service`, `Intel-IGS-Logs/App` e `Intel-IGS-Logs/Overlay`:

### Arranque 1 (`26/10/2026 10:59 AM` — Encendido en frío donde ocurre el `Event ID 1011`)
- **`10:59:06.879`:** `Kernel-PnP Event ID 1011` deja a `DEV_E20B` en `ConfigManagerErrorCode = 43`.
- **`10:59:06.921`:** `IntelGraphicsSoftware.Service.exe` arranca, llama a `ctlEnumerateDevices`, recibe `result=1073741825` (`No display adapter found`) y queda en espera sin colgar la PC.
- **`10:59:08.500`:** El usuario entra al escritorio de Windows (corriendo sobre `BasicDisplay`). La PC funciona normalmente durante 32 segundos.
- **`10:59:40.068`:** La clave `Run` de Windows ejecuta `"C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe" -s`.
- **`10:59:40.295`:** `IntelGraphicsSoftware.exe` lanza `IntelGraphicsSoftware.Overlay.exe`.
- **`10:59:41.787`:** `Overlay.exe` carga `PresentMonAPI2.dll` (conectándose a `PresentMonSharedService` / `PresentMonService.exe`).
- **`10:59:41.805`:** `Overlay.exe` escribe su última línea antes de que el kernel se congele por completo:
  ```text
  [Overlay ID:44] ctlEnumerateDevices, result=1073741836
  ```
  **A las `10:59:41.805` se clava el kernel de Windows y toda la PC queda congelada.**

### Arranque 2 (`26/10/2026 11:01 AM` — Reinicio con botón físico de Reset)
- **`11:01:23.000`:** La PC reinicia tras presionar Reset (`Kernel-Power Event ID 41`). Como un reinicio en caliente no corta los 12V/3.3V del slot PCIe, el switch interno de la placa (`DEV_E2FF` / `DEV_E2F0` / `DEV_E20B`) despierta **todavía bloqueado en `ConfigManagerErrorCode = 43`** (confirmado en `Devices.xml.bak` a las `11:01:46.203`).
- **`11:01:50.112`:** Windows lanza `IntelGraphicsSoftware.exe -s` $\rightarrow$ abre `IntelGraphicsSoftware.Overlay.exe`.
- **`11:01:51.784`:** `Overlay.exe` carga `PresentMonAPI2.dll` y llama a `[Overlay ID:44] ctlEnumerateDevices, result=1073741836`.
- **A las `11:01:51.784`, la PC se vuelve a congelar por completo.**
