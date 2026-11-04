<#
.SYNOPSIS
  EN: Detects "Legacy" OBS Studio 33+ plugins (Windows) and migrates them to the new folder layout.
  ES: Detecta plugins "Legado" de OBS Studio 33+ (Windows) y los migra a la estructura nueva.

.DESCRIPTION
  New layout / Estructura nueva:
    C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll  +  ...\<plugin>\data\*

  EN: Handles two legacy cases:
      A) ProgramData with bin\64bit  -> moves the content of bin\64bit up into the plugin folder.
      B) Program Files (obs-plugins\64bit + data\obs-plugins\<plugin>) -> moves it to ProgramData.
      Dry run by default: it only LISTS what it would do. Use -Apply to actually move files.
      Every -Apply run saves a JSON manifest; -Undo reverts the last migration.

  ES: Detecta dos casos legacy:
      A) ProgramData con bin\64bit   -> sube el contenido de bin\64bit a la carpeta del plugin.
      B) Program Files (obs-plugins\64bit + data\obs-plugins\<plugin>) -> lo mueve a ProgramData.
      Por defecto SOLO SIMULA y lista lo que haría. Usa -Apply para mover de verdad.
      Cada ejecución con -Apply guarda un manifiesto JSON; -Undo revierte la última migración.

.PARAMETER Apply      EN: Perform the migration (without it, dry run).      ES: Ejecuta la migración (sin esto, solo simula).
.PARAMETER Undo       EN: Revert the last migration.                        ES: Revierte la última migración.
.PARAMETER ObsPath    EN: OBS install folder (auto-detected by default).    ES: Carpeta de instalación de OBS (se autodetecta).
.PARAMETER Portable   EN: Portable OBS: target = <ObsPath>\plugins\<plugin>\  ES: OBS portable: destino = <ObsPath>\plugins\<plugin>\
.PARAMETER OrphansTo  EN: Plugin that owns unassigned dependency DLLs (e.g. obs-localvocal).  ES: Plugin dueño de DLL de dependencias sin asignar.
.PARAMETER Force      EN: Overwrite files that already exist at the target. ES: Sobrescribe archivos que ya existan en el destino.
.PARAMETER Detail     EN: Show every file in the plan.                      ES: Muestra cada archivo del plan.
.PARAMETER Lang       EN: Output language: auto (default), es, en.          ES: Idioma de salida: auto (por defecto), es, en.

.EXAMPLE
  .\Migrate-ObsLegacyPlugins.ps1                              # dry run / simulación
  .\Migrate-ObsLegacyPlugins.ps1 -Apply                       # migrate / migrar (admin, OBS closed)
  .\Migrate-ObsLegacyPlugins.ps1 -Apply -OrphansTo obs-localvocal
  .\Migrate-ObsLegacyPlugins.ps1 -Undo
  .\Migrate-ObsLegacyPlugins.ps1 -Lang en
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Undo,
    [string]$ObsPath,
    [switch]$Portable,
    [string]$OrphansTo,
    [switch]$Force,
    [switch]$Detail,
    [ValidateSet('auto', 'es', 'en')][string]$Lang = 'auto',
    [string]$ManifestPath,
    [string]$LogDir = (Join-Path $env:USERPROFILE 'Desktop\obs-migracion')
)

$ErrorActionPreference = 'Stop'

# ---------- Idioma / Language ----------
if ($Lang -eq 'auto') {
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { $script:L = 'es' } else { $script:L = 'en' }
} else {
    $script:L = $Lang
}

