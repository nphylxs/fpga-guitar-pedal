# Cmod A7 guitar multi-effects processor

Synthesizable SystemVerilog for **XC7A35T-1CPG236C**, using the onboard XADC and a 100 MHz, second-order, one-bit sigma-delta DAC. RTL modules are in `rtl/`; compile `audio_math_pkg.sv` first. No external codec, vendor-generated IP, external sample memory, or synthesis-time LUT files are required.

## Implementation highlights

- **Custom RTL DSP:** fixed-point overdrive with interpolated waveshaping, fractional-delay chorus, and a 32,768-sample feedback delay.
- **Mixed-clock acquisition:** XADC at 104 MHz, a coherent request/acknowledge CDC mailbox, and a 100 MHz processing domain at 48,828.125 samples/s.
- **Memory and timing:** inferred block RAM, pipelined arithmetic, synchronized reset release, and explicit XDC delay/skew constraints for the CDC payload.
- **Verification:** three self-checking SystemVerilog testbenches covering DSP arithmetic, acquisition, and full-system control/cadence.

### Routed results

Vivado 2026.1, Artix-7 `xc7a35tcpg236-1`, implementation dated October 18, 2026:

| Metric | Result |
|---|---:|
| Processing / acquisition clocks | 100 / 104 MHz |
| Worst setup slack | +1.002 ns |
| Worst hold slack | +0.048 ns |
| LUTs / registers | 1,392 / 922 |
| BRAM tiles / DSP slices | 17.5 / 8 |
| Failing setup / hold endpoints | 0 / 0 |
| Unconstrained internal endpoints | 0 |

[Archived implementation reports and regression results](docs/reports/README.md) support these figures. The Verilator regression was rerun successfully on October 26, 2026. **Status:** synthesized, placed, routed, and functionally simulated; FPGA programming and analog/audio measurements remain unverified. The CDC report contains 14 handshake-payload warnings, and the DRC report contains advisory warnings documented below.

### Repository guide

| Path | Contents |
|---|---|
| `rtl/` | Synthesizable SystemVerilog modules and fixed-point math package |
| `sim/` | Self-checking testbenches and simulation-only Xilinx primitive models |
| `scripts/test.sh` | Lint and three-suite Verilator regression |
| `scripts/build.tcl` | Vivado synthesis, implementation, reports, and bitstream generation |
| `cmod_a7_pedal.xdc` | Board pinout, clocks, CDC timing, and asynchronous I/O constraints |
| `docs/` | Preliminary wiring diagrams and archived verification reports |

## Hardware and clocking design notes

* **VAUX4 P is G3; N is G2.** DIP pin 15 reaches this channel through the Cmod's onboard analog scaling circuit. Reversing these package assignments would be incorrect. See [Digilent's master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Cmod-A7-Master.xdc).
* **Two MMCME2_BASE instances are necessary.** They use 12 MHz × 50 / 6 = 100 MHz and 12 MHz × 52 / 6 = 104 MHz, with VCOs of 600 and 624 MHz. A single MMCM has only one fractional output divider, in increments of 1/8. If 100 MHz uses an integer divider, the smallest shared VCO compatible with 104 MHz's fractional divider is 1300 MHz; if 104 MHz uses the integer divider, it is 2600 MHz. Neither is legal for this device. See [UG472](https://www.amd.com/content/dam/xilinx/support/documents/user_guides/ug472_7Series_Clocking.pdf) and [Artix-7 DS181](https://www.amd.com/content/dam/xilinx/support/documents/data_sheets/ds181_Artix_7_Data_Sheet.pdf).
* The exact nominal audio rate is **48,828.125 samples/s**, set by a divide-by-2048 clock enable. It is not an integer decimation of 1 MSPS. A rolling 16-conversion boxcar runs at the ADC rate; the most recent coherent result is sampled at the audio rate. There is up to one ADC conversion of sampling-age variation. Frequencies inherit the onboard oscillator's tolerance.
* Sixteen averages can improve ENOB by two bits only with suitable uncorrelated noise and adequate analog conditions. This design retains 14 bits of numerical resolution; it cannot guarantee 14-bit converter accuracy. A 16-point boxcar is also **not an adequate stand-alone audio anti-alias filter**. Its first null is 62.5 kHz and attenuation at the audio Nyquist frequency is only about 2.3 dB. Use an analog input low-pass filter below 24.4 kHz. A better digital resampler would be a scope extension.

## Signal path and timing

`XADC VAUX4 → rolling average → coherent CDC → DC blocker → overdrive/tone → chorus → delay → held PCM → sigma-delta → M3`

