// =============================================================================
// GREEN-V PROJECT — Step 4 of 5 (Predictive Path - SystemVerilog)
// lookahead_unit.sv — 8-Instruction Window Scanner
//
// What this does:
//   - Accepts 8 fetched instructions simultaneously (inst_window[7:0][31:0])
//   - Scans all 8 in parallel combinationally — zero latency detection
//   - Detects: loops, integer compute bursts, FP ops, load/store sequences,
//              branch clusters
//   - Uses a weighted vote across the window — not just slot[0]
//   - Fires spike_detected if 2+ high-intensity instructions in the window
//   - Fires CMD_DOWN if window is dominated by memory/load ops
//   - Fires CMD_UP if window has significant compute density
//
// Port change from v1:
//   inst_window : [31:0]       -> [7:0][31:0]   (8 instructions)
//   inst_valid  : single bit   -> unchanged
// =============================================================================

module lookahead_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] inst_window [7:0],  // 8 fetched instructions
    input  logic        inst_valid,
    output logic [1:0]  lookahead_cmd,       // 00=IDLE 01=DOWN 10=HOLD 11=UP
    output logic        spike_detected
);

    // -------------------------------------------------------------------------
    // Command encodings
    // -------------------------------------------------------------------------
    localparam logic [1:0] CMD_IDLE = 2'b00;
    localparam logic [1:0] CMD_DOWN = 2'b01;
    localparam logic [1:0] CMD_HOLD = 2'b10;
    localparam logic [1:0] CMD_UP   = 2'b11;

    // -------------------------------------------------------------------------
    // RISC-V opcode field = bits [6:0]
    // -------------------------------------------------------------------------
    localparam logic [6:0] OP_BRANCH  = 7'b1100011; // BEQ/BNE/BLT -- loop indicator
    localparam logic [6:0] OP_INT_R   = 7'b0110011; // ADD/SUB/AND/OR/MUL -- compute
    localparam logic [6:0] OP_INT_I   = 7'b0010011; // ADDI/SLTI/XORI -- compute
    localparam logic [6:0] OP_LOAD    = 7'b0000011; // LW/LH/LB -- memory stall
    localparam logic [6:0] OP_STORE   = 7'b0100011; // SW/SH/SB -- memory stall
    localparam logic [6:0] OP_FP_R    = 7'b1010011; // FADD/FMUL/FDIV -- FP burst
    localparam logic [6:0] OP_FP_LOAD = 7'b0000111; // FLW/FLD -- FP memory
    localparam logic [6:0] OP_MADD    = 7'b1000011; // FMADD -- matrix/FP intensive

    // -------------------------------------------------------------------------
    // Per-slot pattern flags (combinational -- all 8 slots in parallel)
    // -------------------------------------------------------------------------
    logic [7:0] slot_is_branch;
    logic [7:0] slot_is_compute;
    logic [7:0] slot_is_mem;
    logic [7:0] slot_is_fp;
    logic [7:0] slot_is_madd;

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : pattern_detect
            assign slot_is_branch [i] = (inst_window[i][6:0] == OP_BRANCH);
            assign slot_is_compute[i] = (inst_window[i][6:0] == OP_INT_R) |
                                        (inst_window[i][6:0] == OP_INT_I);
            assign slot_is_mem    [i] = (inst_window[i][6:0] == OP_LOAD)  |
                                        (inst_window[i][6:0] == OP_STORE);
            assign slot_is_fp     [i] = (inst_window[i][6:0] == OP_FP_R)  |
                                        (inst_window[i][6:0] == OP_FP_LOAD);
            assign slot_is_madd   [i] = (inst_window[i][6:0] == OP_MADD);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Population counts -- how many of each type in the window
    // -------------------------------------------------------------------------
    logic [3:0] cnt_branch;
    logic [3:0] cnt_compute;
    logic [3:0] cnt_mem;
    logic [3:0] cnt_fp;
    logic [3:0] cnt_madd;

    always_comb begin
        cnt_branch  = 4'd0;
        cnt_compute = 4'd0;
        cnt_mem     = 4'd0;
        cnt_fp      = 4'd0;
        cnt_madd    = 4'd0;
        for (int j = 0; j < 8; j++) begin
            cnt_branch  = cnt_branch  + {3'b0, slot_is_branch [j]};
            cnt_compute = cnt_compute + {3'b0, slot_is_compute[j]};
            cnt_mem     = cnt_mem     + {3'b0, slot_is_mem    [j]};
            cnt_fp      = cnt_fp      + {3'b0, slot_is_fp     [j]};
            cnt_madd    = cnt_madd    + {3'b0, slot_is_madd   [j]};
        end
    end

    // -------------------------------------------------------------------------
    // Decision logic (combinational)
    // spike: branch + compute body, FP burst, or matrix op
    // CMD_UP: any spike, or compute-heavy window
    // CMD_DOWN: memory-dominated window
    // CMD_HOLD: balanced / mixed
    // -------------------------------------------------------------------------
    logic comb_spike;
    logic [1:0] comb_cmd;

    always_comb begin
        comb_spike = 1'b0;
        if ((cnt_branch >= 4'd1 && cnt_compute >= 4'd2) ||
            (cnt_fp     >= 4'd2)                         ||
            (cnt_madd   >= 4'd1))
            comb_spike = 1'b1;

        if (comb_spike || cnt_compute >= 4'd3 || cnt_fp >= 4'd1)
            comb_cmd = CMD_UP;
        else if (cnt_mem >= 4'd4 && cnt_compute == 4'd0 && cnt_fp == 4'd0)
            comb_cmd = CMD_DOWN;
        else if (cnt_mem >= 4'd2 && cnt_compute <= 4'd1)
            comb_cmd = CMD_DOWN;
        else
            comb_cmd = CMD_HOLD;
    end

    // -------------------------------------------------------------------------
    // Registered outputs
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookahead_cmd  <= CMD_HOLD;
            spike_detected <= 1'b0;
        end else begin
            spike_detected <= 1'b0;
            lookahead_cmd  <= CMD_HOLD;
            if (inst_valid) begin
                lookahead_cmd  <= comb_cmd;
                spike_detected <= comb_spike;
            end
        end
    end

endmodule
