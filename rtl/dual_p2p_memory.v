module dual_p2p_memory #(
	parameter ADDR_WIDTH = 8,
	parameter DATA_WIDTH = 64,
	parameter PORT_NUM = 2
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	input [PORT_NUM - 1:0] din_valid,
	output reg [PORT_NUM - 1:0] din_busy,
	input [PORT_NUM - 1:0] din_write_req,
	input [PORT_NUM * ADDR_WIDTH - 1:0] din_addr,
	input [PORT_NUM * DATA_WIDTH - 1:0] din_data,

	output reg [PORT_NUM - 1:0] dout_valid,
	input reg [PORT_NUM - 1:0] dout_busy,
	output [DATA_WIDTH - 1:0]dout_data
);

// token generate
wire [PORT_NUM - 1:0] request = din_valid;
wire [PORT_NUM - 1:0] token;
genvar ri;
generate
	for (ri = 0; ri < PORT_NUM; ri = ri + 1) begin:token_generater
		if(ri == 0) begin
			assign token[ri] = request[0];
		end else if(ri == 1) begin
			assign token[ri] = request[1] && !request[0];
		end else begin
			assign token[ri] = request[ri] && (request[ri-1:0] == 'b0);
		end
	end
endgenerate

// p2p input control
wire [PORT_NUM - 1:0] is_din;
wire [PORT_NUM - 1:0] is_block;
reg [PORT_NUM - 1:0] block_sign;

wire [ADDR_WIDTH + DATA_WIDTH:0] this_data [PORT_NUM - 1:0];
reg [ADDR_WIDTH + DATA_WIDTH:0] block_data [PORT_NUM - 1:0];
genvar ii;
generate
	for (ii = 0; ii < PORT_NUM; ii = ii + 1) begin:p2p_input_controller
		
		assign is_din[ii] = din_valid[ii] && !din_busy[ii];
		assign is_block[ii] = is_din[ii] && (dout_busy[ii] || !token[ii]);
		assign this_data[ii] = {din_write_req[ii],din_addr[ii*ADDR_WIDTH+:ADDR_WIDTH],din_data[ii*DATA_WIDTH+:DATA_WIDTH]};

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				din_busy[ii] <= 1'b0;
			end else if(dout_busy[ii] || is_block[ii] || block_sign[ii]) begin
				din_busy[ii] <= 1'b1;
			// end else if(!dout_busy[ii] && token[ii]) begin
			end else begin
				din_busy[ii] <= 1'b0;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				block_sign[ii] <= 1'b0;
			end else if(is_block[ii]) begin
				block_sign[ii] <= 1'b1;
			end else if(!dout_busy[ii] && token[ii]) begin
				block_sign[ii] <= 1'b0;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				block_data[ii] <= 'b0;
			end else if(is_block[ii]) begin
				block_data[ii] <= this_data[ii];
			end
		end
	end
endgenerate

// input switch
localparam S_THIS = 2'b00;
localparam S_LAST = 2'b01;
localparam S_BLOCK = 2'b10;
reg [1:0] last_mux_switch [PORT_NUM - 1:0];
reg [ADDR_WIDTH + DATA_WIDTH:0] last_data [PORT_NUM - 1:0];
reg [ADDR_WIDTH + DATA_WIDTH:0] switch_data [PORT_NUM - 1:0];
genvar si;
generate
	for (si = 0; si < PORT_NUM; si = si + 1) begin:input_switch
		
		wire switch_last_data = is_block[si];
		wire switch_block_data = !dout_busy[si] && block_sign[si] && token[si];
		wire switch_this_data = !dout_busy[si] && !block_sign[si] && token[si];

		always @ (*) begin
			if(switch_last_data) begin
				switch_data[si] = last_data[si];
			end else if(switch_block_data) begin
				switch_data[si] = block_data[si];
			end else if(switch_this_data) begin
				switch_data[si] = this_data[si];
			end else begin
				case (last_mux_switch[si])
					S_THIS:switch_data[si] = this_data[si];
					S_LAST:switch_data[si] = last_data[si];
					S_BLOCK:switch_data[si] = block_data[si];
					default:switch_data[si] = this_data[si];
				endcase
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				last_data[si] <= 'b0;
			end else begin
				last_data[si] <= switch_data[si];
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				last_mux_switch[si] <= S_THIS;
			end else if(switch_last_data) begin
				last_mux_switch[si] <= S_LAST;
			end else if(switch_block_data) begin
				last_mux_switch[si] <= S_BLOCK;
			end else if(switch_this_data) begin
				last_mux_switch[si] <= S_THIS;
			end
		end
	end
endgenerate

integer wi;
reg [ADDR_WIDTH + DATA_WIDTH:0] win_data;
always @ (*) begin
	win_data = 'b0;
	for (wi = PORT_NUM - 1; wi >= 0; wi = wi - 1) begin
		if(token[wi]) begin
			win_data = switch_data[wi];
		end
	end
end

wire [PORT_NUM - 1:0] is_dout;
genvar oi;
generate
	for (oi = 0; oi < PORT_NUM; oi = oi + 1) begin:p2p_out_generator
		
		assign is_dout[oi] = dout_valid[oi] && !dout_busy[oi];

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				dout_valid[oi] <= 1'b0;
			end else if((is_din[oi] || block_sign[oi]) && token[oi] && !switch_data[oi][DATA_WIDTH+ADDR_WIDTH]) begin
				dout_valid[oi] <= 1'b1;
			end else if(is_dout[oi]) begin
				dout_valid[oi] <= 1'b0;
			end
		end
		
	end
endgenerate

wire [ADDR_WIDTH + DATA_WIDTH:0] win_data_wire = win_data;
sram_wrapper #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.DATA_WIDTH(DATA_WIDTH)
) u_sram (
	.clk(clk),    // Clock

	.write_req(win_data_wire[ADDR_WIDTH+DATA_WIDTH]),
	.addr(win_data_wire[DATA_WIDTH+:ADDR_WIDTH]),
	.data(win_data_wire[DATA_WIDTH - 1:0]),

	.q(dout_data)
);

endmodule
