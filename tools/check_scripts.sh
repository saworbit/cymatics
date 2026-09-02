#!/usr/bin/env bash
# Parse-check every tracked GDScript file with the Godot binary.
# Usage: tools/check_scripts.sh [path-to-godot]
# Exit code is non-zero if any script fails to parse.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${1:-${GODOT:-godot}}"

cd "$ROOT"
fail=0
count=0
while IFS= read -r f; do
	count=$((count + 1))
	if ! "$GODOT" --headless --path "$ROOT" --check-only --script "res://$f" >/tmp/check_out.txt 2>&1; then
		echo "FAIL $f"
		grep -i "error" /tmp/check_out.txt | head -5
		fail=1
	fi
done < <(git ls-files --cached --others --exclude-standard '*.gd')

if [ "$fail" -ne 0 ]; then
	echo "Script check failed."
	exit 1
fi
echo "All $count scripts parse."
