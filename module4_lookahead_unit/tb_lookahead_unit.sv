module tb_lookahead_unit;
    logic clk, rst_n, inst_valid;
    logic [31:0] inst_window;
    logic [1:0]  lookahead_cmd;
    logic        spike_detected;

    // Instantiate using .* for SV shortcut
    lookahead_unit dut (.*);

    // Clock Generation
    always #5 clk = (clk === 1'b0);

    initial begin
        $dumpfile("lookahead_sim.vcd");
        $dumpvars(0, tb_lookahead_unit);
        
        clk=0; rst_n=0; inst_valid=0; inst_window=32'h0;
        #20 rst_n=1;

        // Loop Pattern
        @(posedge clk); inst_window = 32'h00000063; inst_valid = 1; 
        @(posedge clk); inst_valid = 0;

        // Arithmetic Pattern
        #50 @(posedge clk); inst_window = 32'h00000033; inst_valid = 1; 
        @(posedge clk); inst_valid = 0;

        #100 $finish;
    end
endmodule