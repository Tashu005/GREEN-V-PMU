module lookahead_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] inst_window,    
    input  logic        inst_valid,
    output logic [1:0]  lookahead_cmd,  // 00=IDLE, 01=DOWN, 10=HOLD, 11=UP
    output logic        spike_detected  
);

    // Using localparam for SV compatibility
    localparam logic [1:0] CMD_IDLE = 2'b00;
    localparam logic [1:0] CMD_DOWN = 2'b01;
    localparam logic [1:0] CMD_HOLD = 2'b10;
    localparam logic [1:0] CMD_UP   = 2'b11;

    // RISC-V Pattern Detection
    logic is_loop, is_int_hi, is_mem;
    assign is_loop   = (inst_window[6:0] == 7'b1100011); 
    assign is_int_hi = (inst_window[6:0] == 7'b0110011); 
    assign is_mem    = (inst_window[6:0] == 7'b0000011); 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookahead_cmd  <= CMD_HOLD;
            spike_detected <= 1'b0;
        end else begin
            spike_detected <= 1'b0;
            lookahead_cmd  <= CMD_HOLD;

            if (inst_valid) begin
                if (is_loop) begin
                    spike_detected <= 1'b1;   
                    lookahead_cmd  <= CMD_UP;
                end else if (is_int_hi) begin
                    lookahead_cmd  <= CMD_UP;   
                end else if (is_mem) begin
                    lookahead_cmd  <= CMD_DOWN; 
                end
            end
        end
    end
endmodule