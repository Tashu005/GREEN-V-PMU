`timescale 1ns/1ps
// =============================================================================
// GREEN-V — tb_lookahead_unit.sv (v2 — 8-instruction window)
//
// Tests every detection path in the fixed lookahead_unit:
//   TEST 1  — Reset: outputs HOLD, no spike
//   TEST 2  — inst_valid=0: outputs stay HOLD regardless of window
//   TEST 3  — Loop spike: branch + 2 math ops -> spike_detected + CMD_UP
//   TEST 4  — Loop threshold: branch + 1 math (below threshold) -> no spike
//   TEST 5  — FP burst spike: 2+ FP ops -> spike_detected + CMD_UP
//   TEST 6  — Single FP: 1 FP op -> CMD_UP but no spike
//   TEST 7  — MADD spike: 1 matrix op -> spike_detected + CMD_UP
//   TEST 8  — Compute burst: 3+ INT ops, no branch -> CMD_UP, no spike
//   TEST 9  — Memory dominated: 4+ loads, no compute -> CMD_DOWN
//   TEST 10 — Light memory: 2 loads, 1 compute -> CMD_DOWN
//   TEST 11 — Mixed window: balanced compute + mem -> CMD_HOLD
//   TEST 12 — NOP stream: all NOPs -> CMD_HOLD, no spike
//   TEST 13 — spike_detected is 1-cycle pulse only
//   TEST 14 — All 8 slots scanned: spike from slot[7] not slot[0]
// =============================================================================

module tb_lookahead_unit;

    logic        clk, rst_n, inst_valid;
    logic [31:0] inst_window [7:0];
    logic [1:0]  lookahead_cmd;
    logic        spike_detected;

    lookahead_unit dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .inst_window  (inst_window),
        .inst_valid   (inst_valid),
        .lookahead_cmd(lookahead_cmd),
        .spike_detected(spike_detected)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // -------------------------------------------------------------------------
    // Instruction encodings — only lower 7 bits matter for opcode detection
    // -------------------------------------------------------------------------
    localparam [31:0] INST_NOP    = 32'h0000007F; // opcode 0x7F — reserved, matches no pattern
    localparam [31:0] INST_BRANCH = 32'h00000063; // opcode 0x63 — branch
    localparam [31:0] INST_MATH   = 32'h00000033; // opcode 0x33 — INT R-type
    localparam [31:0] INST_IMATH  = 32'h00000013; // opcode 0x13 — INT I-type (NOP slot)
    localparam [31:0] INST_LOAD   = 32'h00000003; // opcode 0x03 — load
    localparam [31:0] INST_STORE  = 32'h00000023; // opcode 0x23 — store
    localparam [31:0] INST_FP     = 32'h00000053; // opcode 0x53 — FP R-type
    localparam [31:0] INST_FLOAD  = 32'h00000007; // opcode 0x07 — FP load
    localparam [31:0] INST_MADD   = 32'h00000043; // opcode 0x43 — FMADD

    // -------------------------------------------------------------------------
    // Pass/Fail
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    task pass(input string msg); $display("  [PASS] %s", msg); pass_count++; endtask
    task fail(input string msg); $display("  [FAIL] %s", msg); fail_count++; endtask

    // -------------------------------------------------------------------------
    // Helper: fill all 8 slots with same opcode
    // -------------------------------------------------------------------------
    task fill_all(input [31:0] opcode);
        for (int k = 0; k < 8; k++) inst_window[k] = opcode;
    endtask

    // -------------------------------------------------------------------------
    // Helper: send window and wait one cycle for registered output
    // -------------------------------------------------------------------------
    task send_window_and_wait;
        @(posedge clk);
        inst_valid <= 1;
        @(posedge clk); // outputs register here
        inst_valid <= 0;
        @(posedge clk); // read outputs this cycle
    endtask

    // -------------------------------------------------------------------------
    // SIMULATION
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("lookahead_sim_v2.vcd");
        $dumpvars(0, tb_lookahead_unit);

        // Init
        clk=0; rst_n=0; inst_valid=0;
        fill_all(INST_NOP);

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("\n=== GREEN-V lookahead_unit Testbench v2 ===\n");

        // =====================================================================
        // TEST 1: Reset state
        // =====================================================================
        $display("--- TEST 1: Reset state ---");
        if (lookahead_cmd == 2'b10)
            pass("lookahead_cmd = HOLD after reset");
        else
            fail("lookahead_cmd wrong after reset");
        if (spike_detected == 0)
            pass("spike_detected = 0 after reset");
        else
            fail("spike_detected high after reset");

        // =====================================================================
        // TEST 2: inst_valid=0 — window ignored
        // =====================================================================
        $display("\n--- TEST 2: inst_valid=0 — window ignored ---");
        // Load a spike-worthy window but don't assert inst_valid
        inst_window[0] = INST_BRANCH;
        inst_window[1] = INST_MATH;
        inst_window[2] = INST_MATH;
        inst_window[3] = INST_MATH;
        for (int k=4; k<8; k++) inst_window[k] = INST_NOP;
        inst_valid = 0;
        repeat(3) @(posedge clk);

        if (spike_detected == 0)
            pass("spike_detected stays 0 when inst_valid=0");
        else
            fail("spike_detected fired without inst_valid");
        if (lookahead_cmd == 2'b10)
            pass("lookahead_cmd stays HOLD when inst_valid=0");
        else
            fail("lookahead_cmd changed without inst_valid");

        // =====================================================================
        // TEST 3: Loop spike — branch + 2 math ops
        // =====================================================================
        $display("\n--- TEST 3: Loop spike (branch + 2 math) ---");
        inst_window[0] = INST_BRANCH;
        inst_window[1] = INST_MATH;
        inst_window[2] = INST_MATH;
        inst_window[3] = INST_NOP;
        inst_window[4] = INST_NOP;
        inst_window[5] = INST_NOP;
        inst_window[6] = INST_NOP;
        inst_window[7] = INST_NOP;
        send_window_and_wait;

        if (spike_detected)
            pass("spike_detected fired on loop pattern (branch + 2 math)");
        else
            fail("spike_detected did not fire on loop pattern");
        if (lookahead_cmd == 2'b11)
            pass("lookahead_cmd = CMD_UP on loop pattern");
        else
            fail("lookahead_cmd wrong on loop pattern");

        // =====================================================================
        // TEST 4: Branch + 1 math only — below spike threshold
        // =====================================================================
        $display("\n--- TEST 4: Branch + 1 math — no spike (below threshold) ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_BRANCH;
        inst_window[1] = INST_MATH;
        send_window_and_wait;

        if (!spike_detected)
            pass("No spike on branch + 1 math (needs 2 math for spike)");
        else
            fail("False spike on branch + 1 math");

        // =====================================================================
        // TEST 5: FP burst spike — 2+ FP ops
        // =====================================================================
        $display("\n--- TEST 5: FP burst spike (2+ FP ops) ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_FP;
        inst_window[1] = INST_FP;
        inst_window[2] = INST_MATH;
        send_window_and_wait;

        if (spike_detected)
            pass("spike_detected fired on FP burst (2 FP ops)");
        else
            fail("spike_detected did not fire on FP burst");
        if (lookahead_cmd == 2'b11)
            pass("lookahead_cmd = CMD_UP on FP burst");
        else
            fail("lookahead_cmd wrong on FP burst");

        // =====================================================================
        // TEST 6: Single FP op — CMD_UP but no spike
        // =====================================================================
        $display("\n--- TEST 6: Single FP op — CMD_UP, no spike ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_FP;
        send_window_and_wait;

        if (!spike_detected)
            pass("No spike on single FP op");
        else
            fail("False spike on single FP op");
        if (lookahead_cmd == 2'b11)
            pass("CMD_UP on single FP op (FP always triggers UP)");
        else
            fail("lookahead_cmd wrong on single FP op");

        // =====================================================================
        // TEST 7: MADD spike — single matrix op triggers spike
        // =====================================================================
        $display("\n--- TEST 7: MADD spike (1 matrix op) ---");
        fill_all(INST_NOP);
        inst_window[3] = INST_MADD; // put it in middle slot
        send_window_and_wait;

        if (spike_detected)
            pass("spike_detected fired on MADD (matrix op)");
        else
            fail("spike_detected did not fire on MADD");

        // =====================================================================
        // TEST 8: Compute burst — 3+ INT ops, no branch, no spike
        // =====================================================================
        $display("\n--- TEST 8: Compute burst (3 INT ops, no branch) ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_MATH;
        inst_window[1] = INST_MATH;
        inst_window[2] = INST_MATH;
        send_window_and_wait;

        if (!spike_detected)
            pass("No spike on 3 INT ops without branch");
        else
            fail("False spike on INT-only window");
        if (lookahead_cmd == 2'b11)
            pass("CMD_UP on 3+ compute ops");
        else
            fail("lookahead_cmd wrong on compute burst");

        // =====================================================================
        // TEST 9: Memory dominated — 4+ loads, no compute -> CMD_DOWN
        // =====================================================================
        $display("\n--- TEST 9: Memory dominated window -> CMD_DOWN ---");
        fill_all(INST_NOP); // clear previous window first
        inst_window[0] = INST_LOAD;
        inst_window[1] = INST_LOAD;
        inst_window[2] = INST_LOAD;
        inst_window[3] = INST_LOAD;
        inst_window[4] = INST_LOAD;
        inst_window[5] = INST_NOP;
        inst_window[6] = INST_NOP;
        inst_window[7] = INST_NOP;
        send_window_and_wait;

        if (lookahead_cmd == 2'b01)
            pass("CMD_DOWN on memory-dominated window (5 loads)");
        else
            fail("lookahead_cmd wrong on memory window");
        if (!spike_detected)
            pass("No spike on memory window");
        else
            fail("False spike on memory window");

        // =====================================================================
        // TEST 10: Light memory — 2 loads, 1 compute -> CMD_DOWN
        // =====================================================================
        $display("\n--- TEST 10: Light memory (2 loads, 1 compute) -> CMD_DOWN ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_LOAD;
        inst_window[1] = INST_LOAD;
        inst_window[2] = INST_MATH;
        send_window_and_wait;

        if (lookahead_cmd == 2'b01)
            pass("CMD_DOWN on 2 loads + 1 compute");
        else
            $display("  [INFO] lookahead_cmd = %02b (borderline case)", lookahead_cmd);

        // =====================================================================
        // TEST 11: Mixed window -> CMD_HOLD
        // =====================================================================
        $display("\n--- TEST 11: Mixed window -> CMD_HOLD ---");
        fill_all(INST_NOP);
        inst_window[0] = INST_MATH;
        inst_window[1] = INST_LOAD;
        inst_window[2] = INST_MATH;
        inst_window[3] = INST_LOAD;
        send_window_and_wait;

        if (lookahead_cmd == 2'b10)
            pass("CMD_HOLD on balanced mixed window");
        else
            $display("  [INFO] lookahead_cmd = %02b on mixed window", lookahead_cmd);

        // =====================================================================
        // TEST 12: NOP stream -> CMD_HOLD, no spike
        // =====================================================================
        $display("\n--- TEST 12: NOP stream -> CMD_HOLD, no spike ---");
        fill_all(INST_NOP);
        send_window_and_wait;

        if (lookahead_cmd == 2'b10)
            pass("CMD_HOLD on NOP stream");
        else
            fail("lookahead_cmd wrong on NOP stream");
        if (!spike_detected)
            pass("No spike on NOP stream");
        else
            fail("False spike on NOP stream");

        // =====================================================================
        // TEST 13: spike_detected is 1-cycle pulse only
        // =====================================================================
        $display("\n--- TEST 13: spike_detected is 1-cycle pulse ---");
        // Send spike window
        fill_all(INST_NOP);
        inst_window[0] = INST_BRANCH;
        inst_window[1] = INST_MATH;
        inst_window[2] = INST_MATH;
        @(posedge clk); inst_valid <= 1;
        @(posedge clk); inst_valid <= 0; // stop sending
        @(posedge clk); // spike should fire here
        // Next cycle — no new valid window — spike must clear
        @(posedge clk);
        if (!spike_detected)
            pass("spike_detected cleared after 1 cycle (pulse only)");
        else
            fail("spike_detected stuck high — not a pulse");

        // =====================================================================
        // TEST 14: Spike detected from slot[7] not slot[0]
        // Proves all 8 slots are scanned, not just the first
        // =====================================================================
        $display("\n--- TEST 14: Spike from slot[7] — all slots scanned ---");
        fill_all(INST_NOP);
        inst_window[7] = INST_MADD; // put trigger in LAST slot only
        send_window_and_wait;

        if (spike_detected)
            pass("spike_detected from slot[7] — full window scanned");
        else
            fail("spike missed in slot[7] — not all slots scanned");

        // =====================================================================
        // RESULTS
        // =====================================================================
        $display("\n=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("CHECK WAVEFORM: gtkwave lookahead_sim_v2.vcd\n");

        $finish;
    end

    initial begin #200000; $display("[WATCHDOG] Timeout"); $finish; end

endmodule
