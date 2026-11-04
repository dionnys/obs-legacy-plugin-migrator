<#
.SYNOPSIS
  Detecta plugins "Legacy" de OBS Studio 33+ (Windows) y los migra a la estructura nueva.

.DESCRIPTION
  Estructura nueva:  C:\ProgramData\obs-studio\plugins\<plugin>\<plugin>.dll  +  ...\<plugin>\data\*

  Detecta dos casos:
    A) ProgramData con bin\64bit   -> sube el contenido de bin\64bit a la carpeta del plugin.
    B) Program Files (obs-plugins\64bit + data\obs-plugins\<plugin>) -> mueve a ProgramData.

  Por defecto SOLO SIMULA y lista lo que haria. Usa -Apply para mover de verdad.
  Cada ejecucion con -Apply guarda un manifiesto JSON; -Undo revierte la ultima migracion.

.PARAMETER Apply       Ejecuta la migracion (sin esto, solo lista).
.PARAMETER Undo        Revierte la ultima migracion usando su manifiesto.
.PARAMETER ObsPath     Carpeta de instalacion de OBS (por defecto se autodetecta).
.PARAMETER Portable    OBS portable: nuevo destino = <ObsPath>\plugins\<plugin>\
.PARAMETER OrphansTo   Plugin al que asignar DLLs de dependencias sin duenio claro (ej. obs-localvocal).
.PARAMETER Force       Sobrescribe archivos que ya existan en el destino.
.PARAMETER Detail      Muestra cada archivo del plan, no solo el resumen.

.EXAMPLE
  .\Migrate-ObsLegacyPlugins.ps1                              # simulacion
  .\Migrate-ObsLegacyPlugins.ps1 -Apply                       # migrar (PowerShell como admin, OBS cerrado)
  .\Migrate-ObsLegacyPlugins.ps1 -Apply -OrphansTo obs-localvocal
  .\Migrate-ObsLegacyPlugins.ps1 -Undo
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
    [string]$ManifestPath,
    [string]$LogDir = (Join-Path $env:USERPROFILE 'Desktop\obs-migracion')
)

$ErrorActionPreference = 'Stop'

# ---------- Listas de exclusion (plugins propios de OBS y dependencias de CEF) ----------
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

# ---------- Estado ----------
$Ops     = New-Object System.Collections.Generic.List[object]
$Warns   = New-Object System.Collections.Generic.List[string]
$Cleanup = New-Object System.Collections.Generic.List[string]

# ---------- Utilidades ----------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-IfEmpty([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and -not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Path -Force
    }
}

# Un plugin de OBS exporta obs_module_load: se busca esa cadena en el binario (por bloques).
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
    if (-not (Test-Admin) -and -not $Portable) { throw 'Ejecuta PowerShell como administrador.' }
    if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw 'Cierra OBS antes de revertir.' }

    $mf = $ManifestPath
    if (-not $mf) {
        $last = Get-ChildItem $LogDir -Filter 'migracion-*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $last) { throw "No hay manifiestos en $LogDir" }
        $mf = $last.FullName
    }
    Write-Host "Revirtiendo: $mf" -ForegroundColor Cyan
    $m = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
    $items = @($m.Items)
    [array]::Reverse($items)
    foreach ($i in $items) {
        if (Test-Path -LiteralPath $i.To) {
            New-Item -ItemType Directory -Force (Split-Path $i.From -Parent) | Out-Null
            Move-Item -LiteralPath $i.To -Destination $i.From -Force
            Write-Host "  <- $($i.From)"
        }
        # limpiar carpetas vacias creadas en el destino nuevo
        $p = Split-Path $i.To -Parent
        while ($p -and ($p.Length -gt $m.NewRoot.Length) -and $p.StartsWith($m.NewRoot)) {
            Remove-IfEmpty $p
            $p = Split-Path $p -Parent
        }
    }
    Write-Host 'Reversion completa.' -ForegroundColor Green
    return
}

# ---------- PLAN ----------
$obs = Resolve-ObsPath
if ($Portable) { $new = Join-Path $obs 'plugins' } else { $new = Join-Path $env:ProgramData 'obs-studio\plugins' }
Write-Host "OBS:            $obs"
Write-Host "Destino nuevo:  $new`n"

# A) ProgramData con bin\64bit (solo instalacion normal)
$pdRoot = Join-Path $env:ProgramData 'obs-studio\plugins'
if (-not $Portable -and (Test-Path $pdRoot)) {
    foreach ($d in Get-ChildItem $pdRoot -Directory) {
        $bin = Join-Path $d.FullName 'bin\64bit'
        if (-not (Test-Path $bin)) { continue }
        foreach ($f in Get-ChildItem $bin -Force) {
            Add-Op $d.Name 'ProgramData' $f.FullName (Join-Path $d.FullName $f.Name)
        }
        if (-not (Test-Path (Join-Path $bin "$($d.Name).dll"))) {
            $Warns.Add("$($d.Name): no hay $($d.Name).dll en bin\64bit; OBS espera que la DLL se llame igual que la carpeta.")
        }
        $Cleanup.Add($bin)
        $Cleanup.Add((Join-Path $d.FullName 'bin'))
    }
}

# B) Instalacion antigua: obs-plugins\64bit + data\obs-plugins\<plugin>
$legacyBin  = Join-Path $obs 'obs-plugins\64bit'
$legacyData = Join-Path $obs 'data\obs-plugins'

