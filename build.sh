#!/usr/bin/env bash
# Exports Linux and Windows builds into build/linux and build/windows.
# Needs Godot 4.7.2 on PATH (or GODOT=/path/to/godot) with export templates installed.
set -euo pipefail
cd "$(dirname "$0")"
GODOT=${GODOT:-godot}
mkdir -p build/linux build/windows
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Linux" build/linux/Rustfall.x86_64
"$GODOT" --headless --export-release "Windows" build/windows/Rustfall.exe
cp tools/compare_benchmarks.py build/
cp tools/run_benchmarks.sh build/linux/
cp tools/run_benchmarks.bat build/windows/
ls -la build/linux build/windows
