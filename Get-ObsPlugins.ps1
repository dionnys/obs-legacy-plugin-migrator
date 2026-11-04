<#
.SYNOPSIS
  EN: Lists the OBS Studio plugins installed on this PC, with version, location and status (OK / Legacy).
  ES: Lista los plugins de OBS Studio instalados en este PC, con versión, ubicación y estado (OK / Legado).

.PARAMETER ObsPath      EN: OBS install folder (auto-detected).       ES: Carpeta de instalación de OBS (se autodetecta).
.PARAMETER Portable     EN: Portable OBS (plugins\ and obs-plugins\). ES: OBS portable (plugins\ y obs-plugins\).
.PARAMETER IncludeOBS   EN: Also list OBS's own (first-party) plugins. ES: Incluye también los plugins propios de OBS.
.PARAMETER Export       EN: Save the list to .csv or .json.          ES: Guarda la lista en .csv o .json.
.PARAMETER Lang         EN: auto (default), es, en.                  ES: auto (por defecto), es, en.

.EXAMPLE
  .\Get-ObsPlugins.ps1
  .\Get-ObsPlugins.ps1 -IncludeOBS
  .\Get-ObsPlugins.ps1 -Export "$env:USERPROFILE\Desktop\obs-plugins.csv"
  .\Get-ObsPlugins.ps1 -Lang en
#>
[CmdletBinding()]
param(
    [string]$ObsPath,
    [switch]$Portable,
    [switch]$IncludeOBS,
    [string]$Export,
    [ValidateSet('auto', 'es', 'en')][string]$Lang = 'auto'
)

$ErrorActionPreference = 'Stop'

# ---------- Idioma / Language ----------
if ($Lang -eq 'auto') {
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { $script:L = 'es' } else { $script:L = 'en' }
} else { $script:L = $Lang }

$Msg = @{
    hdrObs   = @{ es = 'OBS:      {0}';                              en = 'OBS:      {0}' }
    hdrNew   = @{ es = 'Plugins:  {0}';                              en = 'Plugins:  {0}' }
    cPlugin  = @{ es = 'Plugin';                                     en = 'Plugin' }
    cVersion = @{ es = 'Versión';                                    en = 'Version' }
    cState   = @{ es = 'Estado';                                     en = 'Status' }
    cWhere   = @{ es = 'Ubicación';                                  en = 'Location' }
    cNote    = @{ es = 'Nota';                                       en = 'Note' }
    sOk      = @{ es = 'OK';                                         en = 'OK' }
    sLegacy  = @{ es = 'Legado';                                     en = 'Legacy' }
    sCore    = @{ es = 'OBS';                                        en = 'OBS' }
    dup      = @{ es = 'Duplicado (nueva + antigua)';                en = 'Duplicate (new + old)' }
    none     = @{ es = 'No se encontraron plugins de terceros.';     en = 'No third-party plugins found.' }
    summary  = @{ es = 'Total: {0}  |  OK: {1}  |  Legado: {2}';     en = 'Total: {0}  |  OK: {1}  |  Legacy: {2}' }
    hint     = @{ es = 'Hay plugins en Legado. Usa Migrate-ObsLegacyPlugins.ps1 para migrarlos.'
                  en = 'Some plugins are Legacy. Use Migrate-ObsLegacyPlugins.ps1 to migrate them.' }
    exported = @{ es = 'Exportado: {0}';                             en = 'Exported: {0}' }
}
function T([string]$Key, [object[]]$A) {
    $fmt = $Msg[$Key][$script:L]
    if ($A -and $A.Count -gt 0) { return [string]::Format($fmt, $A) }
    return $fmt
}

$firstParty = @(
    'aja','aja-output-ui','coreaudio-encoder','decklink','decklink-captions','decklink-output-ui',
    'frontend-tools','image-source','obs-browser','obs-ffmpeg','obs-filters','obs-libfdk','obs-nvenc',
    'obs-outputs','obs-qsv11','obs-text','obs-transitions','obs-vst','obs-webrtc','obs-websocket',
    'obs-x264','rtmp-services','text-freetype2','vlc-video','win-capture','win-dshow','win-ivcam',
    'win-wasapi'
)
$cefDeps = @('libcef','chrome_elf','libEGL','libGLESv2','vk_swiftshader','vulkan-1','d3dcompiler_47','dxcompiler','dxil')

# ---------- Helpers ----------
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

function Get-Ver([string]$Dll) {
    $vi = (Get-Item -LiteralPath $Dll).VersionInfo
    $v = $vi.ProductVersion
    if (-not $v) { $v = $vi.FileVersion }
    if ($v) { return ($v -replace ',\s*', '.').Trim() }
    return '-'
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

$Rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$Name, [string]$Dll, [string]$State, [string]$Where) {
    $Rows.Add([pscustomobject]@{ Name = $Name; Version = (Get-Ver $Dll); State = $State; Where = $Where; Path = $Dll; Note = '' })
}

