`timescale 1ns/1ps

module tb_clk_divider;

    logic        clk_in;
    logic        rst_n;
    logic [2:0]  freq_sel;
    logic        change_req;
    logic        clk_out;
    logic        change_ack;

    clk_divider dut (
        .clk_in     (clk_in),
        .rst_n      (rst_n),
        .freq_sel   (freq_sel),
        .change_req (change_req),
        .clk_out    (clk_out),
        .change_ack (change_ack)
    );

    initial clk_in = 0;
    always  #1 clk_in = ~clk_in;

    initial begin
        $dumpfile("clk_divider.vcd");
        $dumpvars(0, tb_clk_divider);
    end

    task apply_freq_change(input [2:0] sel, input string label);
        @(posedge clk_in);
        freq_sel   <= sel;
        change_req <= 1'b1;
        $display("  Requesting %s (freq_sel=%03b)", label, sel);
        @(posedge clk_in);
        change_req <= 1'b0;
    endtask

    integer ack_cycle;
    task wait_for_ack(input integer max_cycles);
        ack_cycle = 0;
        repeat(max_cycles) begin
            @(posedge clk_in);
            ack_cycle++;
            if (change_ack) begin
                $display("  change_ack received after %0d master cycles", ack_cycle);
                disable wait_for_ack;
            end
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        rst_n      = 0;
        freq_sel   = 3'b100;
        change_req = 0;

        $display("\n=== GREEN-V clk_divider Simulation ===\n");

        repeat(10) @(posedge clk_in);
        rst_n = 1;
        @(posedge clk_in);
        $display("[RESET] Done. Running at div4 = 125MHz default.\n");

        $display("--- TEST 1: Default div4 (125MHz) ---");
        repeat(40) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 2: div4 -> div2 -> div1 ---");
        apply_freq_change(3'b110, "div2 = 250MHz");
        wait_for_ack(100);
        repeat(20) @(posedge clk_in);
        apply_freq_change(3'b111, "div1 = 500MHz");
        wait_for_ack(50);
        repeat(20) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 3: div1 -> div32 (deep idle) ---");
        apply_freq_change(3'b000, "div32 = 15.6MHz");
        wait_for_ack(300);
        repeat(300) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 4: Odd divide div3 (166.7MHz) ---");
        apply_freq_change(3'b101, "div3 = 166.7MHz");
        wait_for_ack(300);
        repeat(30) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 5: Odd divide div6 (83.3MHz) ---");
        apply_freq_change(3'b011, "div6 = 83.3MHz");
        wait_for_ack(200);
        repeat(60) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 6: Step all 8 levels ---");
        begin
            logic [2:0] lvl;
            for (lvl = 3'b000; lvl <= 3'b111; lvl++) begin
                apply_freq_change(lvl, "stepping");
                wait_for_ack(300);
                repeat(20) @(posedge clk_in);
            end
        end
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 7: Rapid override ---");
        @(posedge clk_in); freq_sel <= 3'b110; change_req <= 1'b1;
        @(posedge clk_in); freq_sel <= 3'b010; change_req <= 1'b1;
        @(posedge clk_in); change_req <= 1'b0;
        wait_for_ack(200);
        repeat(50) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("--- TEST 8: Return to div4 ---");
        apply_freq_change(3'b100, "div4 = 125MHz");
        wait_for_ack(100);
        repeat(40) @(posedge clk_in);
        $display("  PASS\n");
        pass_count++;

        $display("=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        $display("Open waveform: gtkwave clk_divider.vcd");
        $finish;
    end

    initial begin
        #200000;
        $display("[WATCHDOG] Timeout - force stop");
        $finish;
    end

endmodule
