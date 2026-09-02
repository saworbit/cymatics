#!/usr/bin/env bash
# Full test suite: unit tests, then the integration harness.
#
#   tools/run_tests.sh [path-to-godot]
#   GODOT=C:/Godot/godot.cmd tools/run_tests.sh
#
# Exits non-zero if any test fails OR if the engine logged a script error.
# Godot exits 0 on a GDScript runtime error, so the log has to be checked too.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${1:-${GODOT:-godot}}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT"
fail=0

# Global class names (TestCase and friends) are registered at import time, so a
# fresh checkout needs this before the runner can resolve them.
echo "== Importing project"
"$GODOT" --headless --path "$ROOT" --import >"$TMP/import.log" 2>&1
if grep -qE "SCRIPT ERROR|Parse Error" "$TMP/import.log"; then
	echo "FAIL: errors during import"
	grep -E "SCRIPT ERROR|Parse Error" "$TMP/import.log" | head -20
	fail=1
fi

echo
echo "== Unit tests"
"$GODOT" --headless --path "$ROOT" --script res://tests/run_tests.gd >"$TMP/unit.log" 2>&1
unit_status=$?
grep -vE "^\[ *[0-9]+%\]|\[ DONE \]" "$TMP/unit.log" | grep -E "^(Running|==|  PASS|  FAIL|       |[0-9]+ passed|OK|Failed tests:|  - )" || true
if [ "$unit_status" -ne 0 ]; then
	echo "FAIL: unit tests returned $unit_status"
	fail=1
fi
if grep -qE "SCRIPT ERROR|Parse Error" "$TMP/unit.log"; then
	echo "FAIL: engine logged a script error during unit tests"
	grep -E "SCRIPT ERROR|Parse Error" "$TMP/unit.log" | head -20
	fail=1
fi

echo
echo "== Integration"
"$GODOT" --headless --path "$ROOT" --script res://tests/integration_run.gd >"$TMP/integration.log" 2>&1
int_status=$?
grep -E "^(  \[|nodes:|Integration|VIOLATION|  - )" "$TMP/integration.log" || true
if [ "$int_status" -ne 0 ]; then
	echo "FAIL: integration returned $int_status"
	fail=1
fi
# The fluid's CPU-fallback warning is expected headless; script errors are not.
if grep -qE "SCRIPT ERROR|Parse Error" "$TMP/integration.log"; then
	echo "FAIL: engine logged a script error during integration"
	grep -E "SCRIPT ERROR|Parse Error" "$TMP/integration.log" | head -20
	fail=1
fi

echo
if [ "$fail" -ne 0 ]; then
	echo "TEST SUITE FAILED"
	exit 1
fi
echo "TEST SUITE PASSED"
