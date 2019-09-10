module tb_mult_port_memory (
);

parameter ADDR_WIDTH = 8;
parameter DATA_WIDTH = 64;
parameter PORT_NUM = 2;

logic clk;
logic rst_n;
logic [PORT_NUM - 1:0] din_valid;
logic [PORT_NUM - 1:0] din_busy;
logic [PORT_NUM - 1:0] din_write_req;
logic [PORT_NUM * ADDR_WIDTH - 1:0] din_addr;
logic [PORT_NUM * DATA_WIDTH - 1:0] din_data;

logic [PORT_NUM - 1:0] dout_valid;
logic [PORT_NUM - 1:0] dout_busy;
logic [DATA_WIDTH - 1:0] dout_data;

mult_p2p_memory #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.DATA_WIDTH(DATA_WIDTH),
	.PORT_NUM(PORT_NUM)
) dut (
	.clk(clk),    // Clock
	.rst_n(rst_n),  // Asynchronous reset active low

	.din_valid(din_valid),
	.din_busy(din_busy),
	.din_write_req(din_write_req),
	.din_addr(din_addr),
	.din_data(din_data),

	.dout_valid(dout_valid),
	.dout_busy(dout_busy),
	.dout_data(dout_data)
);

string dump_file;
initial begin
    `ifdef DUMP
        if($value$plusargs("FSDB=%s",dump_file))
            $display("dump_file = %s",dump_file);
        $fsdbDumpfile(dump_file);
        $fsdbDumpvars(0, tb_mult_port_memory);
        $fsdbDumpMDA(2 ** ADDR_WIDTH,dut);
    `endif

end

initial	 begin
	clk = 1'b0;
	forever begin
		#5 clk = ~clk;
	end
end

initial begin
	din_write_req = 'b0;
	dout_busy = 'b0;

	din_valid = 'b0;
	din_addr = 'b0;
	din_data = 'b0;

	rst_n = 1'b1;
	#1 rst_n = 1'b0;
	#1 rst_n = 1'b1;

end

class p2p_din;

	integer port_num;

	function new (num);
		this.port_num = num;
	endfunction

	task init();
		@(posedge clk);
		din_addr[port_num*ADDR_WIDTH+:ADDR_WIDTH] = 'b0;
		din_data[port_num*DATA_WIDTH+:DATA_WIDTH] = 'b0;
		din_write_req[port_num] = 'b0;
		din_valid[port_num] = 1'b0;
		@(posedge clk);
	endtask : init

	task p2p_din_data(int addr,int data=0,logic write=0);
		din_addr[port_num*ADDR_WIDTH+:ADDR_WIDTH] = addr;
		din_data[port_num*DATA_WIDTH+:DATA_WIDTH] = data;
		din_write_req[port_num] = write;
		din_valid[port_num] = 1'b1;
		do begin
			@(posedge clk);
		end while(din_busy[port_num] == 1'b1);
		din_valid[port_num] = 1'b0;
		din_write_req[port_num] = 1'b0;
	endtask : p2p_din_data

endclass : p2p_din

task monitor_p2p_out(input integer port_num);
	if(dout_valid[port_num] && !dout_busy[port_num]) begin
		$display("Port:%0d:get %0x",port_num,dout_data);
	end
endtask : monitor_p2p_out

initial begin
	p2p_din port0;
	port0 = new(0);
	repeat(20) @(negedge clk);
	port0.init();
	for (int i = 0; i < 16; i++) begin
		port0.p2p_din_data(i,i,1);
	end
	repeat(64) @(negedge clk);
	for (int i = 0; i < 16; i++) begin
		port0.p2p_din_data(i);
	end

	repeat(64) @(negedge clk);
	$finish;
end

initial begin
	p2p_din port1;
	port1 = new(1);
	repeat(6) @(negedge clk);
	port1.init();
	for (int i = 0; i < 16; i++) begin
		port1.p2p_din_data(16+i,i,1);
	end
	repeat(50) @(negedge clk);
	for (int i = 0; i < 16; i++) begin
		port1.p2p_din_data(16+i);
	end
	repeat(64) @(negedge clk);
	$finish;
end

// initial begin
// 	#10000 $finish;
// end

// initial begin
// 	dout_busy[0] = 1'b0;
// 	dout_busy[1] = 1'b1;

// 	#500 dout_busy[1] = 1'b0;
// end

initial begin
	dout_busy[0] = 1'b0;
	dout_busy[1] = 1'b0;
	forever begin
		@(posedge clk);
		for (int i = 0; i < PORT_NUM; i++) begin
			monitor_p2p_out(i);
			dout_busy[i] = $urandom_range(0,1);
		end
	end
end

endmodule