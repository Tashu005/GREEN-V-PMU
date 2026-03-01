`timescale 1ns/1ps

module tb_ibuf_monitor;

    // Signals
    logic        clk;
    logic        rst_n;
    logic [6:0]  ibuf_fill;
    logic [1:0]  scale_cmd;
    logic        scale_valid;

    // Instantiate Device Under Test (DUT)
    ibuf_monitor dut (
        .clk(clk),
        .rst_n(rst_n),
        .ibuf_fill(ibuf_fill),
        .scale_cmd(scale_cmd),
        .scale_valid(scale_valid)
    );

    // Clock Generation (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Test Procedure
    initial begin
        // Setup Waveform Dump
        $dumpfile("ibuf_monitor.vcd");
        $dumpvars(0, tb_ibuf_monitor);

        // Initialize
        rst_n = 0;
        ibuf_fill = 7'd32; // Start at 50% (HOLD)
        #20 rst_n = 1;

        $display("\n=== GREEN-V ibuf_monitor Simulation ===\n");

        // TEST 1: Spike to SCALE_UP (>85%)
        $display("TEST 1: Simulating High Workload (Fill=60)...");
        ibuf_fill = 7'd60; 
        #100; // Wait for 10 cycles to clear 8-cycle hysteresis

        // TEST 2: Transition to SCALE_DOWN (<30%)
        $display("TEST 2: Simulating Low Workload (Fill=15)...");
        ibuf_fill = 7'd15;
        #100;

        // TEST 3: Memory Stall (IDLE <5%)
        $display("TEST 3: Simulating Memory Stall (Fill=2)...");
        ibuf_fill = 7'd2;
        #100;

        // TEST 4: Gray Zone Stability (Should NOT change state)
        $display("TEST 4: Entering Gray Zone (Fill=45)... Expecting no rapid change.");
        ibuf_fill = 7'd45;
        #100;

        $display("\nSimulation Complete. Check GTKWave for pulse validation.");
        $finish;
    end

endmodule