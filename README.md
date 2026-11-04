# obs-legacy-plugin-migrator

![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![OBS Studio](https://img.shields.io/badge/OBS%20Studio-33%2B-302E31?logo=obsstudio&logoColor=white)

**[Español](#español)** · **[English](#english)**

---

## Español

Script de PowerShell que **detecta los plugins marcados como "Legado" en OBS Studio 33+ y los migra** a la nueva estructura de carpetas. Por defecto solo simula; no mueve nada hasta que usas `-Apply`.

### Contexto

Desde OBS Studio 33, los plugins de terceros deben instalarse en:

```text
C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll
C:\ProgramData\obs-studio\plugins\<plugin>\data\*
```

Los plugins en ubicaciones antiguas siguen cargando, pero OBS los marca como **Legado** en `Herramientas > Gestor de plugins`. Los de `Program Files` dejarán de cargarse en OBS 34.0. Referencia oficial: [Legacy Plugin Locations](https://obsproject.com/kb/legacy-plugin-locations).

### Qué hace

| Caso | Origen (legacy) | Acción |
|---|---|---|
| A | `ProgramData\obs-studio\plugins\<plugin>\bin\64bit\` | Sube el contenido a la carpeta del plugin, junto a `data` |
| B | `Program Files\obs-studio\obs-plugins\64bit\` + `data\obs-plugins\<plugin>\` | Mueve DLL, `.pdb` y datos a `ProgramData\...\plugins\<plugin>\` |

- **Simulación por defecto**: sin `-Apply` solo lista lo que haría.
- **Detección de plugins reales**: busca el export `obs_module_load` en cada DLL (o una carpeta de datos con su nombre).
- **Exclusiones**: no toca plugins propios de OBS ni las DLL de CEF.
- **Sin sobrescribir**: si el destino ya existe, omite el archivo (salvo `-Force`).
- **Reversible**: cada migración guarda un manifiesto JSON y `-Undo` la revierte.
- **Seguro**: se niega a ejecutar si OBS está abierto.
- **Bilingüe**: los mensajes salen en español o inglés según el idioma de Windows. Se puede forzar con `-Lang es` o `-Lang en`.

### Requisitos

- Windows con PowerShell 5.1 o superior
- OBS Studio 33 o superior
- PowerShell **como administrador** para migrar (salvo OBS portable)
- OBS **cerrado**

### Cómo ejecutarlo

**1. Abre PowerShell como administrador.** Menú Inicio, escribe `PowerShell`, clic derecho y **Ejecutar como administrador**. Cierra OBS.

**2. Ve a la carpeta del script.**

```powershell
cd C:\ruta\a\obs-legacy-plugin-migrator
```

**3. Permite la ejecución solo en esta ventana.** Windows bloquea por defecto los scripts sin firmar y verás el error *"no está firmado digitalmente"*.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Unblock-File .\Migrate-ObsLegacyPlugins.ps1
```

`-Scope Process` solo afecta a esa ventana; al cerrarla todo vuelve a como estaba. Alternativa en una sola línea:

```powershell
powershell -ExecutionPolicy Bypass -File .\Migrate-ObsLegacyPlugins.ps1
```

**4. Simula primero.** No mueve nada, solo lista lo detectado.

```powershell
.\Migrate-ObsLegacyPlugins.ps1
```

**5. Si el plan se ve bien, migra.**

```powershell
.\Migrate-ObsLegacyPlugins.ps1 -Apply
```

**6. Verifica.** Abre OBS y revisa `Herramientas > Gestor de plugins`: ya no deberían aparecer como *Legado*. Si algo falla:

```powershell
.\Migrate-ObsLegacyPlugins.ps1 -Undo
```

### Parámetros

| Parámetro | Descripción |
|---|---|
| `-Apply` | Ejecuta la migración. Sin él, solo simula |
| `-Undo` | Revierte la última migración (o la de `-ManifestPath`) |
| `-ObsPath <ruta>` | Carpeta de instalación de OBS. Por defecto se autodetecta |
| `-Portable` | OBS portable: el destino es `<ObsPath>\plugins\<plugin>\` |
| `-OrphansTo <plugin>` | Asigna a ese plugin las DLL de dependencias sin dueño claro |
| `-Force` | Sobrescribe archivos que ya existan en el destino |
| `-Detail` | Muestra cada archivo del plan |
| `-Lang auto\|es\|en` | Idioma de los mensajes (por defecto `auto`) |
| `-ManifestPath <json>` | Manifiesto concreto para `-Undo` |
| `-LogDir <ruta>` | Dónde guardar los manifiestos (por defecto `Desktop\obs-migracion`) |

### Ejemplos

```powershell
# Plugin con muchas dependencias (p. ej. obs-localvocal)
.\Migrate-ObsLegacyPlugins.ps1 -Apply -OrphansTo obs-localvocal

# OBS portable
.\Migrate-ObsLegacyPlugins.ps1 -Apply -Portable -ObsPath "D:\OBS"

# Forzar mensajes en inglés y ver el detalle
.\Migrate-ObsLegacyPlugins.ps1 -Lang en -Detail
```

### Solución de problemas

| Problema | Solución |
|---|---|
| *"no está firmado digitalmente"* | Paso 3 de arriba: `Set-ExecutionPolicy -Scope Process Bypass` y `Unblock-File` |
| *"Ejecuta PowerShell como administrador"* | Abre PowerShell con clic derecho, **Ejecutar como administrador** |
| *"Cierra OBS antes de migrar"* | Cierra OBS por completo. Cierra también G HUB y la app de Stream Deck |
| Dice que no hay plugins legacy | Es lo esperado si ya están migrados |
| Un plugin sigue como *Legado* | Instala la versión nueva del autor; mover archivos no siempre basta |
| Errores raros de lectura en OneDrive | Copia el script fuera de OneDrive, por ejemplo a `C:\Tools\` |
| DLL "sin dueño claro" | Usa `-OrphansTo <plugin>` |

### Limitaciones

- **Dependencias compartidas**: el script no puede saber con certeza de qué plugin es cada DLL de dependencia (por ejemplo `ggml*`, `onnxruntime`, `whisper`). Si queda un solo plugin principal, se las asigna; si hay varios, las lista como "sin dueño claro" y no las mueve.
- **Subcarpetas** junto a las DLL (por ejemplo `rocblas\library`): se reportan pero **no se mueven**; revísalas a mano.
- **Instaladores de terceros**: Logitech G HUB o la app de Stream Deck pueden volver a copiar su plugin a la ruta vieja al actualizarse. Si vuelve a salir como *Legado*, ejecuta el script otra vez.
- Solo Windows. En macOS las ubicaciones de plugins no cambian.

> **Recomendación:** haz una copia de `C:\ProgramData\obs-studio\plugins` y de `C:\Program Files\obs-studio\obs-plugins` antes de usar `-Apply`. Es una red de seguridad extra además del `-Undo`.

---

## English

PowerShell script that **detects plugins marked as "Legacy" in OBS Studio 33+ and migrates them** to the new folder layout. It is a dry run by default; nothing is moved until you pass `-Apply`.

### Background

Starting with OBS Studio 33, third-party plugins must be installed to:

```text
C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll
C:\ProgramData\obs-studio\plugins\<plugin>\data\*
```

Plugins in old locations still load, but OBS flags them as **Legacy** in `Tools > Plugin Manager`. Those under `Program Files` will stop loading in OBS 34.0. Official reference: [Legacy Plugin Locations](https://obsproject.com/kb/legacy-plugin-locations).

### What it does

| Case | Legacy source | Action |
|---|---|---|
| A | `ProgramData\obs-studio\plugins\<plugin>\bin\64bit\` | Moves the content up into the plugin folder, next to `data` |
| B | `Program Files\obs-studio\obs-plugins\64bit\` + `data\obs-plugins\<plugin>\` | Moves DLL, `.pdb` and data to `ProgramData\...\plugins\<plugin>\` |

- **Dry run by default**: without `-Apply` it only lists what it would do.
- **Real plugin detection**: scans each DLL for the `obs_module_load` export (or a data folder with its name).
- **Exclusions**: skips OBS first-party plugins and CEF DLLs.
- **No overwriting**: skips files that already exist at the target (unless `-Force`).
- **Reversible**: every migration saves a JSON manifest and `-Undo` reverts it.
- **Safe**: refuses to run while OBS is open.
- **Bilingual**: messages are shown in Spanish or English depending on the Windows language. Force it with `-Lang es` or `-Lang en`.

### Requirements

- Windows with PowerShell 5.1 or later
- OBS Studio 33 or later
- PowerShell **as Administrator** to migrate (except portable OBS)
- OBS **closed**

### How to run it

**1. Open PowerShell as Administrator.** Start menu, type `PowerShell`, right-click and **Run as administrator**. Close OBS.

**2. Go to the script folder.**

```powershell
cd C:\path\to\obs-legacy-plugin-migrator
```

**3. Allow execution for this window only.** Windows blocks unsigned scripts by default and you will see *"is not digitally signed"*.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Unblock-File .\Migrate-ObsLegacyPlugins.ps1
```

`-Scope Process` only affects that window; closing it restores everything. One-line alternative:

```powershell
powershell -ExecutionPolicy Bypass -File .\Migrate-ObsLegacyPlugins.ps1
```

**4. Dry run first.** Nothing is moved; it just lists what it found.

```powershell
.\Migrate-ObsLegacyPlugins.ps1
```

**5. If the plan looks right, migrate.**

```powershell
.\Migrate-ObsLegacyPlugins.ps1 -Apply
```

**6. Verify.** Open OBS and check `Tools > Plugin Manager`: they should no longer be marked *Legacy*. If something goes wrong:

```powershell
.\Migrate-ObsLegacyPlugins.ps1 -Undo
```

### Parameters

| Parameter | Description |
|---|---|
| `-Apply` | Performs the migration. Without it, dry run only |
| `-Undo` | Reverts the last migration (or the one in `-ManifestPath`) |
| `-ObsPath <path>` | OBS install folder. Auto-detected by default |
| `-Portable` | Portable OBS: target is `<ObsPath>\plugins\<plugin>\` |
| `-OrphansTo <plugin>` | Assigns unowned dependency DLLs to that plugin |
| `-Force` | Overwrites files that already exist at the target |
| `-Detail` | Shows every file in the plan |
| `-Lang auto\|es\|en` | Message language (default `auto`) |
| `-ManifestPath <json>` | Specific manifest for `-Undo` |
| `-LogDir <path>` | Where manifests are saved (default `Desktop\obs-migracion`) |

### Examples

```powershell
# Plugin with many dependencies (e.g. obs-localvocal)
.\Migrate-ObsLegacyPlugins.ps1 -Apply -OrphansTo obs-localvocal

# Portable OBS
.\Migrate-ObsLegacyPlugins.ps1 -Apply -Portable -ObsPath "D:\OBS"

# Force Spanish messages and show details
.\Migrate-ObsLegacyPlugins.ps1 -Lang es -Detail
```

### Troubleshooting

| Problem | Fix |
|---|---|
| *"is not digitally signed"* | Step 3 above: `Set-ExecutionPolicy -Scope Process Bypass` and `Unblock-File` |
| *"Run PowerShell as Administrator"* | Right-click PowerShell and choose **Run as administrator** |
| *"Close OBS before migrating"* | Fully close OBS. Also close G HUB and the Stream Deck app |
| Says no legacy plugins were found | Expected if they are already migrated |
| A plugin is still marked *Legacy* | Install the author's newer version; moving files is not always enough |
| Odd read errors on OneDrive | Copy the script outside OneDrive, e.g. to `C:\Tools\` |
| DLLs with "no clear owner" | Use `-OrphansTo <plugin>` |

### Limitations

- **Shared dependencies**: the script cannot know for sure which plugin a dependency DLL belongs to (e.g. `ggml*`, `onnxruntime`, `whisper`). If only one main plugin remains it assigns them to it; with several, it lists them as "no clear owner" and does not move them.
- **Subfolders** next to the DLLs (e.g. `rocblas\library`) are reported but **not moved**; check them manually.
- **Third-party installers**: Logitech G HUB or the Stream Deck app may copy their plugin back to the old path when they update. If it shows as *Legacy* again, run the script again.
- Windows only. On macOS the plugin locations did not change.

> **Recommendation:** back up `C:\ProgramData\obs-studio\plugins` and `C:\Program Files\obs-studio\obs-plugins` before using `-Apply`. It is an extra safety net on top of `-Undo`.

---

## Licencia / License

Define aquí la licencia del proyecto (por ejemplo MIT) y añade el archivo `LICENSE`.  
Choose a license for the project (e.g. MIT) and add a `LICENSE` file.
