# Starts the title with the settings this fork is played with (README.md, "How to run it").
#   scripts\play.ps1 -Exe <path of your own copy's executable>
# -Safe         without the newer, faster ways (the first thing to try when something is wrong)
# -RayTracing   the title's own ray-traced indirect light: lit interiors, about a third slower
# -Fsr4K        PC FidelityFX at 3840x2160 (quality, balanced or performance): FSR 4.1.2 where AMD's SDK offers it for the card, FSR 3.1 otherwise
# -Build        target\diag (the default, the build all measurements are of) or target\release
#               Light DRED is requested by default for diag and requires --features diagnostics.
# -More         other settings: -More @{VICTORY_PANEL='1'}
# -Console      the console the title sees: series-x (the default) or series-s
# -Rdna2        settings measured on an RX 6750 XT (12 GB, RDNA 2) with 32 GB of RAM: see the block below
# Run it from a normal window, not as administrator: the driver then keeps its shader cache elsewhere.
param(
    [Parameter(Mandatory)][string]$Exe,
    [switch]$Safe,
    [switch]$RayTracing,
    [ValidateSet('quality', 'balanced', 'performance')][string]$Fsr4K,
    [ValidateSet('diag', 'release')][string]$Build = 'diag',
    [hashtable]$More = @{},
    [ValidateSet('series-x', 'series-s')][string]$Console,
    [switch]$Rdna2
)
$settings = @{
    VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_RELAY = '2'; VICTORY_WIDE_BACK = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_JOIN_COPIES = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_RELAY_COPY = '1'; VICTORY_CARD_STEPS = '2'
    VICTORY_INDIRECT_BATCH = '2'; VICTORY_MAP_THREADS = '1'; VICTORY_TITLE_PRIORITIES = '0'; VICTORY_CARD_AWAKE = '1'
    VICTORY_SHOW_AFTER = '1'; VICTORY_AMBIENT = '0.8'
}
if ($Build -eq 'diag') { $settings.VICTORY_D3D12_DRED = 'light' }
if ($Safe) {
    $settings.VICTORY_UNDER_WIDE = '0'; $settings.VICTORY_LAND_ECHO = '0'
} else {
    $settings.VICTORY_THIN = '1'; $settings.VICTORY_JOIN_PARTS = '8'; $settings.VICTORY_UPLOAD_AHEAD = '1'
}
# -Rdna2: RX 6000 cards (RDNA 2). AMD's driver removes the device at about 2,048 live command
# allocators (issues #329, #376), so the relay stays on with fewer lists in the air and kept idle,
# the live lists are capped, and the 12 GB card-buffer tier of pull request #444 is used. The Series S
# profile, the title's own upscaler and the full ambient stand-in measured best (scriptsench.ps1).
if ($Rdna2) {
    foreach ($kv in @{
        VICTORY_RELAY = '2'; VICTORY_LATE_WAIT_LISTS = '96'; VICTORY_SUBMIT_FRAMES = '2'; VICTORY_SUBMIT_DEPTH = '32'
        VICTORY_IDLE_LISTS = '64'; VICTORY_LIST_CEILING = '1300'; VICTORY_CARD_STEPS_POOL = '8'; VICTORY_BURY_LAG = '16'
        VICTORY_FALLBACK_HEAPS = '1'; VICTORY_RESIDENCY = '1'; VICTORY_TEXTURE_BUDGET_MB = '6144'
        VICTORY_CARD_BUFFERS_MIN_MB = '1'; VICTORY_CARD_BUFFERS_MB = '1024'; VICTORY_CARD_AWAKE = '0'
        VICTORY_UPSCALER = '6'; VICTORY_AMBIENT = '1'; VICTORY_LANE_CORE = '1'
        VICTORY_PORT_CONSTANTS = '1'; VICTORY_PORT_DESCRIPTORS = '1'; VICTORY_PORT_GUARD = '1'
    }.GetEnumerator()) { $settings[$kv.Key] = $kv.Value }
    if (-not $Console) { $Console = 'series-s' }
}
if ($RayTracing) { $settings.VICTORY_BVH_BUILDER = '1' }
if ($Fsr4K) { $settings.VICTORY_FSR_4K = $Fsr4K.ToLowerInvariant() }
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }

$victory = Join-Path $PSScriptRoot "..\target\$Build\victory.exe"
if (-not (Test-Path $victory)) { Write-Host "No $victory. Build it first (README.md)."; exit 1 }
if (-not (Test-Path $Exe)) { Write-Host "No $Exe."; exit 1 }
# (Other settings left over in this window go; where your files are stays.)
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR', 'VICTORY_FIDELITYFX_DIR'
$inherited = @(Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths })
foreach ($entry in $inherited) { Remove-Item "Env:$($entry.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
$discarded = $inherited | Where-Object {
    $_.Name -notin $More.Keys -and -not $_.Value.Equals([Environment]::GetEnvironmentVariable($_.Name))
} | Sort-Object Name
if ($discarded) {
    Write-Host "Discarded inherited values for $($discarded.Name -join ', '). Use -More to pass them explicitly."
}
$Exe = (Resolve-Path $Exe).Path
Push-Location (Join-Path $PSScriptRoot '..')   # victory.toml is looked for here
$extra = @(); if ($Console) { $extra = @('--console', $Console) }
try { & $victory run $Exe @extra --execute } finally { Pop-Location }
