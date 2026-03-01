module tb_cmu_top;
    logic clk_in, rst_n, inst_valid;
    logic [31:0] inst_window;
    logic [6:0]  ibuf_occupancy;
    logic clk_out;
    logic [2:0]  volt_ctrl;

    cmu_top dut (.*);

    // 500MHz Master Clock
    always #1 clk_in = (clk_in === 1'b0); 

    // Task to mimic a CPU Instruction Fetch
    task send_inst(input [31:0] opcode, input [6:0] fill);
        begin
            @(posedge clk_in);
            inst_window = opcode;
            ibuf_occupancy = fill;
            inst_valid = 1;
            @(posedge clk_in);
            inst_valid = 0;
        end
    endtask

    initial begin
        $dumpfile("greenv_final.vcd");
        $dumpvars(0, tb_cmu_top);
        
        clk_in=0; rst_n=0; inst_valid=0; inst_window=0; ibuf_occupancy=0;
        #10 rst_n=1;

        // --- MIMIC REAL CPU BEHAVIOR ---

        // 1. Idle/Startup: CPU is waiting for data
        repeat(10) send_inst(32'h00000013, 7'd5); // NOPs, Low occupancy

        // 2. Workload Spike: Lookahead detects a Loop (Predictive)
        #20 send_inst(32'h00000063, 7'd12); // Branch opcode, Occupancy still low!
        
        // 3. Heavy Execution: Buffer fills up (Reactive)
        repeat(20) send_inst(32'h00000033, 7'd60); // Math opcodes, High occupancy

        // 4. Memory Stall: Buffer drains
        repeat(15) send_inst(32'h00000003, 7'd8);  // Load opcodes, occupancy drops

        #200 $finish;
    end
endmodule