# ---------- Scan ----------
$obs = Resolve-ObsPath
if ($Portable) { $newRoot = Join-Path $obs 'plugins' } else { $newRoot = Join-Path $env:ProgramData 'obs-studio\plugins' }
Write-Host (T 'hdrObs' $obs)
Write-Host ((T 'hdrNew' $newRoot) + "`n")

# New location + ProgramData legacy (bin\64bit)
if (Test-Path $newRoot) {
    foreach ($d in Get-ChildItem $newRoot -Directory) {
        $main = Join-Path $d.FullName "$($d.Name).dll"
        if (Test-Path $main) { Add-Row $d.Name $main 'ok' $newRoot }
        $bin = Join-Path $d.FullName 'bin\64bit'
        if (Test-Path $bin) {
            $dll = Join-Path $bin "$($d.Name).dll"
            if (-not (Test-Path $dll)) {
                $first = Get-ChildItem $bin -Filter *.dll -File | Select-Object -First 1
                if ($first) { $dll = $first.FullName } else { $dll = $null }
            }
            if ($dll) { Add-Row $d.Name $dll 'legacy' "$($d.FullName)\bin\64bit" }
        }
    }
}

# Old install: obs-plugins\64bit (+ data\obs-plugins\<plugin>)
$legacyBin  = Join-Path $obs 'obs-plugins\64bit'
$legacyData = Join-Path $obs 'data\obs-plugins'
if (Test-Path $legacyBin) {
    foreach ($f in Get-ChildItem $legacyBin -File -Filter *.dll) {
        if ($cefDeps -contains $f.BaseName) { continue }
        if ($firstParty -contains $f.BaseName) {
            if ($IncludeOBS) { Add-Row $f.BaseName $f.FullName 'core' $legacyBin }
            continue
        }
        $hasData = Test-Path (Join-Path $legacyData $f.BaseName)
        if ($hasData -or ($f.Length -lt 300MB -and (Test-ObsModule $f.FullName))) {
            Add-Row $f.BaseName $f.FullName 'legacy' $legacyBin
        }
    }
}

# OBS's own plugins in the new "core" folder (OBS 33+), if present
$coreDir = Join-Path $obs 'core'
if ($IncludeOBS -and (Test-Path $coreDir)) {
    foreach ($f in Get-ChildItem $coreDir -Recurse -File -Filter *.dll) {
        if ($f.Length -lt 50MB -and (Test-ObsModule $f.FullName)) { Add-Row $f.BaseName $f.FullName 'core' $f.DirectoryName }
    }
}

# Duplicates: same plugin in new + old location
foreach ($g in ($Rows | Where-Object { $_.State -ne 'core' } | Group-Object Name)) {
    if (@($g.Group | Select-Object -ExpandProperty State -Unique).Count -gt 1) {
        $g.Group | ForEach-Object { $_.Note = (T 'dup') }
    }
}

# ---------- Report ----------
if ($Rows.Count -eq 0) { Write-Host (T 'none') -ForegroundColor Yellow; return }

$label = @{ ok = (T 'sOk'); legacy = (T 'sLegacy'); core = (T 'sCore') }
$fmt   = '{0,-34} {1,-16} {2,-8} {3}'
Write-Host ($fmt -f (T 'cPlugin'), (T 'cVersion'), (T 'cState'), (T 'cWhere')) -ForegroundColor Cyan
Write-Host ($fmt -f ('-' * 6), ('-' * 7), ('-' * 6), ('-' * 9)) -ForegroundColor Cyan

foreach ($r in ($Rows | Sort-Object Name, State)) {
    $line = $fmt -f $r.Name, $r.Version, $label[$r.State], $r.Where
    if ($r.Note) { $line += "  <- $($r.Note)" }
    switch ($r.State) {
        'legacy' { Write-Host $line -ForegroundColor Yellow }
        'core'   { Write-Host $line -ForegroundColor DarkGray }
        default  { Write-Host $line -ForegroundColor Green }
    }
}

$third  = @($Rows | Where-Object { $_.State -ne 'core' })
$okN    = @($third | Where-Object { $_.State -eq 'ok' }).Count
$legN   = @($third | Where-Object { $_.State -eq 'legacy' }).Count
Write-Host ("`n" + (T 'summary' $third.Count, $okN, $legN))
if ($legN -gt 0) { Write-Host (T 'hint') -ForegroundColor Yellow }

# ---------- Export ----------
if ($Export) {
    $out = $Rows | Sort-Object Name, State | ForEach-Object {
        $o = [ordered]@{}
        $o[(T 'cPlugin')]  = $_.Name
        $o[(T 'cVersion')] = $_.Version
        $o[(T 'cState')]   = $label[$_.State]
        $o[(T 'cWhere')]   = $_.Where
        $o['Path']         = $_.Path
        $o[(T 'cNote')]    = $_.Note
        [pscustomobject]$o
    }
    if ($Export -like '*.json') { $out | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Export -Encoding UTF8 }
    else                        { $out | Export-Csv -LiteralPath $Export -NoTypeInformation -Encoding UTF8 }
    Write-Host (T 'exported' $Export) -ForegroundColor Green
}