if (Test-Path $legacyBin) {
    $files = @(Get-ChildItem $legacyBin -File | Where-Object { $_.Extension -in '.dll', '.pdb' })

    # Plugins "principales": exportan obs_module_load o tienen carpeta de datos con su nombre
    $mains = @()
    foreach ($f in ($files | Where-Object { $_.Extension -eq '.dll' })) {
        if (($firstParty -contains $f.BaseName) -or ($cefDeps -contains $f.BaseName)) { continue }
        $hasData = Test-Path (Join-Path $legacyData $f.BaseName)
        if ($hasData -or ($f.Length -lt 300MB -and (Test-ObsModule $f.FullName))) { $mains += $f.BaseName }
    }

    if ($OrphansTo -and ($mains -notcontains $OrphansTo)) {
        $Warns.Add("-OrphansTo '$OrphansTo' no coincide con ningun plugin detectado ($($mains -join ', ')).")
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
    if ($orphans.Count) {
        $Warns.Add("DLL/PDB sin duenio claro (no se mueven; usa -OrphansTo <plugin>): $($orphans -join ', ')")
    }

    # Subcarpetas junto a las DLL (p.ej. rocblas\library): se reportan, no se mueven
    $subs = @(Get-ChildItem $legacyBin -Directory | Where-Object { $cefDirs -notcontains $_.Name })
    if ($subs.Count) {
        $Warns.Add("Subcarpetas en obs-plugins\64bit NO movidas (revisar a mano): $(($subs | ForEach-Object Name) -join ', ')")
    }

    # Carpetas de datos
    if (Test-Path $legacyData) {
        foreach ($d in Get-ChildItem $legacyData -Directory) {
            if ($firstParty -contains $d.Name) { continue }
            if ($mains -contains $d.Name) {
                foreach ($c in Get-ChildItem $d.FullName -Force) {
                    Add-Op $d.Name 'ProgramFiles-data' $c.FullName (Join-Path $new "$($d.Name)\data\$($c.Name)")
                }
                $Cleanup.Add($d.FullName)
            } else {
                $Warns.Add("Datos sin DLL principal: data\obs-plugins\$($d.Name) (no se mueve).")
            }
        }
    }
}

# Conflictos: si el destino ya existe, se omite (salvo -Force en archivos)
foreach ($op in $Ops) {
    if (Test-Path -LiteralPath $op.To) {
        $isDir = (Get-Item -LiteralPath $op.From -Force).PSIsContainer
        if ($isDir -or -not $Force) { $op.Skip = 'ya existe en destino' }
    }
}

# ---------- REPORTE ----------
if ($Ops.Count -eq 0) {
    Write-Host 'No se detectaron plugins legacy. Nada que migrar.' -ForegroundColor Green
    $Warns | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    return
}

Write-Host 'Plugins legacy detectados:' -ForegroundColor Cyan
foreach ($g in ($Ops | Group-Object Plugin)) {
    $skipped = @($g.Group | Where-Object Skip).Count
    $kinds   = ($g.Group | Select-Object -ExpandProperty Kind -Unique) -join '+'
    $line    = '  {0,-32} {1,3} elementos  [{2}]' -f $g.Name, $g.Count, $kinds
    if ($skipped) { $line += "  ($skipped omitidos: ya existen)" }
    Write-Host $line
    if ($Detail) {
        foreach ($op in $g.Group) {
            $tag = ''; if ($op.Skip) { $tag = "  [OMITIDO: $($op.Skip)]" }
            Write-Host "      $($op.From)`n        -> $($op.To)$tag" -ForegroundColor DarkGray
        }
    }
}
if ($Warns.Count) {
    Write-Host "`nAvisos:" -ForegroundColor Yellow
    $Warns | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
}

if (-not $Apply) {
    Write-Host "`nSIMULACION: no se movio nada. Ejecuta con -Apply (admin, OBS cerrado) para migrar." -ForegroundColor Magenta
    return
}

# ---------- APLICAR ----------
if (-not (Test-Admin) -and -not $Portable) { throw 'Ejecuta PowerShell como administrador.' }
if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw 'Cierra OBS antes de migrar.' }
foreach ($p in 'LGHUB', 'lghub_agent', 'StreamDeck') {
    if (Get-Process $p -ErrorAction SilentlyContinue) {
        Write-Host "Aviso: $p esta en ejecucion; podria recopiar su plugin a la ruta vieja." -ForegroundColor Yellow
    }
}

$done = New-Object System.Collections.Generic.List[object]
foreach ($op in ($Ops | Where-Object { -not $_.Skip })) {
    try {
        New-Item -ItemType Directory -Force (Split-Path $op.To -Parent) | Out-Null
        Move-Item -LiteralPath $op.From -Destination $op.To -Force:$Force
        $done.Add([pscustomobject]@{ From = $op.From; To = $op.To })
    } catch {
        Write-Host "  ERROR moviendo $($op.From): $($_.Exception.Message)" -ForegroundColor Red
    }
}

foreach ($c in $Cleanup) { Remove-IfEmpty $c }

New-Item -ItemType Directory -Force $LogDir | Out-Null
$mfPath = Join-Path $LogDir ("migracion-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[pscustomobject]@{ Date = (Get-Date).ToString('s'); NewRoot = $new; Items = $done.ToArray() } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $mfPath -Encoding UTF8

Write-Host "`nMigrados: $($done.Count) elementos." -ForegroundColor Green
Write-Host "Manifiesto: $mfPath  (revertir con -Undo)"
Write-Host 'Abre OBS > Herramientas > Gestor de plugins y verifica que ya no aparezcan como Legado.'
Write-Host 'Nota: G HUB / Stream Deck pueden volver a instalar su plugin en la ruta vieja al actualizarse; repite el script.'
