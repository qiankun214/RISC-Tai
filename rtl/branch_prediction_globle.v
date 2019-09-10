module branch_prediction_globle#(
	parameter GLOBAL_HISTORY_WIDTH = 10
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// predict
	input predict_valid,
	output reg predict_result,

	// renew
	input renew_valid,
	input last_predict,
	input renew_result
);

localparam STRONG_JUMP = 2'b11;
localparam WEAK_JUMP = 2'b10;
localparam WEAK_NO_JUMP = 2'b01;
localparam STRONG_NOP_JUMP = 2'b00;

reg [GLOBAL_HISTORY_WIDTH - 1:0]global_history;
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		global_history <= 'b0;
	end else if(renew_valid) begin
		global_history <= {global_history[GLOBAL_HISTORY_WIDTH - 2:0],renew_result};
	end
end

reg [1:0] global_history_table [2 ** GLOBAL_HISTORY_WIDTH - 1:0];
genvar ti;
generate
	for (ti = 0; ti < 2 ** GLOBAL_HISTORY_WIDTH; ti = ti + 1) begin:proc_ti

		// wire predict_tmp = global_history_table[ti][1];

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				global_history_table[ti] <= STRONG_NOP_JUMP;
			end else if(renew_valid && (global_history == ti)) begin
				if(last_predict == renew_result) begin
					case (global_history_table[ti])
						STRONG_JUMP:global_history_table[ti] <= STRONG_JUMP;
						WEAK_JUMP:global_history_table[ti] <= STRONG_JUMP;
						STRONG_NOP_JUMP:global_history_table[ti] <= STRONG_NOP_JUMP;
						WEAK_NO_JUMP:global_history_table[ti] <= STRONG_NOP_JUMP;
						default:global_history_table[ti] <= STRONG_NOP_JUMP;
					endcase
				end else begin
					case (global_history_table[ti])
						STRONG_JUMP:global_history_table[ti] <= WEAK_JUMP;
						WEAK_JUMP:global_history_table[ti] <= STRONG_NOP_JUMP;
						STRONG_NOP_JUMP:global_history_table[ti] <= WEAK_NO_JUMP;
						WEAK_NO_JUMP:global_history_table[ti] <= STRONG_JUMP;
						default:global_history_table[ti] <= STRONG_NOP_JUMP;
					endcase
				end
			end
		end

	end

endgenerate

always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		predict_result <= 'b0;
	end else if(predict_valid) begin
		predict_result <= global_history_table[global_history][1];
	end
end

endmodule