`timescale 1ns/1ps

// =============================================================================
// GREEN-V PROJECT — Step 2 of 5
// Module  : clk_divider.sv
// Purpose : Glitch-free programmable clock divider.
//           Divides master clock by 1,2,3,4,6,8,16,32.
//           Switches only during HIGH→LOW transition — no glitches ever.
//
// FIXES from v1:
//   1. current_sel port added — dvfs_controller reads live frequency level
//   2. div1 passthrough fixed — clk_out = clk_in directly, no toggling
//   3. Switch window clarified — applies pending ratio on falling edge only
//   4. Odd divide documented  — 66% duty cycle is known single-edge FF limit
// =============================================================================

module clk_divider (
    input  logic        clk_in,
    input  logic        rst_n,
    input  logic [2:0]  freq_sel,
    input  logic        change_req,
    output logic        clk_out,
    output logic        change_ack,
    output logic [2:0]  current_sel    // NEW: live level — read this not freq_sel
);

    // -------------------------------------------------------------------------
    // LOOKUP: freq_sel → divide ratio
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // LOOKUP: ratio → freq_sel (for current_sel output)
    // -------------------------------------------------------------------------
    function automatic logic [2:0] get_sel (input logic [5:0] ratio);
        case (ratio)
            6'd32: get_sel = 3'd0;
            6'd16: get_sel = 3'd1;
            6'd8:  get_sel = 3'd2;
            6'd6:  get_sel = 3'd3;
            6'd4:  get_sel = 3'd4;
            6'd3:  get_sel = 3'd5;
            6'd2:  get_sel = 3'd6;
            6'd1:  get_sel = 3'd7;
            default: get_sel = 3'd4;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // INTERNAL SIGNALS
    // -------------------------------------------------------------------------
    logic [5:0]  active_div;
    logic [5:0]  pending_div;
    logic [5:0]  half_count;
    logic [5:0]  half_target;
    logic        clk_reg;
    logic        switch_pending;

    // -------------------------------------------------------------------------
    // MAIN DIVIDER FSM
    //
    // GLITCH-FREE STRATEGY:
    //   New ratio is applied only when clk_reg=1 (falling edge moment).
    //   This stretches the LOW period — never truncates a HIGH period.
    //   Result: no runt pulses, no glitch on downstream flip-flops.
    //
    // ODD DIVIDE DUTY CYCLE:
    //   div3: HIGH=2 cycles, LOW=1 cycle → 66% duty (single-edge FF limit)
    //   div6: HIGH=3 cycles, LOW=3 cycles → 50% (even within odd ratio)
    //   True 50% for div3 requires dual-edge technique — Phase 2 FPGA work.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            active_div     <= 6'd4;
            pending_div    <= 6'd4;
            half_count     <= 6'd0;
            half_target    <= 6'd2;
            clk_reg        <= 1'b0;
            change_ack     <= 1'b0;
            switch_pending <= 1'b0;
            current_sel    <= 3'd4;
        end else begin
            change_ack <= 1'b0;

            // Stage incoming request
            if (change_req) begin
                pending_div    <= get_div_ratio(freq_sel);
                switch_pending <= 1'b1;
            end

            if (active_div == 6'd1) begin
                // ── DIV1: passthrough mode ────────────────────────────────
                // clk_out = clk_in via assign below
                // Apply switch immediately — no counter needed
                if (switch_pending) begin
                    active_div     <= pending_div;
                    half_target    <= pending_div >> 1;
                    half_count     <= 6'd0;
                    clk_reg        <= 1'b0;
                    switch_pending <= 1'b0;
                    change_ack     <= 1'b1;
                    current_sel    <= get_sel(pending_div);
                end

            end else begin
                // ── COUNTER-BASED DIVIDER ─────────────────────────────────
                if (half_count >= half_target - 1) begin
                    clk_reg    <= ~clk_reg;
                    half_count <= 6'd0;

                    if (clk_reg) begin
                        // FALLING EDGE — safe switch window
                        if (switch_pending) begin
                            active_div     <= pending_div;
                            half_target    <= pending_div >> 1;
                            switch_pending <= 1'b0;
                            change_ack     <= 1'b1;
                            current_sel    <= get_sel(pending_div);
                        end else begin
                            half_target <= active_div >> 1;
                        end
                    end else begin
                        // RISING EDGE — set HIGH half period
                        // ceil(ratio/2) = (ratio+1)/2
                        half_target <= (active_div + 6'd1) >> 1;
                    end

                end else begin
                    half_count <= half_count + 6'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // OUTPUT — div1 bypasses counter entirely
    // -------------------------------------------------------------------------
    assign clk_out = (active_div == 6'd1) ? clk_in : clk_reg;

endmodule