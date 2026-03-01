`timescale 1ns/1ps

module clk_divider (
    input  logic        clk_in,
    input  logic        rst_n,
    input  logic [2:0]  freq_sel,
    input  logic        change_req,
    output logic        clk_out,
    output logic        change_ack
);

    function automatic logic [5:0] get_div_ratio (input logic [2:0] sel);
        case (sel)
            3'b000: get_div_ratio = 6'd32;
            3'b001: get_div_ratio = 6'd16;
            3'b010: get_div_ratio = 6'd8;
            3'b011: get_div_ratio = 6'd6;
            3'b100: get_div_ratio = 6'd4;
            3'b101: get_div_ratio = 6'd3;
            3'b110: get_div_ratio = 6'd2;
            3'b111: get_div_ratio = 6'd1;
            default: get_div_ratio = 6'd4;
        endcase
    endfunction

    logic [5:0]  active_div;
    logic [5:0]  pending_div;
    logic [5:0]  half_count;
    logic [5:0]  half_target;
    logic        clk_reg;
    logic        switch_pending;

    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            active_div     <= 6'd4;
            pending_div    <= 6'd4;
            half_count     <= 6'd0;
            half_target    <= 6'd2;
            clk_reg        <= 1'b0;
            change_ack     <= 1'b0;
            switch_pending <= 1'b0;
        end else begin
            change_ack <= 1'b0;

            if (change_req) begin
                pending_div    <= get_div_ratio(freq_sel);
                switch_pending <= 1'b1;
            end

            if (active_div == 6'd1) begin
                clk_reg    <= ~clk_reg;
                half_count <= 6'd0;
                if (switch_pending) begin
                    active_div     <= pending_div;
                    half_target    <= pending_div >> 1;
                    switch_pending <= 1'b0;
                    change_ack     <= 1'b1;
                end
            end else begin
                if (half_count >= half_target - 1) begin
                    clk_reg    <= ~clk_reg;
                    half_count <= 6'd0;
                    if (!clk_reg) begin
                        half_target <= (active_div + 1) >> 1;
                    end else begin
                        if (switch_pending) begin
                            active_div     <= pending_div;
                            half_target    <= pending_div >> 1;
                            switch_pending <= 1'b0;
                            change_ack     <= 1'b1;
                        end else begin
                            half_target <= active_div >> 1;
                        end
                    end
                end else begin
                    half_count <= half_count + 1;
                end
            end
        end
    end

    assign clk_out = clk_reg;

endmodule
