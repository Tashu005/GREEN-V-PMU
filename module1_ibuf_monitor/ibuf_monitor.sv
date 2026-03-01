`timescale 1ns/1ps

module ibuf_monitor (
    input  logic        clk,           // System Clock
    input  logic        rst_n,         // Active-low Reset
    input  logic [6:0]  ibuf_fill,     // [6:0] Live occupancy 0-64 
    output logic [1:0]  scale_cmd,     // 00:IDLE, 01:DOWN, 10:HOLD, 11:UP 
    output logic        scale_valid    // 1-cycle pulse on state change [cite: 76]
);

    // State Encoding
    typedef enum logic [1:0] {
        IDLE       = 2'b00,
        SCALE_DOWN = 2'b01,
        HOLD       = 2'b10,
        SCALE_UP   = 2'b11
    } state_t;

    state_t current_state, next_state;
    logic [3:0] hyst_count; // 4-bit counter for 8-cycle hysteresis 

    // --- State Transition Logic ---
    always_comb begin
        next_state = current_state; // Default: stay in current state
        
        // Threshold-based transitions 
        if      (ibuf_fill < 7'd4)   next_state = IDLE;       // < 5% (4/64)
        else if (ibuf_fill < 7'd19)  next_state = SCALE_DOWN; // < 30% (19/64)
        else if (ibuf_fill > 7'd54)  next_state = SCALE_UP;   // > 85% (54/64)
        else if (ibuf_fill >= 7'd32 && ibuf_fill <= 7'd51) 
                                     next_state = HOLD;       // 50-80% (32-51/64)
        // Note: 30-50% and 80-85% are "Gray Zones" where we maintain state 
    end

    // --- Sequential Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= HOLD; // Start in balanced state
            hyst_count    <= 4'd0;
            scale_valid   <= 1'b0;
        end else begin
            scale_valid <= 1'b0; // Default: no change pulse
            
            if (next_state != current_state) begin
                if (hyst_count >= 4'd7) begin // 8-cycle hysteresis check 
                    current_state <= next_state;
                    hyst_count    <= 4'd0;
                    scale_valid   <= 1'b1; // Trigger pulse for dvfs_controller
                end else begin
                    hyst_count <= hyst_count + 1;
                end
            end else begin
                hyst_count <= 4'd0; // Reset counter if state stabilizes
            end
        end
    end

    // Output assignment
    assign scale_cmd = current_state;

endmodule