$Msg = @{
    needAdmin   = @{ es = 'Ejecuta PowerShell como administrador.'
                     en = 'Run PowerShell as Administrator.' }
    obsRunUndo  = @{ es = 'Cierra OBS antes de revertir.'
                     en = 'Close OBS before reverting.' }
    obsRunApply = @{ es = 'Cierra OBS antes de migrar.'
                     en = 'Close OBS before migrating.' }
    noManifests = @{ es = 'No hay manifiestos en {0}'
                     en = 'No manifests found in {0}' }
    reverting   = @{ es = 'Revirtiendo: {0}'
                     en = 'Reverting: {0}' }
    revertDone  = @{ es = 'Reversión completa.'
                     en = 'Revert complete.' }
    hdrObs      = @{ es = 'OBS:            {0}'
                     en = 'OBS:            {0}' }
    hdrNew      = @{ es = 'Destino nuevo:  {0}'
                     en = 'New target:     {0}' }
    warnNoMain  = @{ es = '{0}: no hay {0}.dll en bin\64bit; OBS espera que la DLL se llame igual que la carpeta.'
                     en = '{0}: {0}.dll not found in bin\64bit; OBS expects the DLL to be named like its folder.' }
    warnOrphTo  = @{ es = "-OrphansTo '{0}' no coincide con ningún plugin detectado ({1})."
                     en = "-OrphansTo '{0}' does not match any detected plugin ({1})." }
    warnOrph    = @{ es = 'DLL/PDB sin dueño claro (no se mueven; usa -OrphansTo <plugin>): {0}'
                     en = 'DLL/PDB with no clear owner (not moved; use -OrphansTo <plugin>): {0}' }
    warnSubdirs = @{ es = 'Subcarpetas en obs-plugins\64bit NO movidas (revisar a mano): {0}'
                     en = 'Subfolders in obs-plugins\64bit NOT moved (check manually): {0}' }
    warnData    = @{ es = 'Datos sin DLL principal: data\obs-plugins\{0} (no se mueve).'
                     en = 'Data folder without a main DLL: data\obs-plugins\{0} (not moved).' }
    skipExists  = @{ es = 'ya existe en destino'
                     en = 'already exists at target' }
    nothing     = @{ es = 'No se detectaron plugins legacy. Nada que migrar.'
                     en = 'No legacy plugins detected. Nothing to migrate.' }
    found       = @{ es = 'Plugins legacy detectados:'
                     en = 'Legacy plugins detected:' }
    items       = @{ es = 'elementos'
                     en = 'items' }
    skipCount   = @{ es = '({0} omitidos: ya existen)'
                     en = '({0} skipped: already exist)' }
    skippedTag  = @{ es = '[OMITIDO: {0}]'
                     en = '[SKIPPED: {0}]' }
    warnHdr     = @{ es = 'Avisos:'
                     en = 'Warnings:' }
    dryRun      = @{ es = 'SIMULACIÓN: no se movió nada. Ejecuta con -Apply (admin, OBS cerrado) para migrar.'
                     en = 'DRY RUN: nothing was moved. Run with -Apply (admin, OBS closed) to migrate.' }
    procRun     = @{ es = 'Aviso: {0} está en ejecución; podría recopiar su plugin a la ruta vieja.'
                     en = 'Note: {0} is running; it may copy its plugin back to the old path.' }
    moveErr     = @{ es = '  ERROR moviendo {0}: {1}'
                     en = '  ERROR moving {0}: {1}' }
    migrated    = @{ es = 'Migrados: {0} elementos.'
                     en = 'Migrated: {0} items.' }
    manifest    = @{ es = 'Manifiesto: {0}  (revertir con -Undo)'
                     en = 'Manifest: {0}  (revert with -Undo)' }
    verify      = @{ es = 'Abre OBS > Herramientas > Gestor de plugins y verifica que ya no aparezcan como Legado.'
                     en = 'Open OBS > Tools > Plugin Manager and check they are no longer marked Legacy.' }
    note        = @{ es = 'Nota: G HUB / Stream Deck pueden volver a instalar su plugin en la ruta vieja al actualizarse; repite el script.'
                     en = 'Note: G HUB / Stream Deck may reinstall their plugin to the old path when they update; run the script again.' }
}

function T([string]$Key, [object[]]$A) {
    $fmt = $Msg[$Key][$script:L]
    if ($A -and $A.Count -gt 0) { return [string]::Format($fmt, $A) }
    return $fmt
}

# ---------- Listas de exclusión / Exclusion lists (OBS first-party + CEF) ----------
$firstParty = @(
    'aja','aja-output-ui','coreaudio-encoder','decklink','decklink-captions','decklink-output-ui',
    'frontend-tools','image-source','obs-browser','obs-ffmpeg','obs-filters','obs-libfdk','obs-nvenc',
    'obs-outputs','obs-qsv11','obs-text','obs-transitions','obs-vst','obs-webrtc','obs-websocket',
    'obs-x264','rtmp-services','text-freetype2','vlc-video','win-capture','win-dshow','win-ivcam',
    'win-wasapi'
)
$cefDeps = @(
    'libcef','chrome_elf','libEGL','libGLESv2','vk_swiftshader','vulkan-1','d3dcompiler_47',
    'dxcompiler','dxil'
)
$cefDirs = @('locales','swiftshader')

# ---------- Estado / State ----------
$Ops     = New-Object System.Collections.Generic.List[object]
$Warns   = New-Object System.Collections.Generic.List[string]
$Cleanup = New-Object System.Collections.Generic.List[string]

# ---------- Utilidades / Helpers ----------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-IfEmpty([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and -not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Path -Force
    }
}

# A plugin exports obs_module_load: search that string in the binary (chunked).
function Test-ObsModule([string]$Path) {
    $needle = 'obs_module_load'
    $enc = [Text.Encoding]::GetEncoding(28591)
    $fs = [IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] (4MB)
        $carry = ''
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            $s = $carry + $enc.GetString($buf, 0, $n)
            if ($s.Contains($needle)) { return $true }
            $carry = $s.Substring([Math]::Max(0, $s.Length - $needle.Length))
        }
        return $false
    } finally { $fs.Dispose() }
}

