# Unattended frame-rate run (diagnostics build): starts the title through play.ps1 -Rdna2 (plus
# -More), presses Enter through the menus with VICTORY_KEYS, waits for scenes with more than 1,000
# draws, records them for -HeavySeconds, stops the title and prints one line: the median, lowest
# and highest frame rate of those scenes and the frame line's preparing / GPU / copying-back times.
#   scripts\bench.ps1 -Exe <your copy's executable> -Tag base
#   scripts\bench.ps1 -Exe <...> -Tag x -More @{VICTORY_SOMETHING='1'}
# Runs differ by about 1 fps from one to the next: compare two or more of each.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Tag,
    [hashtable]$More = @{},
    [int]$HeavySeconds = 150,
    [string]$Console = '',
    [int]$TimeoutSeconds = 600,
    [string]$Keys = ((15..120 | Where-Object { $_ % 4 -eq 3 } | ForEach-Object { "${_}:Enter" }) -join ',')
)
$exe = (Resolve-Path $Exe).Path
$dir = "$env:LOCALAPPDATA\victory\bench"
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir "$Tag.log"
Get-Process victory -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$More['VICTORY_KEYS'] = $Keys
$play = Join-Path $PSScriptRoot 'play.ps1'
$job = Start-Job -ScriptBlock {
    param($play, $exe, $more, $log, $console)
    if ($console) { & $play -Exe $exe -Rdna2 -Console $console -More $more *> $log }
    else { & $play -Exe $exe -Rdna2 -More $more *> $log }
} -ArgumentList $play, $exe, $More, $log, $Console
$started = Get-Date
$heavySince = $null
$outcome = 'timeout'
while (((Get-Date) - $started).TotalSeconds -lt $TimeoutSeconds) {
    Start-Sleep 5
    $p = Get-Process victory -ErrorAction SilentlyContinue
    if (-not $p) {
        if (((Get-Date) - $started).TotalSeconds -gt 30) { $outcome = 'exited'; break } else { continue }
    }
    if ($p.MainWindowTitle -match '(\d+) draws') {
        if ([int]$Matches[1] -gt 1000 -and -not $heavySince) { $heavySince = Get-Date }
    }
    if ($heavySince -and ((Get-Date) - $heavySince).TotalSeconds -ge $HeavySeconds) { $outcome = 'done'; break }
}
Get-Process victory -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue

# Frame lines (they wrap): "N fps, M ms/frame (P preparing ... G on the GPU; B copying back ...), D draws/frame"
$text = (Get-Content $log -Raw) -replace "`r?`n", ' '
$rx = [regex]'([\d.]+) fps, ([\d.]+) ms/frame \(([\d.]+) preparing.*?; ([\d.]+) on the GPU; ([\d.]+) copying back.*?\), (\d+) draws/frame'
$rows = foreach ($m in $rx.Matches($text)) {
    [pscustomobject]@{ fps = [double]$m.Groups[1].Value; prep = [double]$m.Groups[3].Value; gpu = [double]$m.Groups[4].Value; back = [double]$m.Groups[5].Value; draws = [int]$m.Groups[6].Value }
}
$heavy = @($rows | Where-Object { $_.draws -gt 1000 })
$removed = ([regex]::Matches($text, 'device removed')).Count
if ($heavy.Count -gt 0) {
    $f = $heavy.fps | Sort-Object
    $avg = { param($k) [math]::Round(($heavy | Measure-Object $k -Average).Average, 1) }
    "{0}: {1}, heavy samples {2}, fps median {3} min {4} max {5}, prep {6} gpu {7} back {8} ms, device lost {9}" -f `
        $Tag, $outcome, $heavy.Count, $f[[int]($f.Count / 2)], $f[0], $f[-1], (& $avg prep), (& $avg gpu), (& $avg back), $removed
} else {
    "{0}: {1}, no heavy samples (device lost {2})" -f $Tag, $outcome, $removed
}
