module sram_wrapper #(
	parameter ADDR_WIDTH = 8,
	parameter DATA_WIDTH = 64
) (
	input clk,    // Clock

	input [ADDR_WIDTH - 1:0] addr,
	input [DATA_WIDTH - 1:0] data,
	input write_req,

	output reg[DATA_WIDTH - 1:0] q
);

reg [DATA_WIDTH - 1:0] ram [2 ** ADDR_WIDTH - 1:0];
always @ (posedge clk) begin
	if(write_req) begin
		ram[addr] <= data;
	end
end

always @ (posedge clk) begin
	q <= ram[addr];
	// q <= {(DATA_WIDTH - ADDR_WIDTH)'(0),addr}; // for test
end

endmodule
