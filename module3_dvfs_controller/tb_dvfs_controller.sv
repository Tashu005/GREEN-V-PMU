module dvfs_controller_tb;
    reg clk, rst_n, scale_valid, spike_detected, change_ack;
    reg [1:0] scale_cmd, lookahead_cmd;
    reg [2:0] current_sel;
    wire [2:0] freq_sel, volt_ctrl;
    wire change_req;

    dvfs_controller dut (
        .clk(clk), .rst_n(rst_n), .scale_cmd(scale_cmd), .scale_valid(scale_valid),
        .lookahead_cmd(lookahead_cmd), .spike_detected(spike_detected),
        .freq_sel(freq_sel), .change_req(change_req), .change_ack(change_ack),
        .current_sel(current_sel), .volt_ctrl(volt_ctrl)
    );

    always #5 clk = (clk === 1'b0); // 100MHz clock

    initial begin
        clk=0; rst_n=0; scale_valid=0; spike_detected=0;
        scale_cmd=2'b10; lookahead_cmd=2'b10; current_sel=3'd4; change_ack=0;
        $dumpfile("dvfs_sim.vcd"); $dumpvars(0, dvfs_controller_tb);
        
        #20 rst_n=1;
        #20 @(posedge clk); scale_cmd=2'b11; scale_valid=1;
        #10 @(posedge clk); scale_valid=0;
        
        #500 $finish;
    end

    // Mock Ack - handled correctly in testbench always block
    always @(posedge clk) begin
        if (change_req) begin
            #30 change_ack <= 1;
            current_sel <= freq_sel;
            #10 change_ack <= 0;
        end
    end
endmodule