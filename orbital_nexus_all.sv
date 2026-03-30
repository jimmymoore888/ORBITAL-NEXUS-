// ============================================================
// ORBITAL NEXUS™ — FULL SINGLE-FILE IMPLEMENTATION
// Includes:
// - Core pipeline (10 stages)
// - SRAM model
// - Control system
// - Testbench
// ============================================================

// ============================================================
// SRAM MODEL
// ============================================================
module sram_model (
    input  logic        clk,
    input  logic        write,
    input  logic [19:0] addr,
    input  logic [63:0] data_in,
    output logic [63:0] data_out
);

    (* ram_style = "block" *)
    logic [63:0] mem [0:1048575]; // 1M x 64-bit (8MB)

    always_ff @(posedge clk) begin
        if (write) begin
            mem[addr] <= data_in;
        end
        data_out <= mem[addr];
    end

endmodule


// ============================================================
// ORBITAL NEXUS CORE
// ============================================================
module orbital_nexus_core (
    input  logic clk,
    input  logic rst,

    input  logic [63:0] data_in,
    input  logic [19:0] addr_in,
    input  logic write_in,
    input  logic [1:0]  qos_in,

    output logic [63:0] data_out
);

typedef struct packed {
    logic [63:0] data;
    logic [19:0] addr;
    logic write;
    logic [1:0] qos;
    logic [15:0] age;
    logic valid;
    logic parity;
    logic ecc_error;
} packet_t;

packet_t pipe [0:9];

// ---------------- GLOBAL STATE ----------------
logic [15:0] pressure;
logic [15:0] heat;
logic [15:0] integrity;

logic [63:0] anchor;
logic [7:0]  anchor_age;

// ---------------- MEMORY ----------------
logic [63:0] mem_data_out;

sram_model mem (
    .clk(clk),
    .write(pipe[6].write),
    .addr(pipe[6].addr),
    .data_in(pipe[6].data),
    .data_out(mem_data_out)
);

integer i;

always_ff @(posedge clk) begin
    if (rst) begin
        pressure   <= 0;
        heat       <= 0;
        integrity  <= 100;
        anchor     <= 0;
        anchor_age <= 0;

        for (i = 0; i < 10; i++) begin
            pipe[i].valid <= 0;
        end

    end else begin

        // ---------------- SHIFT ----------------
        for (i = 9; i > 0; i--) begin
            pipe[i] <= pipe[i-1];
        end

        // ---------------- INPUT ----------------
        pipe[0] <= '{
            data: data_in,
            addr: addr_in,
            write: write_in,
            qos: qos_in,
            age: 0,
            valid: 1,
            parity: 0,
            ecc_error: 0
        };

        // ---------------- STAGE 2 — LATENCY ----------------
        if (pipe[2].valid)
            pipe[2].age <= pipe[2].age + 1;

        // ---------------- STAGE 4 — COMPRESSION ----------------
        if (pipe[4].valid) begin
            if (integrity >= 50)
                pipe[4].data <= pipe[4].data - anchor;

            anchor_age <= anchor_age + 1;

            if (anchor_age > 50) begin
                anchor <= pipe[4].data;
                anchor_age <= 0;
            end
        end

        // ---------------- STAGE 5 — ECC GEN ----------------
        if (pipe[5].valid)
            pipe[5].parity <= ^pipe[5].data;

        // ---------------- STAGE 6 — MEMORY ----------------
        if (pipe[6].valid && !pipe[6].write)
            pipe[6].data <= mem_data_out;

        // ---------------- STAGE 7 — ECC CHECK ----------------
        if (pipe[7].valid) begin
            logic parity_check;
            parity_check = ^pipe[7].data;

            if (parity_check != pipe[7].parity) begin
                integrity <= (integrity > 5) ? integrity - 5 : 0;
                pipe[7].ecc_error <= 1;
            end else begin
                integrity <= (integrity < 65535) ? integrity + 1 : integrity;
                pipe[7].ecc_error <= 0;
            end
        end

        // ---------------- THERMAL ----------------
        heat <= (heat * 7 + 1) >> 3;

        // ---------------- PRESSURE ----------------
        pressure <= pressure + 1;

        // ---------------- CONTROL LOOP ----------------
        if ((pressure > 120) || (heat > 120) || (integrity < 40)) begin
            pressure <= (pressure > 2) ? pressure - 2 : 0;
            heat     <= (heat > 1) ? heat - 1 : 0;
        end
    end
end

assign data_out = pipe[9].data;

endmodule


// ============================================================
// TESTBENCH
// ============================================================
module testbench;

logic clk = 0;
always #5 clk = ~clk; // 100 MHz

logic rst;
logic [63:0] data_in;
logic [19:0] addr_in;
logic write_in;
logic [1:0] qos_in;
logic [63:0] data_out;

orbital_nexus_core dut (
    .clk(clk),
    .rst(rst),
    .data_in(data_in),
    .addr_in(addr_in),
    .write_in(write_in),
    .qos_in(qos_in),
    .data_out(data_out)
);

initial begin
    rst = 1;
    #20 rst = 0;

    repeat (1000) begin
        @(posedge clk);
        data_in  = $random;
        addr_in  = $random;
        write_in = $random;
        qos_in   = $random;
    end

    #100;
    $finish;
end

endmodule
