module i_cache #(
	parameter LABEL_WIDTH = 24,
	parameter GROUP_WIDTH = 1,
	parameter BIASE_WIDTH = 7,
	parameter DATA_BYTE_WIDTH = 3,
	parameter GROUP_LINK = 2
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	// addr p2p din
	input addr_valid,
	output reg addr_busy,
	input [LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH - 1:0]addr_data,

	// order p2p dout
	output reg order_valid,
	input order_busy,
	output reg [8 * (2 ** DATA_BYTE_WIDTH) - 1:0] order_data,

	// load addr p2p dout
	output reg load_addr_valid,
	input load_addr_busy,
	output reg [LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH - 1:0]load_addr_data,

	// load data p2p din
	input load_order_valid,
	output load_order_busy,
	input [8 * (2 ** DATA_BYTE_WIDTH) - 1:0]load_order_data
);

localparam ADDR_WIDTH = LABEL_WIDTH + GROUP_WIDTH + BIASE_WIDTH;

reg [1:0]mode,next_mode;
localparam NORM = 2'b00;
localparam READ = 2'b01;
localparam RETU = 2'b11;
wire inter_busy = (next_mode != NORM);
wire inter_busy_buffer = (mode != NORM);
wire is_mode_read = (mode == READ);
wire is_mode_retu = (mode == RETU);

wire is_cache_miss;
wire is_addr_din = addr_valid && !addr_busy;
wire is_block = is_addr_din && ((order_valid && order_busy) || inter_busy);

wire is_order_dout = order_valid && !order_busy;
 
wire is_load_din = load_order_valid && !load_order_busy;
wire is_load_aout = load_addr_valid && !load_addr_busy;
// controller

localparam COUNTE_WIDTH = BIASE_WIDTH - DATA_BYTE_WIDTH;
reg [COUNTE_WIDTH - 1:0] save_counte;
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		save_counte <= 'b0;
	end else if(is_mode_read && is_load_din) begin
		save_counte <= save_counte + 1'b1;
	end else if(is_mode_retu) begin
		save_counte <= 'b0;
	end
end

reg block_sign;
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		mode = NORM;
	end else begin
		mode = next_mode;
	end
end
always @ (*) begin
	case (mode)
		NORM:begin
			// if(is_cache_miss) begin
			if((is_addr_din || block_sign) && is_cache_miss) begin
				next_mode = READ;
			end else begin
				next_mode = NORM;
			end
		end
		READ:begin
			if((save_counte == 2 ** COUNTE_WIDTH - 1) && is_load_din) begin
				next_mode = RETU;
			end else begin
				next_mode = READ;
			end
		end
		RETU:next_mode = NORM;
		default : next_mode = NORM;
	endcase
end

// p2p addr din
reg [ADDR_WIDTH - 1:0]block_addr;

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		addr_busy <= 'b0;
	end else if(order_busy || is_block || block_sign || inter_busy) begin
		addr_busy <= 1'b1;
	end else begin
		addr_busy <= 1'b0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		block_sign <= 1'b0;
	end else if(is_block) begin
		block_sign <= 1'b1;
	end else if(!order_valid && !inter_busy) begin
		block_sign <= 1'b0;
	end else if(is_order_dout) begin
		block_sign <= 1'b0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		block_addr <= 'b0;
	end else if (is_block) begin
		block_addr <= addr_data;
	end
end

// switch addr
localparam S_THIS = 2'b00;
localparam S_LAST = 2'b01;
localparam S_BLOCK = 2'b10;
wire is_last_data = order_valid && order_busy;
wire is_block_data = (order_valid && !order_busy && block_sign) || (!order_valid && block_sign);
wire is_this_data = !order_busy && !inter_busy_buffer && is_addr_din;
reg [ADDR_WIDTH - 1:0] this_addr,last_addr;
reg [1:0] last_switch;

always @ (*) begin
	if(is_last_data) begin
		this_addr = last_addr;
	end else if(is_block_data) begin
		this_addr = block_addr;
	end else if(is_this_data) begin
		this_addr = addr_data;
	end else begin
		case (last_switch)
			S_THIS:this_addr = addr_data;
			S_LAST:this_addr = last_addr;
			S_BLOCK:this_addr = block_addr;
			default:this_addr = addr_data;
		endcase
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		last_addr <= 1'b0;
	end else begin
		last_addr <= this_addr;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		last_switch <= S_THIS;
	end else if(is_last_data) begin
		last_switch <= S_LAST;
	end else if(is_block_data) begin
		last_switch <= S_BLOCK;
	end else if(is_this_data) begin
		last_switch <= S_THIS;
	end
end

// cache hit
reg cache_valid[2 ** GROUP_WIDTH - 1:0][GROUP_LINK - 1:0];
reg [LABEL_WIDTH - 1:0]cache_label[2 ** GROUP_WIDTH - 1:0][GROUP_LINK - 1:0];
wire [GROUP_LINK - 1:0]cache_hit[2 ** GROUP_WIDTH - 1:0];
genvar ci,cj;
generate
	for (ci = 0; ci < 2 ** GROUP_WIDTH; ci = ci + 1) begin:ci_proc
		for (cj = 0; cj < GROUP_LINK; cj = cj + 1) begin:cj_proc
			assign cache_hit[ci][cj] = cache_valid[ci][cj] && (this_addr[ADDR_WIDTH - 1 -:LABEL_WIDTH] == cache_label[ci][cj]);
		end
	end
