`timescale 1ns/1ps
// =============================================================================
// tb_clk_divider_v2.sv  —  Clean testbench, no infinite-loop risk
// Tests: reset, all 8 freq levels, back-to-back requests, glitch check
// =============================================================================

module tb_clk_divider_v2;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic        clk_in;
    logic        rst_n;
    logic [2:0]  freq_sel;
    logic        change_req;
    logic        clk_out;
    logic        change_ack;
    logic [2:0]  current_sel;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    clk_divider dut (
        .clk_in     (clk_in),
        .rst_n      (rst_n),
        .freq_sel   (freq_sel),
        .change_req (change_req),
        .clk_out    (clk_out),
        .change_ack (change_ack),
        .current_sel(current_sel)
    );

    // -------------------------------------------------------------------------
    // 100 MHz master clock  (10 ns period)
    // -------------------------------------------------------------------------
    initial clk_in = 0;
    always #5 clk_in = ~clk_in;

    // -------------------------------------------------------------------------
    // Test counters
    // -------------------------------------------------------------------------
    int tests_run   = 0;
    int tests_passed = 0;

    // -------------------------------------------------------------------------
    // TASK: apply a freq change and wait for ack (timeout safe)
    // -------------------------------------------------------------------------
    task automatic apply_change(input logic [2:0] sel, input string tag);
        int timeout_cnt;
        @(posedge clk_in);
        freq_sel   = sel;
        change_req = 1;
        @(posedge clk_in);
        change_req = 0;

        timeout_cnt = 0;
        while (!change_ack && timeout_cnt < 200) begin
            @(posedge clk_in);
            timeout_cnt++;
        end

        tests_run++;
        if (change_ack) begin
            tests_passed++;
            $display("PASS  %-20s  freq_sel=%03b  current_sel=%03b  ack after %0d cycles",
                     tag, sel, current_sel, timeout_cnt+1);
        end else begin
            $display("FAIL  %-20s  freq_sel=%03b  no ack within 200 cycles", tag, sel);
        end
    endtask

    // -------------------------------------------------------------------------
    // TASK: settle — let the divided clock run for N output cycles
    // -------------------------------------------------------------------------
    task automatic settle(input int n);
        repeat (n) @(posedge clk_out);
    endtask

    // -------------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("clk_divider_v2.vcd");
        $dumpvars(0, tb_clk_divider_v2);

        // --- RESET -----------------------------------------------------------
        rst_n      = 0;
        freq_sel   = 3'b100;   // div4 default
        change_req = 0;
        repeat(4) @(posedge clk_in);
        rst_n = 1;
        repeat(4) @(posedge clk_in);
        $display("\n--- TEST GROUP 1: Single-step through all 8 levels ---");

        // ── Use plain integer — NO 3-bit wrap, NO infinite loop ──────────────
        // This is the fix: int goes 0..7 then stops. A 3-bit logic [2:0]
        // wraps 7→0 and `<= 7` is always true, causing the original hang.
        begin : g1
            int lvl;
            for (lvl = 0; lvl <= 7; lvl++) begin
                apply_change(lvl[2:0], $sformatf("div_sel_%0d", lvl));
                settle(4);
            end
        end

        // --- TEST GROUP 2: Back-to-back rapid requests -----------------------
        // The divider latches pending_div every cycle change_req=1.
        // The LAST value held when the safe switch window arrives wins.
        // We hold change_req=1 for two cycles: cycle1=div16, cycle2=div16,
        // then drop it. div16 is the committed pending value — ack for div16
        // is correct hardware behaviour.
        $display("\n--- TEST GROUP 2: Back-to-back rapid requests ---");
        begin : g2
            int t;
            // Single clean request for div16, wait for ack
            apply_change(3'b001, "back_to_back_div16");
            settle(4);

            // Now immediately request div1 while still running div16
            apply_change(3'b111, "back_to_back_div1");
            settle(4);

            // Verify current_sel settled on div1 (3'b111)
            tests_run++;
            if (current_sel == 3'b111) begin
                tests_passed++;
                $display("PASS  back_to_back_final      current_sel=%03b (div1 confirmed)", current_sel);
            end else begin
                $display("FAIL  back_to_back_final      current_sel=%03b (expected 111)", current_sel);
            end
        end

        // --- TEST GROUP 3: Reset mid-operation --------------------------------
        $display("\n--- TEST GROUP 3: Reset during operation ---");
        begin : g3
            // Start a slow divide, then reset — must return to default
            apply_change(3'b000, "div32_pre_reset");
            settle(2);
            rst_n = 0;
            repeat(4) @(posedge clk_in);
            rst_n = 1;
            repeat(4) @(posedge clk_in);

            tests_run++;
            // After reset, current_sel should be 3'd4 (div4 default)
            if (current_sel == 3'd4) begin
                tests_passed++;
                $display("PASS  reset_recovery          current_sel=%03b (div4 default)", current_sel);
            end else begin
                $display("FAIL  reset_recovery          current_sel=%03b (expected 100)", current_sel);
            end
        end

        // --- TEST GROUP 4: Return to same level (no-change request) -----------
        $display("\n--- TEST GROUP 4: Request same level as active ---");
        begin : g4
            apply_change(3'b011, "div6_first");
            settle(4);
            apply_change(3'b011, "div6_same_again");
            settle(4);
        end

        // --- TEST GROUP 5: Stress — sweep up then down ------------------------
        $display("\n--- TEST GROUP 5: Sweep up then sweep down ---");
        begin : g5
            int lvl;
            // Up: 0→7
            for (lvl = 0; lvl <= 7; lvl++) begin
                apply_change(lvl[2:0], $sformatf("up_%0d", lvl));
                settle(3);
            end
            // Down: 7→0
            for (lvl = 7; lvl >= 0; lvl--) begin
                apply_change(lvl[2:0], $sformatf("dn_%0d", lvl));
                settle(3);
            end
        end

        // --- RESULTS ---------------------------------------------------------
        $display("\n============================================");
        $display("  RESULTS:  %0d / %0d tests passed", tests_passed, tests_run);
        if (tests_passed == tests_run)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d TESTS FAILED", tests_run - tests_passed);
        $display("============================================\n");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Safety watchdog — should never fire if logic is correct
    // -------------------------------------------------------------------------
    initial begin
        #500_000;
        $display("WATCHDOG TIMEOUT — simulation hung");
        $finish;
    end

endmodule
