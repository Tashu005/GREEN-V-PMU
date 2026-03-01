// =============================================================================
// GREEN-V PROJECT — Step 5 of 5 (System Integration)
// Module  : cmu_top.sv
// Purpose : Top-level wrapper linking Monitor, Lookahead, Controller, and Divider.
// =============================================================================

module cmu_top (
    input  logic        clk_in,         // High-speed master clock (500MHz)
    input  logic        rst_n,
    
    // CPU Interface
    input  logic [31:0] inst_window,    // For Lookahead
    input  logic        inst_valid,
    input  logic [6:0]  ibuf_occupancy, // For Monitor (0-64)
    
    // PMU / SoC Outputs
    output logic        clk_out,        // Scaled clock to CPU
    output logic [2:0]  volt_ctrl       // To external PMIC
);

    // Internal Signal Interconnects
    logic [1:0] monitor_cmd;
    logic       monitor_valid;
    
    logic [1:0] lookahead_cmd;
    logic       spike_detected;
    
    logic [2:0] freq_sel;
    logic       change_req;
    logic       change_ack;
    logic [2:0] current_sel;

    // 1. Reactive Path: Instruction Buffer Monitor
    // (Assumes your teammate used these port names)
    ibuf_monitor monitor_inst (
        .clk            (clk_in),
        .rst_n          (rst_n),
        .ibuf_fill      (ibuf_occupancy),
        .scale_cmd      (monitor_cmd),
        .scale_valid    (monitor_valid)
    );

    // 2. Predictive Path: Instruction Lookahead Unit
    lookahead_unit lookahead_inst (
        .clk            (clk_in),
        .rst_n          (rst_n),
        .inst_window    (inst_window),
        .inst_valid     (inst_valid),
        .lookahead_cmd  (lookahead_cmd),
        .spike_detected (spike_detected)
    );

    // 3. The Brain: DVFS Controller
    dvfs_controller controller_inst (
        .clk            (clk_in),
        .rst_n          (rst_n),
        .scale_cmd      (monitor_cmd),
        .scale_valid    (monitor_valid),
        .lookahead_cmd  (lookahead_cmd),
        .spike_detected (spike_detected),
        .freq_sel       (freq_sel),
        .change_req     (change_req),
        .change_ack     (change_ack),
        .current_sel    (current_sel),
        .volt_ctrl      (volt_ctrl)
    );

    // 4. The Actuator: Clock Divider
    clk_divider divider_inst (
        .clk_in         (clk_in),
        .rst_n          (rst_n),
        .freq_sel       (freq_sel),
        .change_req     (change_req),
        .clk_out        (clk_out),
        .change_ack     (change_ack)
    );

    // Track the current selection for the controller's FSM
    assign current_sel = freq_sel; 

endmodule