endgenerate
assign is_cache_miss = (cache_hit[ this_addr[BIASE_WIDTH +: GROUP_WIDTH] ] == 'b0);

// cache load
reg [LABEL_WIDTH + GROUP_WIDTH - 1:0] target_label;
reg [COUNTE_WIDTH - 1:0] load_counte;

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		load_counte <= 'b0;
	end else if(is_mode_read && is_load_aout) begin
		load_counte <= load_counte + 1'b1;
	end else if(is_mode_retu) begin
		load_counte <= 'b0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		target_label <= 'b0;
	end else if(next_mode == READ) begin
		target_label <= this_addr[ADDR_WIDTH - 1:BIASE_WIDTH];
	end
end

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		load_addr_valid <= 1'b0;
	end else if((load_counte == 2 ** COUNTE_WIDTH - 1) && is_load_aout) begin
		load_addr_valid <= 1'b0;
	end else if(mode == READ) begin
		load_addr_valid <= 1'b1;
	end
end

always @ (*) begin
	load_addr_data[ADDR_WIDTH - 1 -: LABEL_WIDTH+GROUP_WIDTH] = target_label;
	load_addr_data[BIASE_WIDTH - 1 : DATA_BYTE_WIDTH] = load_counte;
	load_addr_data[DATA_BYTE_WIDTH - 1:0] = 'b0;
	// load_addr_data = {target_label,load_counte,'b0};	
end


// sram
reg [GROUP_LINK - 1:0] rewrite_ram_num [2 ** GROUP_WIDTH - 1:0];
genvar ni;
generate
	for (ni = 0; ni < 2 ** GROUP_WIDTH; ni = ni + 1) begin:ni_proc
		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				rewrite_ram_num[ni][0] <= 1'b1;
				rewrite_ram_num[ni][GROUP_LINK - 1:1] <= 'b0;
			end else if(is_mode_retu && ((target_label[GROUP_WIDTH - 1:0] == ni))) begin
				rewrite_ram_num[ni] <= {rewrite_ram_num[ni][GROUP_LINK - 2:0],rewrite_ram_num[ni][GROUP_LINK - 1]};
			end
		end	
	end
endgenerate

reg [GROUP_LINK - 1:0]sram_write_req;
always @ (*) begin
	if(is_load_din) begin
		sram_write_req = rewrite_ram_num[ target_label[GROUP_WIDTH - 1:0] ];
	end else begin
		sram_write_req = 'b0;
	end
end

reg [GROUP_WIDTH + BIASE_WIDTH - DATA_BYTE_WIDTH - 1:0] sram_addr;
always @ (*) begin
	if(is_mode_read) begin
		sram_addr[BIASE_WIDTH - DATA_BYTE_WIDTH +: GROUP_WIDTH] = target_label[0 +: GROUP_WIDTH];
		sram_addr[BIASE_WIDTH - DATA_BYTE_WIDTH - 1 : 0] = save_counte;
	end else begin
		sram_addr = this_addr[GROUP_WIDTH + BIASE_WIDTH - 1:DATA_BYTE_WIDTH];
	end
end

assign load_order_busy = 1'b0;

wire [8 * (2 ** DATA_BYTE_WIDTH) - 1:0] sram_dout [GROUP_LINK - 1:0];
genvar si;
generate
	for (si = 0; si < GROUP_LINK; si = si + 1) begin:sram_generate
		sram_wrapper #(
			.ADDR_WIDTH(GROUP_WIDTH + BIASE_WIDTH - DATA_BYTE_WIDTH),
			.DATA_WIDTH(8 * (2 ** DATA_BYTE_WIDTH))
		) u_sram (
			.clk(clk),    // Clock

			.write_req(sram_write_req[si]),
			.addr(sram_addr),
			.data(load_order_data),

			.q(sram_dout[si])
		);
	end
endgenerate

genvar li,lj;
generate
	for (li = 0; li < 2 ** GROUP_WIDTH; li = li + 1) begin:cache_label_proc
		for (lj = 0; lj < GROUP_LINK; lj = lj + 1) begin:cache_valid_proc
			always @ (posedge clk or negedge rst_n) begin
				if(~rst_n) begin
					cache_label[li][lj] <= 'b0;
					cache_valid[li][lj] <= 1'b0;
				end else if((next_mode == RETU) && (target_label[GROUP_WIDTH - 1:0] == li) && rewrite_ram_num[li][lj]) begin
					cache_label[li][lj] <= target_label[GROUP_WIDTH +: LABEL_WIDTH];
					cache_valid[li][lj] <= 1'b1;
				end
			end
		end
	end
endgenerate

// p2p dout
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		order_valid <= 'b0;
	end else if( (is_this_data || (last_switch == S_THIS)) && !inter_busy && is_addr_din) begin
		order_valid <= 1'b1;
	end else if( is_block_data && !inter_busy_buffer) begin
		order_valid <= 1'b1;
	end else if((is_block_data || (last_switch == S_BLOCK)) && inter_busy_buffer && !inter_busy) begin
		order_valid <= 1'b1;
	end else if(is_order_dout) begin
		order_valid <= 'b0;
	end
end

integer i;
always @ (*) begin
	order_data = 'b0;
	for (i = 0; i < GROUP_LINK - 1; i = i + 1) begin
		if(cache_hit[ last_addr[BIASE_WIDTH+:GROUP_WIDTH] ][i]) begin
			order_data = sram_dout[i];
		end
	end
end

endmodule
