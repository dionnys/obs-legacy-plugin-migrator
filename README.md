# obs-legacy-plugin-migrator

Script de PowerShell que **detecta los plugins "Legado" (Legacy) de OBS Studio 33+ en Windows y los migra** a la nueva estructura de carpetas.

*English summary below.*

## Contexto

Desde OBS Studio 33, los plugins de terceros deben instalarse en:

```
C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll
C:\ProgramData\obs-studio\plugins\<plugin>\data\*
```

Los plugins en las ubicaciones antiguas siguen cargando, pero OBS los marca como **Legado** en `Herramientas > Gestor de plugins`, y las rutas de Program Files dejarán de cargarse en OBS 34.0. Referencia oficial: [Legacy Plugin Locations](https://obsproject.com/kb/legacy-plugin-locations).

## Qué hace

| Caso | Origen (legacy) | Acción |
|---|---|---|
| A | `ProgramData\obs-studio\plugins\<plugin>\bin\64bit\` | Sube el contenido a la carpeta del plugin, junto a `data` |
| B | `Program Files\obs-studio\obs-plugins\64bit\` + `data\obs-plugins\<plugin>\` | Mueve DLL, `.pdb` y datos a `ProgramData\...\plugins\<plugin>\` |

Cómo lo hace:

- **Simulación por defecto**: sin `-Apply` solo lista lo que haría.
- **Detección de plugins reales**: busca el export `obs_module_load` en cada DLL (o una carpeta de datos con su nombre).
- **Exclusiones**: no toca plugins propios de OBS ni las DLL de CEF.
- **Sin sobrescribir**: si el destino ya existe, omite el archivo (salvo `-Force`).
- **Reversible**: cada migración guarda un manifiesto JSON y `-Undo` la revierte.
- **Seguro**: se niega a ejecutar si OBS está abierto.

## Requisitos

- Windows con PowerShell 5.1 o superior
- OBS Studio 33 o superior
- PowerShell **como administrador** para migrar (salvo OBS portable)
- OBS **cerrado**

## Uso

```powershell
# 1. Simulación: lista los plugins legacy detectados
.\Migrate-ObsLegacyPlugins.ps1

# 2. Simulación con el detalle de cada archivo
.\Migrate-ObsLegacyPlugins.ps1 -Detail

# 3. Migrar
.\Migrate-ObsLegacyPlugins.ps1 -Apply

# 4. Revertir la última migración
.\Migrate-ObsLegacyPlugins.ps1 -Undo
```

Si Windows bloquea la ejecución: `Set-ExecutionPolicy -Scope Process Bypass`.

Después de migrar, abre OBS y revisa `Herramientas > Gestor de plugins`: ya no deberían aparecer como *Legado*.

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
| `-ManifestPath <json>` | Manifiesto concreto para `-Undo` |
| `-LogDir <ruta>` | Dónde guardar los manifiestos (por defecto `Desktop\obs-migracion`) |

### Ejemplos

```powershell
# Plugin con muchas dependencias (p. ej. obs-localvocal)
.\Migrate-ObsLegacyPlugins.ps1 -Apply -OrphansTo obs-localvocal

# OBS portable
.\Migrate-ObsLegacyPlugins.ps1 -Apply -Portable -ObsPath "D:\OBS"
```

## Limitaciones

- **Dependencias compartidas**: el script no puede saber con certeza de qué plugin es cada DLL de dependencia (por ejemplo `ggml*`, `onnxruntime`, `whisper`). Si queda un solo plugin principal en la carpeta, se las asigna; si hay varios, las lista como "sin dueño claro" y no las mueve. Usa `-OrphansTo`.
- **Subcarpetas** junto a las DLL (por ejemplo `rocblas\library`): se reportan pero **no se mueven**; revísalas a mano.
- **Instaladores de terceros**: software como Logitech G HUB o la app de Stream Deck puede volver a copiar su plugin a la ruta vieja al actualizarse. Si vuelve a salir como *Legado*, ejecuta el script otra vez.
- **Mover no siempre basta**: algunos plugins pueden seguir marcados como Legado aunque se muevan sus archivos. La solución definitiva es instalar una versión nueva del autor.
- Solo Windows. En macOS las ubicaciones de plugins no cambian.

## Recomendación

Haz una copia de `C:\ProgramData\obs-studio\plugins` y de `C:\Program Files\obs-studio\obs-plugins` antes de usar `-Apply`. Además del manifiesto de `-Undo`, es una red de seguridad extra.

---

## English summary

PowerShell script that detects **Legacy plugins in OBS Studio 33+ (Windows)** and migrates them to the new layout `C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll` + `\data\*`.

- Dry-run by default; pass `-Apply` to move files (run as Administrator, with OBS closed).
- Handles both legacy layouts: `ProgramData\...\bin\64bit` and `Program Files\obs-studio\obs-plugins\64bit` + `data\obs-plugins\<plugin>`.
- Identifies real plugins by scanning DLLs for the `obs_module_load` export; skips OBS first-party modules and CEF files.
- Never overwrites unless `-Force`; writes a JSON manifest so `-Undo` can revert the last run.
- Supports portable OBS (`-Portable -ObsPath <dir>`).
- Shared dependency DLLs of multi-DLL plugins (e.g. `obs-localvocal`) may need `-OrphansTo <plugin>`.

```powershell
.\Migrate-ObsLegacyPlugins.ps1            # dry run
.\Migrate-ObsLegacyPlugins.ps1 -Apply     # migrate
.\Migrate-ObsLegacyPlugins.ps1 -Undo      # revert last migration
```

## Licencia / License

Define aquí la licencia del proyecto (por ejemplo MIT).
