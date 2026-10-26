#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rtl=(rtl/audio_math_pkg.sv)
for f in rtl/*.sv; do [[ "$f" == rtl/audio_math_pkg.sv ]] || rtl+=("$f"); done
# Suppress only intentional unused primitive pins, model signals, FPGA INITs,
# mixed reset styles and file/timescale conventions. Width warnings are fatal.
flags=(--timing --assert -Wall -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-SYNCASYNCNET)
verilator --lint-only "${flags[@]}" --top-module cmod_a7_guitar_top "${rtl[@]}" sim/xilinx_models.sv > build/lint.log 2>&1
for tb in tb_dsp tb_input tb_top; do
  verilator --binary -j 2 "${flags[@]}" --top-module "$tb" --Mdir "build/obj_$tb" "${rtl[@]}" sim/xilinx_models.sv "sim/$tb.sv" > "build/$tb.compile.log" 2>&1
  "build/obj_$tb/V$tb" | tee "build/$tb.log"
done