function Add-Op([string]$Plugin, [string]$Kind, [string]$From, [string]$To) {
    $Ops.Add([pscustomobject]@{ Plugin = $Plugin; Kind = $Kind; From = $From; To = $To; Skip = $null })
}

function Resolve-ObsPath {
    if ($ObsPath) { return $ObsPath }
    foreach ($k in 'HKLM:\SOFTWARE\OBS Studio', 'HKLM:\SOFTWARE\WOW6432Node\OBS Studio') {
        try {
            $v = (Get-Item $k -ErrorAction Stop).GetValue('')
            if ($v -and (Test-Path $v)) { return $v }
        } catch { }
    }
    return (Join-Path $env:ProgramFiles 'obs-studio')
}

# ---------- UNDO ----------
if ($Undo) {
    if (-not (Test-Admin) -and -not $Portable) { throw (T 'needAdmin') }
    if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw (T 'obsRunUndo') }

    $mf = $ManifestPath
    if (-not $mf) {
        $last = Get-ChildItem $LogDir -Filter 'migracion-*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $last) { throw (T 'noManifests' $LogDir) }
        $mf = $last.FullName
    }
    Write-Host (T 'reverting' $mf) -ForegroundColor Cyan
    $m = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
    $items = @($m.Items)
    [array]::Reverse($items)
    foreach ($i in $items) {
        if (Test-Path -LiteralPath $i.To) {
            New-Item -ItemType Directory -Force (Split-Path $i.From -Parent) | Out-Null
            Move-Item -LiteralPath $i.To -Destination $i.From -Force
            Write-Host "  <- $($i.From)"
        }
        # remove empty folders left at the new location
        $p = Split-Path $i.To -Parent
        while ($p -and ($p.Length -gt $m.NewRoot.Length) -and $p.StartsWith($m.NewRoot)) {
            Remove-IfEmpty $p
            $p = Split-Path $p -Parent
        }
    }
    Write-Host (T 'revertDone') -ForegroundColor Green
    return
}

# ---------- PLAN ----------
$obs = Resolve-ObsPath
if ($Portable) { $new = Join-Path $obs 'plugins' } else { $new = Join-Path $env:ProgramData 'obs-studio\plugins' }
Write-Host (T 'hdrObs' $obs)
Write-Host ((T 'hdrNew' $new) + "`n")

# A) ProgramData with bin\64bit (regular install only)
$pdRoot = Join-Path $env:ProgramData 'obs-studio\plugins'
if (-not $Portable -and (Test-Path $pdRoot)) {
    foreach ($d in Get-ChildItem $pdRoot -Directory) {
        $bin = Join-Path $d.FullName 'bin\64bit'
        if (-not (Test-Path $bin)) { continue }
        foreach ($f in Get-ChildItem $bin -Force) {
            Add-Op $d.Name 'ProgramData' $f.FullName (Join-Path $d.FullName $f.Name)
        }
        if (-not (Test-Path (Join-Path $bin "$($d.Name).dll"))) {
            $Warns.Add((T 'warnNoMain' $d.Name))
        }
        $Cleanup.Add($bin)
        $Cleanup.Add((Join-Path $d.FullName 'bin'))
    }
}

# B) Old install: obs-plugins\64bit + data\obs-plugins\<plugin>
$legacyBin  = Join-Path $obs 'obs-plugins\64bit'
$legacyData = Join-Path $obs 'data\obs-plugins'

