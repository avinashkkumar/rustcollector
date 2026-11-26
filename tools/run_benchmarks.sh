#!/usr/bin/env bash
# Runs the Rustfall benchmark suite on Linux: native, FSR 1 and FSR 2 (Quality, 67%),
# RUNS times each, fullscreen at the monitor's native resolution, then builds the report.
#
#   ./run_benchmarks.sh                 # preset high, 3 runs each
#   PRESET=medium RUNS=5 ./run_benchmarks.sh
#   DISPLAY_DRIVER=wayland ./run_benchmarks.sh   # native Wayland instead of X11/XWayland
#
# Results land in ../benchmark_results (shared with the Windows build on the same drive).
set -euo pipefail
cd "$(dirname "$0")"
PRESET=${PRESET:-high}
RUNS=${RUNS:-3}
EXTRA=()
[[ -n "${DISPLAY_DRIVER:-}" ]] && EXTRA+=(--display-driver "$DISPLAY_DRIVER")
CONFIGS=("off 1.0" "fsr1 0.67" "fsr2 0.67")
for cfg in "${CONFIGS[@]}"; do
	read -r up scale <<<"$cfg"
	for ((i = 1; i <= RUNS; i++)); do
		echo "== $PRESET / $up @ $scale  (run $i/$RUNS)"
		./Rustfall.x86_64 "${EXTRA[@]}" --run-benchmark --bench-preset="$PRESET" \
			--bench-upscaler="$up" --bench-scale="$scale" --bench-autoquit | grep -E "OVERALL|written"
	done
done
python3 ../compare_benchmarks.py ../benchmark_results -o ../benchmark_results/comparison.html
