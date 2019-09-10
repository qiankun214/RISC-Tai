module mult_p2p_memory #(
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
	input [PORT_NUM - 1:0] dout_busy,
	output [DATA_WIDTH - 1:0]dout_data
);

wire [PORT_NUM - 1:0]inter_busy;

wire [PORT_NUM - 1:0]is_din = din_valid & (~din_busy);
wire [PORT_NUM - 1:0]is_dout = dout_valid & (~dout_busy);
wire [PORT_NUM - 1:0]is_dout_block = dout_valid & dout_busy;
wire [PORT_NUM - 1:0]is_block = is_din & ((~din_write_req & is_dout_block) | inter_busy);

genvar pi;
reg [PORT_NUM - 1:0]inter_busy_buffer;
reg [PORT_NUM - 1:0]block_sign;
reg [ADDR_WIDTH + DATA_WIDTH:0]block_data[PORT_NUM - 1:0];
wire [ADDR_WIDTH + DATA_WIDTH:0]din_data_s[PORT_NUM - 1:0];
generate
	for (pi = 0; pi < PORT_NUM; pi = pi + 1) begin:proc_pi

		assign din_data_s[pi] = {din_write_req[pi],din_addr[pi*ADDR_WIDTH +: ADDR_WIDTH],din_data[pi*DATA_WIDTH +: DATA_WIDTH]};

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				inter_busy_buffer[pi] <= 'b0;
			end else if(inter_busy[pi] && is_din[pi]) begin
				inter_busy_buffer[pi] <= 1'b1;
			end else if(!inter_busy[pi]) begin
				inter_busy_buffer[pi] <= 'b0;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				din_busy[pi] <= 'b0;
			end else if(is_block[pi]) begin
				din_busy[pi] <= 1'b1;
			end else if(!inter_busy[pi] && !dout_busy[pi])begin
				din_busy[pi] <= 'b0;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				block_sign[pi] <= 'b0;
			end else if(is_block[pi]) begin
				block_sign[pi] <= 1'b1;
			end else if(!dout_valid[pi] && !inter_busy[pi]) begin
				block_sign[pi] <= 'b0;
			end else if(is_dout[pi] && !inter_busy[pi]) begin //change here,add !interbusy
				block_sign[pi] <= 'b0;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				block_data[pi] <= 'b0;
			end else if(is_block[pi]) begin
				block_data[pi] <= din_data_s[pi];
			end
		end
	end
endgenerate

genvar si;
localparam S_THIS = 2'b00;
localparam S_LAST = 2'b01;
localparam S_BLOCK = 2'b10;
wire [PORT_NUM - 1:0] is_last_data = dout_valid & dout_busy;
wire [PORT_NUM - 1:0] is_block_data = (dout_valid & ~dout_busy & block_sign) | (~dout_valid & block_sign);
wire [PORT_NUM - 1:0] is_this_data = ~block_sign & ~inter_busy_buffer & is_din;
reg [ADDR_WIDTH + DATA_WIDTH:0] this_data [PORT_NUM - 1:0];
reg [ADDR_WIDTH + DATA_WIDTH:0] last_data [PORT_NUM - 1:0];
reg [1:0] last_switch [PORT_NUM - 1:0];
reg [PORT_NUM - 1:0] write_finish;
generate
	for (si = 0; si < PORT_NUM; si = si + 1) begin:proc_si
		
		always @ (*) begin
			if(is_last_data[si]) begin
				this_data[si] = last_data[si];
			end else if(is_block_data[si]) begin
				this_data[si] = block_data[si];
			end else if(is_this_data[si]) begin
				this_data[si] = din_data_s[si];
			end else begin
				case (last_switch[si])
					S_THIS:this_data[si] = din_data_s[si];
					S_LAST:this_data[si] = last_data[si];
					S_BLOCK:this_data[si] = block_data[si];
					default:this_data[si] = din_data_s[si];
				endcase
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				last_data[si] <= 1'b0;
			end else begin
				last_data[si] <= this_data[si];
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				last_switch[si] <= S_THIS;
			end else if(is_last_data[si]) begin
				last_switch[si] <= S_LAST;
			end else if(is_block_data[si]) begin
				last_switch[si] <= S_BLOCK;
			end else if(is_this_data[si]) begin
				last_switch[si] <= S_THIS;
			end
		end

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				dout_valid[si] <= 'b0;
			end else if(!this_data[si][DATA_WIDTH + ADDR_WIDTH]) begin
				if( (is_this_data[si] || (last_switch[si] == S_THIS)) && !inter_busy[si] && is_din[si]) begin
					dout_valid[si] <= 1'b1;
				end else if( is_block_data[si] && !inter_busy[si]) begin //change here inter_busy_buffer->inter_busy
					dout_valid[si] <= 1'b1;
				end else if( (is_block_data[si] || (last_switch[si] == S_BLOCK)) && inter_busy_buffer[si] && !inter_busy[si]) begin
					dout_valid[si] <= 1'b1;
				end else if(is_dout[si]) begin
					dout_valid[si] <= 1'b0;
				end
			end else if(is_dout[si]) begin
				dout_valid[si] <= 1'b0;
			end
		end
		
		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				write_finish[si] <= 1'b0;
			end else if(!inter_busy[si] && this_data[si][DATA_WIDTH + ADDR_WIDTH])begin
				write_finish[si] <= 1'b1;
			end else begin
				write_finish[si] <= 1'b0;
			end
		end
	end
endgenerate

// 
reg [ADDR_WIDTH + DATA_WIDTH:0] win_port;
integer i;
always @ (*) begin
	win_port = 'b0;
	for (i = 0; i < PORT_NUM; i = i + 1) begin
		if(inter_busy[i] == 1'b0) begin
			win_port = this_data[i];
		end
	end
end

sram_wrapper #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.DATA_WIDTH(DATA_WIDTH)
) u_simgle_port_sram (
	.clk(clk),    // Clock

	.addr(win_port[DATA_WIDTH+:ADDR_WIDTH]),
	.data(win_port[DATA_WIDTH - 1:0]),
	.write_req(win_port[DATA_WIDTH + ADDR_WIDTH]),

	.q(dout_data)
);

// token generate


wire [PORT_NUM - 1:0] request = din_valid | block_sign;
genvar ti;
wire [PORT_NUM - 1:0] token,token_c;
reg [PORT_NUM - 1:0] token_reg;
wire is_token_change = ((token_reg == 'b0) || ((token_reg & is_dout) != 'b0)) || ((token_reg & write_finish) != 'b0);
generate
	for (ti = 0; ti < PORT_NUM; ti = ti + 1) begin:proc_ti
		if(ti == 0) begin
			assign token_c[ti] = request[ti];
		end else begin
			assign token_c[ti] = (request[ti] && (request[ti - 1:0] == 'b0));
		end
		assign token[ti] = is_token_change?token_c[ti]:token_reg[ti];
		assign inter_busy[ti] = ~token[ti] && (token != 'b0);
	end
endgenerate
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		token_reg <= 'b0;
	end else if(is_token_change) begin
		token_reg <= token_c;
	end 
end

endmodule