if (Test-Path $legacyBin) {
    $files = @(Get-ChildItem $legacyBin -File | Where-Object { $_.Extension -in '.dll', '.pdb' })

    # "Main" plugins: export obs_module_load or have a data folder with their name
    $mains = @()
    foreach ($f in ($files | Where-Object { $_.Extension -eq '.dll' })) {
        if (($firstParty -contains $f.BaseName) -or ($cefDeps -contains $f.BaseName)) { continue }
        $hasData = Test-Path (Join-Path $legacyData $f.BaseName)
        if ($hasData -or ($f.Length -lt 300MB -and (Test-ObsModule $f.FullName))) { $mains += $f.BaseName }
    }

    if ($OrphansTo -and ($mains -notcontains $OrphansTo)) {
        $Warns.Add((T 'warnOrphTo' $OrphansTo, ($mains -join ', ')))
    }

    $orphans = @()
    foreach ($f in $files) {
        $plugin = $null
        if ($mains -contains $f.BaseName)                                  { $plugin = $f.BaseName }
        elseif (($firstParty -contains $f.BaseName) -or ($cefDeps -contains $f.BaseName)) { continue }
        elseif ($OrphansTo -and ($mains -contains $OrphansTo))             { $plugin = $OrphansTo }
        elseif ($mains.Count -eq 1)                                        { $plugin = $mains[0] }

        if ($plugin) { Add-Op $plugin 'ProgramFiles' $f.FullName (Join-Path $new "$plugin\$($f.Name)") }
        else         { $orphans += $f.Name }
    }
    if ($orphans.Count) { $Warns.Add((T 'warnOrph' ($orphans -join ', '))) }

    # Subfolders next to the DLLs (e.g. rocblas\library): reported, not moved
    $subs = @(Get-ChildItem $legacyBin -Directory | Where-Object { $cefDirs -notcontains $_.Name })
    if ($subs.Count) {
        $Warns.Add((T 'warnSubdirs' (($subs | ForEach-Object { $_.Name }) -join ', ')))
    }

    # Data folders
    if (Test-Path $legacyData) {
        foreach ($d in Get-ChildItem $legacyData -Directory) {
            if ($firstParty -contains $d.Name) { continue }
            if ($mains -contains $d.Name) {
                foreach ($c in Get-ChildItem $d.FullName -Force) {
                    Add-Op $d.Name 'ProgramFiles-data' $c.FullName (Join-Path $new "$($d.Name)\data\$($c.Name)")
                }
                $Cleanup.Add($d.FullName)
            } else {
                $Warns.Add((T 'warnData' $d.Name))
            }
        }
    }
}

# Conflicts: if the target exists it is skipped (except files with -Force)
foreach ($op in $Ops) {
    if (Test-Path -LiteralPath $op.To) {
        $isDir = (Get-Item -LiteralPath $op.From -Force).PSIsContainer
        if ($isDir -or -not $Force) { $op.Skip = (T 'skipExists') }
    }
}

# ---------- REPORT ----------
if ($Ops.Count -eq 0) {
    Write-Host (T 'nothing') -ForegroundColor Green
    $Warns | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    return
}

Write-Host (T 'found') -ForegroundColor Cyan
foreach ($g in ($Ops | Group-Object Plugin)) {
    $skipped = @($g.Group | Where-Object { $_.Skip }).Count
    $kinds   = ($g.Group | Select-Object -ExpandProperty Kind -Unique) -join '+'
    $line    = '  {0,-32} {1,3} {2}  [{3}]' -f $g.Name, $g.Count, (T 'items'), $kinds
    if ($skipped) { $line += '  ' + (T 'skipCount' $skipped) }
    Write-Host $line
    if ($Detail) {
        foreach ($op in $g.Group) {
            $tag = ''
            if ($op.Skip) { $tag = '  ' + (T 'skippedTag' $op.Skip) }
            Write-Host "      $($op.From)`n        -> $($op.To)$tag" -ForegroundColor DarkGray
        }
    }
}
if ($Warns.Count) {
    Write-Host ("`n" + (T 'warnHdr')) -ForegroundColor Yellow
    $Warns | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
}

if (-not $Apply) {
    Write-Host ("`n" + (T 'dryRun')) -ForegroundColor Magenta
    return
}

# ---------- APPLY ----------
if (-not (Test-Admin) -and -not $Portable) { throw (T 'needAdmin') }
if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw (T 'obsRunApply') }
foreach ($p in 'LGHUB', 'lghub_agent', 'StreamDeck') {
    if (Get-Process $p -ErrorAction SilentlyContinue) {
        Write-Host (T 'procRun' $p) -ForegroundColor Yellow
    }
}

$done = New-Object System.Collections.Generic.List[object]
foreach ($op in ($Ops | Where-Object { -not $_.Skip })) {
    try {
        New-Item -ItemType Directory -Force (Split-Path $op.To -Parent) | Out-Null
        Move-Item -LiteralPath $op.From -Destination $op.To -Force:$Force
        $done.Add([pscustomobject]@{ From = $op.From; To = $op.To })
    } catch {
        Write-Host (T 'moveErr' $op.From, $_.Exception.Message) -ForegroundColor Red
    }
}

foreach ($c in $Cleanup) { Remove-IfEmpty $c }

New-Item -ItemType Directory -Force $LogDir | Out-Null
$mfPath = Join-Path $LogDir ("migracion-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[pscustomobject]@{ Date = (Get-Date).ToString('s'); NewRoot = $new; Items = $done.ToArray() } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $mfPath -Encoding UTF8

Write-Host ("`n" + (T 'migrated' $done.Count)) -ForegroundColor Green
Write-Host (T 'manifest' $mfPath)
Write-Host (T 'verify')
Write-Host (T 'note')
