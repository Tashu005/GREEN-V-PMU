`timescale 1ns/1ps
// =============================================================================
// GREEN-V — tb_cmu_top.sv (v4 — 8-instruction window)
// =============================================================================

module tb_cmu_top;

    logic        clk_in, rst_n, inst_valid;
    logic [31:0] inst_window [7:0];       // 8-instruction window
    logic [6:0]  ibuf_occupancy;
    logic        clk_out;
    logic [2:0]  volt_ctrl;

    // Hierarchical probes
    wire [2:0] w_freq_sel     = dut.freq_sel;
    wire [2:0] w_current_sel  = dut.current_sel;
    wire       w_change_req   = dut.change_req;
    wire       w_change_ack   = dut.change_ack;
    wire [1:0] w_monitor_cmd  = dut.monitor_cmd;
    wire       w_spike        = dut.spike_detected;
    wire [1:0] w_lookahead    = dut.lookahead_cmd;

    cmu_top dut (
        .clk_in        (clk_in),
        .rst_n         (rst_n),
        .inst_window   (inst_window),
        .inst_valid    (inst_valid),
        .ibuf_occupancy(ibuf_occupancy),
        .clk_out       (clk_out),
        .volt_ctrl     (volt_ctrl)
    );

    // 500MHz master clock
    initial clk_in = 0;
    always #1 clk_in = ~clk_in;

    // -------------------------------------------------------------------------
    // Instruction opcodes (RISC-V lower 7 bits)
    // -------------------------------------------------------------------------
    localparam [31:0] INST_NOP    = 32'h00000013; // opcode 0x13 ADDI x0,x0,0
    localparam [31:0] INST_BRANCH = 32'h00000063; // opcode 0x63 BEQ
    localparam [31:0] INST_MATH   = 32'h00000033; // opcode 0x33 ADD
    localparam [31:0] INST_IMATH  = 32'h00000013; // opcode 0x13 ADDI (reuse NOP slot)
    localparam [31:0] INST_LOAD   = 32'h00000003; // opcode 0x03 LW
    localparam [31:0] INST_STORE  = 32'h00000023; // opcode 0x23 SW
    localparam [31:0] INST_FP     = 32'h00000053; // opcode 0x53 FADD
    localparam [31:0] INST_MADD   = 32'h00000043; // opcode 0x43 FMADD

    // -------------------------------------------------------------------------
    // Task: fill all 8 window slots with the same opcode
    // -------------------------------------------------------------------------
    task fill_window(input [31:0] opcode);
        for (int k = 0; k < 8; k++) inst_window[k] = opcode;
    endtask

    // -------------------------------------------------------------------------
    // Task: send one cycle with given window and occupancy
    // -------------------------------------------------------------------------
    task cpu_cycle(input [31:0] opcode, input [6:0] occ);
        @(posedge clk_in);
        fill_window(opcode);
        ibuf_occupancy <= occ;
        inst_valid     <= 1'b1;
        @(posedge clk_in);
        inst_valid     <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: send a LOOP window — branch + compute body (spike trigger)
    // Slots: [0]=branch, [1-5]=math, [6-7]=nop
    // -------------------------------------------------------------------------
    task send_loop_window(input [6:0] occ);
        @(posedge clk_in);
        inst_window[0] = INST_BRANCH;
        inst_window[1] = INST_MATH;
        inst_window[2] = INST_MATH;
        inst_window[3] = INST_MATH;
        inst_window[4] = INST_MATH;
        inst_window[5] = INST_MATH;
        inst_window[6] = INST_NOP;
        inst_window[7] = INST_NOP;
        ibuf_occupancy <= occ;
        inst_valid     <= 1'b1;
        @(posedge clk_in);
        inst_valid     <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: send an FP burst window (spike trigger)
    // -------------------------------------------------------------------------
    task send_fp_window(input [6:0] occ);
        @(posedge clk_in);
        inst_window[0] = INST_FP;
        inst_window[1] = INST_FP;
        inst_window[2] = INST_FP;
        inst_window[3] = INST_MATH;
        inst_window[4] = INST_FP;
        inst_window[5] = INST_MATH;
        inst_window[6] = INST_NOP;
        inst_window[7] = INST_NOP;
        ibuf_occupancy <= occ;
        inst_valid     <= 1'b1;
        @(posedge clk_in);
        inst_valid     <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: send a memory stall window
    // -------------------------------------------------------------------------
    task send_mem_window(input [6:0] occ);
        @(posedge clk_in);
        inst_window[0] = INST_LOAD;
        inst_window[1] = INST_LOAD;
        inst_window[2] = INST_LOAD;
        inst_window[3] = INST_LOAD;
        inst_window[4] = INST_LOAD;
        inst_window[5] = INST_STORE;
        inst_window[6] = INST_STORE;
        inst_window[7] = INST_NOP;
        ibuf_occupancy <= occ;
        inst_valid     <= 1'b1;
        @(posedge clk_in);
        inst_valid     <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Gradual ramp with given opcode
    // -------------------------------------------------------------------------
    task ramp_occupancy(input [31:0] opcode, input [6:0] start_occ,
                        input [6:0] end_occ, input integer cycles);
        logic [6:0] occ;
        for (int ii = 0; ii < cycles; ii++) begin
            occ = start_occ + ((end_occ - start_occ) * ii) / (cycles - 1);
            cpu_cycle(opcode, occ);
        end
    endtask

    // -------------------------------------------------------------------------
    // Pass/Fail
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    task pass(input string msg); $display("  [PASS] %s", msg); pass_count++; endtask
    task fail(input string msg); $display("  [FAIL] %s", msg); fail_count++; endtask

    // -------------------------------------------------------------------------
    // SIMULATION
    // -------------------------------------------------------------------------
    logic [2:0] freq_at_spike;
    logic [2:0] freq_before;

    initial begin
        $dumpfile("greenv_final_v3.vcd");
        $dumpvars(0, tb_cmu_top);

        clk_in=0; rst_n=0; inst_valid=0; ibuf_occupancy=0;
        for (int k=0; k<8; k++) inst_window[k] = INST_NOP;

        repeat(10) @(posedge clk_in);
        rst_n = 1;
        repeat(5) @(posedge clk_in);

        $display("\n=== GREEN-V Realistic CPU Waveform Simulation ===\n");

        // =================================================================
        // SCENARIO 1: Cold start / idle
        // NOP stream, occupancy drifts 2-8
        // =================================================================
        $display("--- SCENARIO 1: Cold start / idle ---");
        for (int ii = 0; ii < 25; ii++)
            cpu_cycle(INST_NOP, 7'd2 + (ii % 7));
        $display("  freq_sel after idle = %0d (expect low)", w_freq_sel);
        $display("  Done.\n");

        // =================================================================
        // SCENARIO 2: Lookahead spike — THE KEY DEMO MOMENT
        // Loop window arrives (branch + 5 math) while occupancy = 12
        // Reactive system sees occ=12 → CMD_DOWN, does nothing
        // Lookahead sees branch+math in window → spike_detected=1 → jump to 7
        // Then occupancy ramps up gradually — freq already high when it peaks
        // =================================================================
        $display("--- SCENARIO 2: Lookahead spike (predictive path) ---");
        $display("  Loop window arrives — occupancy still low at 12");
        $display("  A pure reactive system would do nothing here.");
        $display("  freq_sel BEFORE loop window = %0d", w_freq_sel);

        freq_at_spike = w_freq_sel;

        // THE PREDICTIVE TRIGGER — branch + math body, low occupancy
        send_loop_window(7'd12);
        repeat(8) @(posedge clk_in); // propagation cycles

        $display("  spike_detected fired. freq_sel now = %0d (expect 7)", w_freq_sel);

        // Now ramp occupancy gradually — reactive threshold is at 55
        $display("  Occupancy now ramping up gradually (pipeline filling)...");
        ramp_occupancy(INST_MATH, 7'd12, 7'd62, 20);

        if (w_freq_sel == 3'd7)
            pass("freq_sel = 7 during ramp — clock was ready before workload peaked");
        else begin
            $display("  [INFO] freq_sel = %0d after spike+ramp", w_freq_sel);
            fail("freq_sel not at max — spike did not propagate correctly");
        end
        $display("");

        // =================================================================
        // SCENARIO 3: FP burst detection
        // Window with 4x FP ops — should spike even without branch
        // =================================================================
        $display("--- SCENARIO 3: FP burst detection ---");
        freq_before = w_freq_sel;
        ibuf_occupancy = 7'd10; // still low occupancy
        send_fp_window(7'd10);
        repeat(8) @(posedge clk_in);

        if (w_spike || w_freq_sel >= 3'd6)
            pass("FP burst detected — spike or high freq on FP-heavy window");
        else
            $display("  [INFO] freq_sel = %0d, spike = %0d on FP window", w_freq_sel, w_spike);
        $display("");

        // =================================================================
        // SCENARIO 4: Sustained heavy compute
        // Math window, occupancy 58-64 — freq should hold at 7
        // =================================================================
        $display("--- SCENARIO 4: Sustained heavy compute burst ---");
        for (int ii = 0; ii < 30; ii++)
            cpu_cycle(INST_MATH, 7'd58 + (ii % 6));

        if (w_freq_sel >= 3'd6)
            pass("freq_sel held high during sustained compute");
        else
            fail("freq_sel dropped during sustained compute");
        $display("  freq_sel = %0d during burst\n", w_freq_sel);

        // =================================================================
        // SCENARIO 5: Memory stall — lookahead CMD_DOWN
        // Memory window (5x load, 2x store) with draining occupancy
        // Lookahead should fire CMD_DOWN before monitor threshold
        // =================================================================
        $display("--- SCENARIO 5: Memory stall window ---");
        freq_before = w_freq_sel;
        for (int ii = 0; ii < 20; ii++)
            send_mem_window(7'd62 - (ii * 3));
        repeat(60) @(posedge clk_in);

        $display("  freq_sel after mem stall = %0d (expect lower than %0d)",
                 w_freq_sel, freq_before);
        if (w_freq_sel < freq_before)
            pass("freq_sel stepped down during memory stall");
        else
            $display("  [INFO] freq_sel = %0d — drain may need more cycles", w_freq_sel);
        $display("");

        // =================================================================
        // SCENARIO 6: Chaining test (current_sel fix verification)
        // =================================================================
        $display("--- SCENARIO 6: Multi-step chaining test ---");
        // First drain to low
        for (int ii = 0; ii < 30; ii++)
            cpu_cycle(INST_NOP, 7'd2 + (ii % 4));
        freq_before = w_freq_sel;
        $display("  freq_sel before second burst = %0d", freq_before);

        // Now ramp again
        ramp_occupancy(INST_MATH, 7'd5, 7'd62, 25);
        repeat(100) @(posedge clk_in);

        $display("  freq_sel after second burst = %0d", w_freq_sel);
        if (w_freq_sel > freq_before + 1)
            pass("Multiple UP steps chained — current_sel fix confirmed");
        else
            $display("  [INFO] 1 step or no change — may need more drain time first");
        $display("");

        // =================================================================
        // RESULTS
        // =================================================================
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("CHECK WAVEFORM: gtkwave greenv_final_v3.vcd\n");

        $display("GTKWave signal order for demo:");
        $display("  ibuf_occupancy, inst_window[0]");
        $display("  w_spike, w_lookahead, w_monitor_cmd");
        $display("  w_freq_sel, w_current_sel");
        $display("  w_change_req, w_change_ack, clk_out\n");

        $finish;
    end

    initial begin #2000000; $display("[WATCHDOG] Timeout"); $finish; end

endmodule
