# GREEN-V: Predictive Dynamic Voltage and Frequency Scaling (DVFS)
**An Autonomous, Hardware-Level Power Management Unit for RISC-V Cores**

## 🌐 Overview
**GREEN-V** is an RTL-based Power Management Unit (PMU) designed to solve the "Latency Gap" in modern processor power scaling. Traditional software-driven DVFS (operating at the OS level) has a reaction latency of $>100,000ns$, causing massive energy waste during short workload spikes. 

GREEN-V achieves an **effective 0ns reaction time** by moving the scaling logic into the hardware pipeline, utilizing a **Predictive Instruction Lookahead Unit**.

## 🚀 Key Features
* **Predictive Workload Awareness:** Scans the Instruction Window (RV32I) to identify loops and high-compute bursts 8–12 cycles *before* they reach the execution stage.
* **Immediate-Idle Jump:** A specialized FSM state that drops the frequency to the lowest power state ($div32$) instantly during memory stalls, reclaiming up to **62% dynamic power**.
* **Glitch-Free Actuation:** An 8-stage hardware clock divider that scales from **500MHz down to 15.6MHz** without skipping pulses or causing timing violations.
* **OS-Agnostic:** Operates entirely in hardware; requires no kernel drivers or software overhead.



## 🛠 Project Architecture
The system is divided into five modular RTL components:

| Module | Component | Primary Function |
| :--- | :--- | :--- |
| **Module 1** | `ibuf_monitor` | **The Sensor:** Monitors instruction buffer occupancy for reactive scaling. |
| **Module 2** | `clk_divider` | **The Actuator:** Performs glitch-free frequency scaling ($div1$ to $div32$). |
| **Module 3** | `dvfs_controller` | **The Brain:** An FSM that prioritizes predictive signals over reactive ones. |
| **Module 4** | `lookahead_unit` | **The Predictor:** Decodes opcodes (Branches, Loads, R-Type) for preemptive scaling. |
| **Module 5** | `cmu_top` | **The Wrapper:** Integrates the full DVFS pipeline for SoC integration. |

## 📊 Technical Specifications
* **Logic Type:** SystemVerilog (Synthesizable RTL)
* **Target Savings:** ~62% Energy reduction during bursty workloads.
* **Frequency Range:** 15.6 MHz — 500 MHz (8 steps).
* **Reaction Latency:** 0ns (Predictive) / 16-cycle Hysteresis (Reactive).
* **Hardware Overhead:** Negligible (<1% of typical RISC-V core area).

## 💻 Simulation & Verification
The system has been verified using **Icarus Verilog** and **GTKWave**.
1. Navigate to `module5_cmu_top`.
2. Run: `iverilog -g2012 -o greenv_sim ../module1_ibuf_monitor/*.sv ../module2_clk_divider/*.sv ../module3_dvfs_controller/*.sv ../module4_lookahead_unit/*.sv cmu_top.sv tb_cmu_top.sv`
3. Execute: `vvp greenv_sim`
4. View: `gtkwave greenv_final.vcd`

---
*Developed as a B.Tech ECE Research Project at Banasthali Vidyapith.*
*Contributors: Ananya Choudhary (Tashu005) & Team*
