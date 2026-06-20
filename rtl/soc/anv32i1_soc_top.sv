module anv32i1_soc_top(
    input  logic clk_i,
    input  logic rst_n_i,

    output logic [3:0] debug_leds
);
    logic rst_i;
    logic [31:0] led_reg;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_we;

    assign rst_i = ~rst_n_i;
    assign debug_leds = ~led_reg[3:0];

    always_ff @(posedge clk_i) begin
        if (mem_addr == 32'h1000_0000 && (mem_we != 4'b0)) begin
            led_reg <= mem_wdata;
        end
    end

    anv32i1_top #(
        .INIT_FILE("src/prog")
    ) core (
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(1'b0), 
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i(32'b0),
        .instr_o(), 
        .pc_o(),
        .instr_valid_o(),
        .mem_rdata_i(32'b0),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_we(mem_we)
    );


endmodule