All effects accept a one-clock `in_valid` pulse when idle and produce a one-clock `out_valid` pulse. There is no backpressure; allow at least 8 clocks between transactions for standalone instances. The top supplies 2048 clocks between frames and pipelines all three effects with valid strobes. Disabled effects return bit-exact dry audio while their internal histories continue running. Mode and parameter registers are captured at the audio tick and remain constant for that transaction. A mode change or delay-time jump can click; this implementation does not crossfade or slew controls.

The XADC runs continuous, single-channel, unipolar VAUX4 conversion: `INIT_40=0014`, `INIT_41=31EF`, `INIT_42=0400`. DCLK is 104 MHz; ADCCLK is DCLK/4 = 26 MHz; a conversion takes 26 ADCCLK periods. EOC triggers a DRP read of address `14h`; DRDY qualifies DO[15:4]. Hardware averaging is disabled because the rolling filter is implemented in logic. Refer to [AMD UG480](https://www.amd.com/content/dam/xilinx/support/documents/user_guides/ug480_7Series_XADC.pdf).

The ADC domain accumulates sixteen unsigned 12-bit samples in a 16-bit sum. Dropping two LSBs produces a 14-bit average with two fractional bits relative to the original converter. This is mapped to signed PCM and filtered using `32604/32768 = 0.9949951171875` in the DC blocker. Its state retains eight fractional bits and transient headroom; only the output saturates. Multiply, accumulation, and output saturation are pipelined over three 100 MHz clock edges to meet routed timing. The approximate high-pass corner is 39 Hz. Startup history is masked until sixteen real conversions arrive.

The CDC mailbox holds its data until a three-stage request synchronizer has been observed and acknowledged through a three-stage return synchronizer. The destination continuously accepts snapshots, then consumes the latest one at the sample tick. XDC constrains the bundled data path to 15 ns and skew to 5 ns, and cuts only first-stage control synchronizer inputs. Reset assertion is shared and release synchronized; button reset lasts much longer than either domain's synchronization delay.

### Effects

* **Overdrive:** gain `(16 + drive)/16`, from 1 to 16.9375. A 256-entry asymmetric tanh ROM spans amplified inputs −131072 through +130048 in steps of 1024, with linear interpolation between entries. Positive and negative saturation levels are approximately +24576 and −16384. Multiplication and interpolation occur in separate cycles. Tone is a single-pole low-pass with Q8 state and unsigned Q0.16 alpha. The UART mapping supplies alpha 512..29072, corresponding to an equivalent pole frequency of approximately 61 Hz..4.56 kHz. The asymmetry generates DC, removed by the output coupling capacitor.
* **Chorus:** 2048×16 BRAM, 32-bit phase accumulator, 256-entry Q1.15 sine ROM, approximately 0.7 Hz LFO. Delay is `768 + sine * (2*depth)` samples, with eight fractional delay bits. Range at maximum depth is approximately 258..1278 samples (5.28..26.17 ms). Two sequential synchronous reads provide the near and far taps; linear interpolation weights the older sample by the fractional part. Output is 50% dry + 50% wet. Startup fill tracking masks unwritten memory.
* **Delay:** 32768×16 BRAM, delay 1..32768 samples at the module interface. UART selects 128..32768 in steps of 128. Default 18304 samples = 374.86592 ms, approximately a dotted eighth at 120 BPM. For another tempo, dotted-eighth duration is `45000/BPM` ms; UART quantizes this to 2.62144 ms steps. Feedback is capped at 240/256 = 0.9375. A single-pole damping filter with alpha 1/4 and Q8 state precedes the feedback multiplier. The write sum and dry-plus-half-wet output saturate. Full delay uses read-before-write at the same address, in separate cycles; no RAM array is reset.
* **DAC:** second-order cascade-of-integrators feedback loop with two signed 24-bit states, ±32768 feedback, and sign quantization at 100 MHz. Signed PCM is first converted to unsigned by XOR with `8000h` (equivalent to adding it modulo 65536). The modulator internally halves the centered input for stability headroom. Full-scale PCM therefore produces approximately 25%..75% density; zero PCM produces 50%. This is a real two-integrator noise-shaping loop, not PWM or a first-order accumulator. No dither is added; idle tones remain possible. Reset holds the pin low briefly.

Storage is 557056 sample-memory bits total: nominally 16 RAMB36 blocks for delay plus one RAMB36 for chorus, before implementation-specific packing. This fits within the 35T's 50 RAMB36 blocks. Actual LUT, DSP, BRAM and timing results must come from Vivado reports.

## Controls

Both buttons are synchronized and debounced for 10 ms. BTN0 asserts synchronous DSP reset while held; it does not reset the clock managers or its own debouncer. BTN1 advances on a debounced rising edge.

| Mode | Effects | LED[1:0] | RGB color |
|---|---|---|---|
| 0 | Clean | 00 | White |
| 1 | Overdrive | 01 | Red |
| 2 | Chorus | 10 | Cyan |
| 3 | Delay | 11 | Blue |
| 4 | All, in the order above | 00 | Magenta |

RGB outputs are active low. All buttons, LEDs, clock, UART, analog pins and DAC are assigned in `cmod_a7_pedal.xdc`.

UART is **115200 baud, 8 data bits, no parity, one stop bit**, idle high, 3.3 V logic. The receiver uses 868 main-clock cycles per bit (~115207 baud), validates the start and stop bits, and resets an incomplete packet after 20 ms between bytes. Unsupported parameter IDs are ignored. An AA byte in the value position is a normal value. Packet bytes are **binary**, not ASCII hex strings; an ordinary terminal needs a binary-send feature.

| Packet | Parameter | Default | Mapping |
|---|---|---|---|
| AA 01 vv | Drive | 48 | gain = 1 + vv/16 |
| AA 02 vv | Tone | 96 | alpha = (512 + 112×vv)/65536 |
| AA 03 vv | Chorus depth | 100 | peak deviation = 2×vv samples |
| AA 04 vv | Delay | 142 | delay = 128 + 128×vv samples |
| AA 05 vv | Feedback | 128 | min(vv,240)/256 |

The protocol has no checksum, reply channel, tempo command, or UART mode command. Example with Python and pyserial: `port.write(bytes([0xAA, 0x01, 96]))` sets drive to 7×. J17 is the FPGA RX signal driven by the onboard USB-UART bridge; do not connect a second active transmitter to the same net without isolating the bridge. An ESP32 connection may require board-level routing/isolation or a revised RX pin assignment.

## Analog connections

DIP pin 15 accepts the Cmod board's nominal **0..3.3 V** analog range, scaled onboard to the XADC's 0..1 V range. Use a high-impedance guitar buffer/preamp, input AC coupling, a quiet approximately 1.65 V bias at the DIP pin, and analog low-pass filtering. Keep the waveform inside that range. The negative VAUX input is part of the board's analog network, not a separate guitar connection. Share ground at DIP pin 25. See the [Cmod A7 reference manual](https://digilent.com/reference/_media/cmod_a7/cmod_a7_rm.pdf).

DIP pin 1 / M3 carries a 3.3 V logic bitstream. Connect it to an analog reconstruction low-pass filter, an AC-coupling capacitor and a suitable output buffer. A practical starting point is two **buffered** RC poles using 3.3 kΩ and 4.7 nF each (~10.3 kHz per pole), followed by 1 µF coupling into at least 100 kΩ. Component choices trade off audio bandwidth and carrier rejection; this is not a measured analog design. Do not drive headphones or a speaker directly from M3. The raw output rests around 1.65 V after filtering and swings roughly ±0.825 V at digital full scale because of modulator headroom.

## Build and verification

Prerequisites: Bash, a C++ compiler and Make for simulation, Verilator (validated with 5.052), and Vivado with Artix-7 device support (validated with 2026.1) for implementation. Run from the repository root.

```sh
./scripts/test.sh
vivado -mode batch -source scripts/build.tcl
```

The Vivado script targets the exact part, reads only `rtl/`, synthesizes, places and routes, writes utilization/timing/CDC/DRC reports, checks setup and hold slack, and writes `build/cmod_a7_pedal.bit`. Review CDC and unconstrained-path reports, verify BRAM inference, and resolve any implementation DRC failures before programming. The bundled CDC data is intentionally not independently synchronized bit by bit; assess that report with the handshake and constraints in view.

Verilator functional tests use **simulation-only** Xilinx models in `sim/xilinx_models.sv`. These models emulate DRP delivery and clock frequencies; they do not model analog conversion, MMCM lock physics, jitter or metastability. Never synthesize them. Hardware implementation uses the actual Xilinx primitives.

The tests exercise delay impulse timing including 32768-sample wraparound, unwritten-memory masking after reset, chorus integer/fractional reads, dry bypass, clipper monotonicity and asymmetry, saturated feedback, DAC density and bounded states, UART packets/framing recovery, ADC sample cadence, gain, DC rejection and saturation. See `build/*.log` for the actual run results. Vivado 2026.1 implementation was completed on 2026-10-18 for xc7a35tcpg236-1. Routed setup slack is +1.002 ns, hold slack +0.048 ns, and pulse-width slack +3.558 ns; there are no failing timing endpoints or unconstrained internal endpoints. Utilization is 1392 LUTs, 922 registers, 17.5 BRAM tiles, 8 DSPs and 2 MMCMs. All three Verilator regression suites pass after the input-filter pipeline and synchronous reset-distribution changes. CDC reports retain the 14 expected handshake-data warnings, with no critical CDC findings. DRC reports contain advisory DSP pipelining and missing configuration-voltage properties warnings, with no errors. FPGA programming, analog SNR/THD and listening tests remain unverified.
