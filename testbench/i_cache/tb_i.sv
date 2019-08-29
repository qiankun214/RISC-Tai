module tb_i (
);

parameter LABEL_WIDTH = 24;
parameter GROUP_WIDTH = 1;
parameter BIASE_WIDTH = 7;
parameter DATA_BYTE_WIDTH = 3;
parameter GROUP_LINK = 2;

logic clk;
logic rst_n;
logic addr_valid;
logic addr_busy;
logic [LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH - 1:0]addr_data;
logic order_valid;
logic order_busy;
logic [8 * (2 ** DATA_BYTE_WIDTH) - 1:0] order_data;
logic load_addr_valid;
logic load_addr_busy;
logic [LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH - 1:0]load_addr_data;
logic load_order_valid;
logic load_order_busy;
logic [8 * (2 ** DATA_BYTE_WIDTH) - 1:0]load_order_data;

i_cache #(
	.LABEL_WIDTH(LABEL_WIDTH),
	.GROUP_WIDTH(GROUP_WIDTH),
	.BIASE_WIDTH(BIASE_WIDTH),
	.DATA_BYTE_WIDTH(DATA_BYTE_WIDTH),
	.GROUP_LINK(GROUP_LINK)
) dut (
	.clk(clk),    // Clock
	.rst_n(rst_n),  // Asynchronous reset active low

	// addr p2p din
	.addr_valid(addr_valid),
	.addr_busy(addr_busy),
	.addr_data(addr_data),

	// order p2p dout
	.order_valid(order_valid),
	.order_busy(order_busy),
	.order_data(order_data),

	// load addr p2p dout
	.load_addr_valid(load_addr_valid),
	.load_addr_busy(load_addr_busy),
	.load_addr_data(load_addr_data),

	// load data p2p din
	.load_order_valid(load_order_valid),
	.load_order_busy(load_order_busy),
	.load_order_data(load_order_data)
);

initial begin
	clk = 1'b0;
	forever begin
		#5 clk = ~clk;
	end
end

initial begin
	rst_n = 1'b1;
	#1 rst_n = 1'b0;
	#1 rst_n = 1'b1;
end

initial begin
	load_addr_busy = 1'b0;
	load_order_valid = 1'b1;
	load_order_data = 'b0;
	@(posedge clk);
	forever begin
		@(posedge clk);
		load_order_valid = 1'b0;
		if(load_addr_valid && !load_addr_busy) begin
			load_order_valid = 1'b1;
			load_order_data = load_addr_data;
		end
		load_addr_busy = 'b0;
		// load_addr_busy = $urandom_range(0,1);
	end
end

task ain(logic [LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH - 1:0] addr);
	addr_data = addr;
	addr_valid = 1'b1;
	do begin
		@(posedge clk);
	end while(addr_busy);
	addr_valid = 1'b0;
endtask : ain

initial begin
	order_busy = 1'b0;
	forever begin
		@(posedge clk);
		if(order_valid && !order_busy) begin
			$display("ORDER:get %0d",order_data);
			// $stop;
		end
		#1 order_busy = 1'b0;
		// #1 order_busy = $urandom_range(0,1);
	end
end

initial begin
	addr_valid = 1'b0;
	addr_data = 'b0;
	repeat(8) @(posedge clk);
	for (int i = 0; i < 16; i++) begin
		ain(10+i);
	end
	for (int i = 0; i < 16; i++) begin
		ain(130+i);
	end
	repeat(200) @ (posedge clk);
	$stop;
end
endmodule
