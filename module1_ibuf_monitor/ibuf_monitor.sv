
// GREEN-V PROJECT — Step 1 of 5 (Reactive Sensor)
// ibuf_monitor.sv — 4-State FSM with 8-Cycle Hysteresis Counter
// What this does vs the original:
//   BEFORE: Pure combinational threshold — thrashes on noisy occupancy
//   NOW:    Proper 4-state FSM — state only changes after threshold is held
//           for HYSTERESIS_CYCLES consecutive cycles. No false transitions.
// States:
//   S_IDLE       — occupancy <  5  — CMD_IDLE  (memory stall, clock floor)
//   S_DOWN       — occupancy < 19  — CMD_DOWN  (computational slack)
//   S_HOLD       — occupancy < 55  — CMD_HOLD  (balanced)
//   S_UP         — occupancy >= 55 — CMD_UP    (execution units saturated)
//
// Hysteresis:
//   A pending state change requires the new threshold condition to be true
//   for HYSTERESIS_CYCLES (8) consecutive cycles before the FSM commits.
//   If the condition drops before the counter expires, counter resets.
//   This prevents oscillation on noisy / borderline occupancy values.
//
// Outputs:
//   scale_cmd   [1:0] — command encoding (same as before)
//   scale_valid [0]   — 1-cycle pulse on state change


module ibuf_monitor (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [6:0] occupancy,      // 0-127, buffer fill count
    output logic [1:0] scale_cmd,      // 00=IDLE 01=DOWN 10=HOLD 11=UP
    output logic       scale_valid     // 1-cycle pulse on state change
);

    // -------------------------------------------------------------------------
    // Command encodings
    // -------------------------------------------------------------------------
    localparam logic [1:0] CMD_IDLE = 2'b00;
    localparam logic [1:0] CMD_DOWN = 2'b01;
    localparam logic [1:0] CMD_HOLD = 2'b10;
    localparam logic [1:0] CMD_UP   = 2'b11;

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    localparam logic [1:0] S_IDLE = 2'b00;
    localparam logic [1:0] S_DOWN = 2'b01;
    localparam logic [1:0] S_HOLD = 2'b10;
    localparam logic [1:0] S_UP   = 2'b11;

    // -------------------------------------------------------------------------
    // Thresholds (based on 7-bit occupancy, max=127, buffer depth=64)
    // Report values: IDLE<5, DOWN<30%, HOLD 30-85%, UP>85%
    // At depth 64: 5%, 30%, 85% = 4, 19, 55
    // -------------------------------------------------------------------------
    localparam logic [6:0] THR_IDLE = 7'd4;   // < 5   → IDLE
    localparam logic [6:0] THR_DOWN = 7'd19;  // < 30% → DOWN
    localparam logic [6:0] THR_UP   = 7'd55;  // > 85% → UP
    // HOLD is the band between THR_DOWN and THR_UP

    // -------------------------------------------------------------------------
    // Hysteresis depth — must hold new condition for this many cycles
    // -------------------------------------------------------------------------
    localparam integer HYSTERESIS_CYCLES = 8;

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    logic [1:0] state;          // current FSM state
    logic [1:0] pending_state;  // state we are trying to transition to
    logic [3:0] hyst_count;     // hysteresis counter (0-8)

    // -------------------------------------------------------------------------
    // Combinational: what state does the current occupancy suggest?
    // -------------------------------------------------------------------------
    logic [1:0] suggested_state;
    always_comb begin
        if      (occupancy <= THR_IDLE) suggested_state = S_IDLE;
        else if (occupancy <= THR_DOWN) suggested_state = S_DOWN;
        else if (occupancy <  THR_UP  ) suggested_state = S_HOLD;
        else                            suggested_state = S_UP;
    end

    // -------------------------------------------------------------------------
    // FSM with hysteresis counter
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_HOLD;      // safe default — hold current freq
            pending_state <= S_HOLD;
            hyst_count    <= 4'd0;
            scale_cmd     <= CMD_HOLD;
            scale_valid   <= 1'b0;
        end else begin
            scale_valid <= 1'b0;  // default: no pulse

            if (suggested_state == state) begin
                // Already in the right state — reset counter and pending
                hyst_count    <= 4'd0;
                pending_state <= state;
            end else begin
                // Threshold crossed — check if same direction as pending
                if (suggested_state == pending_state) begin
                    // Same target — increment counter
                    if (hyst_count >= HYSTERESIS_CYCLES - 1) begin
                        // Counter expired — commit the transition
                        state         <= suggested_state;
                        pending_state <= suggested_state;
                        hyst_count    <= 4'd0;
                        scale_valid   <= 1'b1;  // pulse on transition
                        // Update command output
                        case (suggested_state)
                            S_IDLE: scale_cmd <= CMD_IDLE;
                            S_DOWN: scale_cmd <= CMD_DOWN;
                            S_HOLD: scale_cmd <= CMD_HOLD;
                            S_UP:   scale_cmd <= CMD_UP;
                        endcase
                    end else begin
                        hyst_count <= hyst_count + 1;
                    end
                end else begin
                    // Different target than pending — reset and start fresh
                    pending_state <= suggested_state;
                    hyst_count    <= 4'd1;
                end
            end
        end
    end

endmodule
