module branch_prediction_switch #(
	parameter GLOBAL_HISTORY_WIDTH = 10
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	// predict
	input predict_valid,
	output reg predict_result,

	// renew
	input renew_valid,
	input renew_local_result,
	input renew_global_result,
	input renew_switch_result,
	input renew_result
	
);

reg [GLOBAL_HISTORY_WIDTH - 1:0] global_history;
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		global_history <= 'b0;
	end else if(renew_valid) begin
		global_history <= {global_history[GLOBAL_HISTORY_WIDTH - 2:0],renew_result};
	end
end

localparam STRONG_GLOBAL = 2'b11;
localparam WEAK_GLOBAL = 2'b10;
localparam WEAK_LOCAL = 2'b01;
localparam STRONG_LOCAL = 2'b00;
reg [1:0] global_history_table [2 ** GLOBAL_HISTORY_WIDTH - 1:0];
wire is_wrong_global = renew_switch_result && (renew_global_result != renew_result) && (renew_local_result == renew_result);
wire is_wrong_local = !renew_switch_result && (renew_global_result == renew_result) && (renew_local_result != renew_result);
genvar ti;
generate
	for (ti = 0; ti < 2 ** GLOBAL_HISTORY_WIDTH; ti = ti + 1) begin:proc_ti
		// wire predict_tmp = global_history_table[ti][1];

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				global_history_table[ti] <= STRONG_LOCAL;
			end else if(renew_valid && (global_history == ti)) begin
				if(is_wrong_local || is_wrong_global) begin
					case (global_history_table[ti])
						STRONG_GLOBAL:global_history_table[ti] <= WEAK_GLOBAL;
						WEAK_GLOBAL:global_history_table[ti] <= STRONG_LOCAL;
						STRONG_LOCAL:global_history_table[ti] <= WEAK_LOCAL;
						WEAK_LOCAL:global_history_table[ti] <= STRONG_LOCAL;
						default:global_history_table[ti] <= STRONG_LOCAL;
					endcase
				end else begin
					case (global_history_table[ti])
						STRONG_GLOBAL:global_history_table[ti] <= STRONG_GLOBAL;
						WEAK_GLOBAL:global_history_table[ti] <= STRONG_GLOBAL;
						STRONG_LOCAL:global_history_table[ti] <= STRONG_LOCAL;
						WEAK_GLOBAL:global_history_table[ti] <= STRONG_LOCAL;
						default:global_history_table[ti] <= STRONG_LOCAL;
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