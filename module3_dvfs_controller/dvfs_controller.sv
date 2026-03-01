module dvfs_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  scale_cmd,     
    input  wire        scale_valid,   
    input  wire [1:0]  lookahead_cmd, 
    input  wire        spike_detected, 
    output reg  [2:0]  freq_sel,      
    output reg         change_req,    
    input  wire        change_ack,    
    input  wire [2:0]  current_sel,   
    output wire [2:0]  volt_ctrl      
);

    parameter S_IDLE = 2'b00, S_STEP = 2'b01, S_COOL = 2'b10;
    reg [1:0] state;
    reg [2:0] target;
    reg [4:0] count;

    assign volt_ctrl = freq_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; target <= 3'd4; freq_sel <= 3'd4; change_req <= 0; count <= 0;
        end else begin
            change_req <= 0;
            case (state)
                S_IDLE: begin
                    if (spike_detected) target <= 3'd7;
                    else if (scale_valid) begin
                        if (scale_cmd == 2'b11 && target < 3'd7) target <= target + 1;
                        else if (scale_cmd == 2'b01 && target > 3'd0) target <= target - 1;
                    end
                    if (target != current_sel) begin
                        freq_sel <= target; change_req <= 1; state <= S_STEP;
                    end
                end
                S_STEP: if (change_ack) state <= S_COOL;
                S_COOL: if (count < 5'd16) count <= count + 1; 
                        else begin count <= 0; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule