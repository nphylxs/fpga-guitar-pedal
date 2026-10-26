# Verification evidence

The routed Vivado 2026.1 reports below were generated on **2026-10-18** for `xc7a35tcpg236-1`. They are archived results, not a new implementation run. Absolute project prefixes in report command headers have been removed for portability and trailing whitespace trimmed; numerical results are unchanged.

- [Timing](timing.rpt): setup, hold, pulse width, clock interactions, and unconstrained-path checks.
- [Utilization](utilization.rpt): post-route LUT, register, BRAM, DSP, and clock resources.
- [CDC](cdc.rpt): 14 CDC-15 warnings on the held handshake payload; no critical findings. Review alongside the request/acknowledge logic and XDC max-delay/bus-skew constraints.
- [DRC](drc.rpt): configuration-voltage properties and DSP pipelining warnings; no errors in this report.
- [Regression](regression.txt): all three self-checking suites passed on **2026-10-26**, using Verilator 5.052 and `./scripts/test.sh`.

These reports establish digital implementation and functional simulation results. They do not establish board programming, analog performance, listening quality, or measured SNR/THD. Simulation primitive models do not model metastability or physical ADC behavior.

To reproduce the flow from the repository root:

```sh
./scripts/test.sh
vivado -mode batch -source scripts/build.tcl
```

Fresh reports are written to ignored `build/`; this directory is an intentional snapshot. [Source hashes](source-sha256.txt) record the RTL, simulation sources, constraints, and build scripts present when the snapshot was packaged on 2026-10-26.
