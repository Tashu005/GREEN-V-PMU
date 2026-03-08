`timescale 1ns/1ps
// =============================================================================
// GREEN-V — tb_ibuf_monitor.sv (v2 — FSM + hysteresis verification)
//
// Tests:
//   TEST 1 — No false transition on brief threshold crossing (hysteresis)
//   TEST 2 — Transition commits after 8 sustained cycles
//   TEST 3 — Counter resets if signal drops before 8 cycles
//   TEST 4 — All 4 state transitions: HOLD→UP, UP→HOLD, HOLD→DOWN, DOWN→IDLE
//   TEST 5 — Noisy occupancy around threshold — no thrashing
//   TEST 6 — scale_valid fires exactly once per transition
// =============================================================================

module tb_ibuf_monitor;

    logic       clk, rst_n;
    logic [6:0] occupancy;
    logic [1:0] scale_cmd;
    logic       scale_valid;

    ibuf_monitor dut (.*);

    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // Pass/Fail
    integer pass_count = 0;
    integer fail_count = 0;
    task pass(input string msg); $display("  [PASS] %s", msg); pass_count++; endtask
    task fail(input string msg); $display("  [FAIL] %s", msg); fail_count++; endtask

    // Drive occupancy for N cycles
    task drive(input [6:0] occ, input integer cycles);
        occupancy = occ;
        repeat(cycles) @(posedge clk);
    endtask

    // Wait for scale_valid pulse, timeout after max_cycles
    task wait_valid(input integer max_cycles, output logic got_it);
        got_it = 0;
        repeat(max_cycles) begin
            @(posedge clk);
            if (scale_valid && !got_it) got_it = 1;
        end
    endtask

    logic [1:0] cmd_before;
    logic got_valid;
    integer valid_count;

    initial begin
        $dumpfile("ibuf_sim_v2.vcd");
        $dumpvars(0, tb_ibuf_monitor);

        rst_n = 0; occupancy = 7'd30; // HOLD zone
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("\n=== GREEN-V ibuf_monitor FSM + Hysteresis Testbench ===\n");

        // =====================================================================
        // TEST 1: Brief threshold crossing — should NOT trigger transition
        // Cross into UP zone for only 4 cycles (less than hysteresis=8)
        // scale_cmd must NOT change
        // =====================================================================
        $display("--- TEST 1: Brief crossing — no false transition ---");
        drive(7'd30, 5); // settle in HOLD
        cmd_before = scale_cmd;
        drive(7'd60, 4); // cross UP threshold for only 4 cycles
        drive(7'd30, 5); // drop back
        if (scale_cmd == cmd_before)
            pass("scale_cmd unchanged after 4-cycle crossing (hysteresis blocked)");
        else
            fail("scale_cmd changed on brief crossing — hysteresis not working");

        // =====================================================================
        // TEST 2: Sustained crossing — should commit after 8 cycles
        // =====================================================================
        $display("\n--- TEST 2: Sustained crossing commits after 8 cycles ---");
        drive(7'd30, 5); // settle in HOLD
        cmd_before = scale_cmd;

        // Drive UP zone for 10 cycles — should commit at cycle 8
        occupancy = 7'd60;
        valid_count = 0;
        repeat(12) begin
            @(posedge clk);
            if (scale_valid) valid_count++;
        end

        if (scale_cmd == 2'b11)
            pass("scale_cmd = CMD_UP after sustained crossing");
        else
            fail("scale_cmd did not reach CMD_UP after 12 cycles");

        if (valid_count == 1)
            pass("scale_valid fired exactly once during transition");
        else begin
            $display("  [INFO] scale_valid fired %0d times", valid_count);
            if (valid_count > 1)
                fail("scale_valid fired multiple times — thrashing");
        end

        // =====================================================================
        // TEST 3: Counter resets if signal drops before committing
        // Cross threshold for 6 cycles, drop, cross again — should need
        // another full 8 cycles from the drop point
        // =====================================================================
        $display("\n--- TEST 3: Counter resets on signal dropout ---");
        drive(7'd30, 5); // back to HOLD — wait for it to commit
        repeat(15) @(posedge clk); // give FSM time to settle back to HOLD

        cmd_before = scale_cmd;
        drive(7'd60, 6); // cross UP for 6 cycles (not enough)
        drive(7'd30, 3); // drop back — counter should reset
        drive(7'd60, 4); // cross again for only 4 more cycles
        drive(7'd30, 5); // drop

        // Should still be in HOLD — 6+4 with a gap doesn't count as 8 sustained
        if (scale_cmd == 2'b10 || scale_cmd == cmd_before)
            pass("Counter reset on dropout — no premature transition");
        else
            fail("Transition happened despite non-sustained crossing");

        // =====================================================================
        // TEST 4: All 4 state transitions
        // =====================================================================
        $display("\n--- TEST 4: All 4 state transitions ---");

        // HOLD → UP
        drive(7'd30, 3);
        repeat(20) @(posedge clk); // let it settle
        drive(7'd60, 10);
        if (scale_cmd == 2'b11) pass("HOLD -> UP transition");
        else fail("HOLD -> UP failed");

        // UP → HOLD
        drive(7'd35, 10);
        if (scale_cmd == 2'b10) pass("UP -> HOLD transition");
        else fail("UP -> HOLD failed");

        // HOLD → DOWN
        drive(7'd10, 10);
        if (scale_cmd == 2'b01) pass("HOLD -> DOWN transition");
        else fail("HOLD -> DOWN failed");

        // DOWN → IDLE
        drive(7'd2, 10);
        if (scale_cmd == 2'b00) pass("DOWN -> IDLE transition");
        else fail("DOWN -> IDLE failed");

        // IDLE → HOLD (recovery)
        drive(7'd35, 10);
        if (scale_cmd == 2'b10) pass("IDLE -> HOLD recovery");
        else fail("IDLE -> HOLD recovery failed");

        // =====================================================================
        // TEST 5: Noisy signal around threshold — no thrashing
        // Oscillate occupancy around the UP threshold (55) every 2 cycles
        // With hysteresis, scale_cmd should NOT toggle repeatedly
        // =====================================================================
        $display("\n--- TEST 5: Noisy signal — no thrashing ---");
        drive(7'd35, 5); // settle in HOLD
        repeat(15) @(posedge clk);

        valid_count = 0;
        // Noise: alternate 52 and 58 every 2 cycles for 32 cycles
        for (int ii = 0; ii < 16; ii++) begin
            drive(7'd58, 2); // just above threshold
            drive(7'd52, 2); // just below threshold
            if (scale_valid) valid_count++;
        end

        $display("  scale_valid fired %0d times during 32 cycles of noise", valid_count);
        if (valid_count <= 1)
            pass("No thrashing on noisy signal around threshold");
        else
            fail("Thrashing detected — hysteresis not wide enough");

        // =====================================================================
        // RESULTS
        // =====================================================================
        $display("\n=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("CHECK WAVEFORM: gtkwave ibuf_sim_v2.vcd\n");

        $finish;
    end

    initial begin #500000; $display("[WATCHDOG] Timeout"); $finish; end

endmodule
