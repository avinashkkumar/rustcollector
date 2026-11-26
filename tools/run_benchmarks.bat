@echo off
rem Runs the Rustfall benchmark suite on Windows: native, FSR 1 and FSR 2 (Quality, 67 percent),
rem RUNS times each, fullscreen at native resolution, then builds the comparison report.
rem   run_benchmarks.bat            (preset high, 3 runs each)
rem   run_benchmarks.bat medium 5
rem Results land in ..\benchmark_results (shared with the Linux build on the same drive).
setlocal
cd /d "%~dp0"
set PRESET=%1
if "%PRESET%"=="" set PRESET=high
set RUNS=%2
if "%RUNS%"=="" set RUNS=3
for %%C in ("off 1.0" "fsr1 0.67" "fsr2 0.67") do (
  for /f "tokens=1,2" %%A in (%%C) do (
    for /l %%I in (1,1,%RUNS%) do (
      echo == %PRESET% / %%A @ %%B  run %%I of %RUNS%
      Rustfall.console.exe --run-benchmark --bench-preset=%PRESET% --bench-upscaler=%%A --bench-scale=%%B --bench-autoquit | findstr /C:"OVERALL" /C:"written"
    )
  )
)
where py >nul 2>nul && (py -3 ..\compare_benchmarks.py ..\benchmark_results -o ..\benchmark_results\comparison.html) || (python ..\compare_benchmarks.py ..\benchmark_results -o ..\benchmark_results\comparison.html)
pause
