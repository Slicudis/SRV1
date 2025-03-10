module memory_stage(
    input clk, clk_en, sync_rst,

    // * From execute stage
    input [31:0] inst_in,
    input [4:0] ctr_word_in,
    input [31:0] alu_in,
    input [29:0] inc_pc_in,
    input [31:0] regfile_rs2,
    input [4:0] exe_regfile_rs1_address, //Current RS1 in the execute stage (Not buffered data)
    input [4:0] exe_regfile_rs2_address, //Current RS2 in the execute stage (Not buffered data)
    input exe_uses_rs1,
    input exe_uses_rs2,

    // * To previous stages
    output stall,

    // * To data memory
    output [31:0] data_out,
    output [29:0] address_out,
    output [3:0] mask,
    output bus_lock,
    output memory_mode,

    // * To writeback stage
    output [19:0] inst_u_imm_out,
    output [2:0] inst_fn3_out,
    output [4:0] rd_addr_out,
    output [2:0] ctr_out,
    output [31:0] alu_out,
    output [29:0] inc_pc_out
);

    //                                                                                                  //

    // * --- Instruction splitting ---

    wire [4:0] inst_rd_addr = inst_in[11:7];

    //                                                                                                  //

    // * Writeback buffers

    reg [19:0] inst_u_imm_buffer;
    assign inst_u_imm_out = inst_u_imm_buffer;

    reg [2:0] inst_fn3_buffer;
    assign inst_fn3_out = inst_fn3_buffer;

    reg [4:0] rd_addr_buffer;
    assign rd_addr_out = rd_addr_buffer;

    reg [2:0] ctr_buffer;
    assign ctr_out = ctr_buffer;

    reg [31:0] alu_buffer;
    assign alu_out = alu_buffer;

    reg [29:0] inc_pc_buffer;
    assign inc_pc_out = inc_pc_buffer;

    always_ff @(posedge clk) begin
        if(sync_rst) ctr_buffer <= 0;
        else if(clk_en) begin
            inst_u_imm_buffer <= inst_in[31:12];
            inst_fn3_buffer <= inst_in[14:12];
            rd_addr_buffer <= inst_rd_addr;
            ctr_buffer <= ctr_word_in[4:2];
            alu_buffer <= alu_in;
            inc_pc_buffer <= inc_pc_in;
        end
    end

    //                                                                                                  //

    // * --- Hazard detection & Pipeline stalls ---

    wire rs1_hazard = (inst_rd_addr == exe_regfile_rs1_address) && exe_uses_rs1; //Check for dependencies with RS1
    wire rs2_hazard = (inst_rd_addr == exe_regfile_rs2_address) && exe_uses_rs2; //Check for dependencies with RS2

    assign stall = ctr_word_in[2] && (rs1_hazard || rs2_hazard) && (|inst_rd_addr);
    
    //                                                                                                  //

    // * --- Memory access ---

    assign bus_lock = ctr_word_in[0];
    assign memory_mode = ctr_word_in[1];
    assign address_out = alu_in[31:2];

    output_adj output_adj(
        .data_in(regfile_rs2), .fn3(inst_in[14:12]), .addr_low(alu_in[1:0]),
        .data_out(data_out), .mask(mask)
    );

    /*
    EXAMPLE: sh t0, 0(t1)
    T0 = 0xFF50
    T1 = 0x2
    DATA_OUT = 0x50FF
    MASK = 0011
    */

    //                                                                                                  //

endmodule : memory_stage

module output_adj(
    input [31:0] data_in,
    input [2:0] fn3,
    input [1:0] addr_low,
    output logic [31:0] data_out,
    output logic [3:0] mask
);
    //Adjusts inputs from big to little endian

    always_comb begin : OutputAdj_and_Mask
        case(fn3)
        3'h0: case(addr_low)
            2'h0: begin data_out = {data_in[7:0], 24'h0}; mask = 4'b1000; end
            2'h1: begin data_out = {8'h0, data_in[7:0], 16'h0}; mask = 4'b0100; end
            2'h2: begin data_out = {16'h0, data_in[7:0], 8'h0}; mask = 4'b0010; end
            2'h3: begin data_out = {24'h0, data_in[7:0]}; mask = 4'b0001; end
            endcase
        3'h1: case(addr_low)
            2'h0, 2'h1: begin data_out = {data_in[7:0], data_in[15:8], 16'h0}; mask = 4'b1100; end
            2'h2, 2'h3: begin data_out = {16'h0, data_in[7:0], data_in[15:8]}; mask = 4'b0011; end
            endcase
        3'h2: begin data_out = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]}; mask = 4'b1111; end
        default: begin data_out = 0; mask = 0; end
        endcase
    end

endmodule : output_adj
