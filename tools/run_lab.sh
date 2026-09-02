#!/usr/bin/env bash
# Headless AI-vs-AI lab run (Linux/macOS/Git Bash). Mirrors run_lab.ps1.
# Usage: tools/run_lab.sh [matches] [seconds] [scale]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATCHES="${1:-1}"
SECONDS_PER="${2:-90}"
SCALE="${3:-4}"
GODOT="${GODOT:-godot}"

echo "Lab: $GODOT --headless -- --lab --lab-matches=$MATCHES --lab-seconds=$SECONDS_PER --lab-scale=$SCALE"
"$GODOT" --headless --path "$ROOT" -- --lab --lab-matches="$MATCHES" --lab-seconds="$SECONDS_PER" --lab-scale="$SCALE" --lab-quiet
python3 "$ROOT/tools/lab_analyze.py"
