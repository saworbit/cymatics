param(
    [int]$Matches = 1,
    [int]$Seconds = 90,
    [double]$Scale = 4,
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $Godot) {
    $candidates = @(
        "godot",
        "C:\Godot\Godot_v4.7.2-stable_win64_console.exe",
        "C:\Godot\Godot_v4.7.2-stable_win64.exe",
        "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64.exe",
        "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe"
    )
    foreach ($c in $candidates) {
        if ($c -eq "godot") {
            $cmd = Get-Command godot -ErrorAction SilentlyContinue
            if ($cmd) { $Godot = $cmd.Source; break }
        } elseif (Test-Path $c) {
            $Godot = $c
            break
        }
    }
}

if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Error "Godot 4.7.2 not found. Set GODOT to the editor binary."
}

Write-Host "Lab: $Godot --headless -- --lab --lab-matches=$Matches --lab-seconds=$Seconds --lab-scale=$Scale"
& $Godot --headless --path $root -- --lab --lab-matches=$Matches --lab-seconds=$Seconds --lab-scale=$Scale --lab-quiet
$analyze = Join-Path $PSScriptRoot "lab_analyze.py"
if (Get-Command python -ErrorAction SilentlyContinue) {
    python $analyze
} else {
    py -3 $analyze
}
