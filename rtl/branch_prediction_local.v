module branch_prediction_local#(
	parameter LOW_ADDR_WIDTH = 8,
	parameter BRANCH_HISTORY_WIDTH = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// prediction
	input predict_valid,
	input [LOW_ADDR_WIDTH - 1:0] predict_addr,
	output reg predict_result,

	// renew
	input renew_valid,
	input last_predict,
	input [LOW_ADDR_WIDTH - 1:0] renew_addr,
	input renew_result
);

integer i;

// branch history table
reg [BRANCH_HISTORY_WIDTH - 1:0] branch_history_table [2 ** LOW_ADDR_WIDTH - 1:0];
genvar bi;
generate
	for (bi = 0; bi < 2 ** LOW_ADDR_WIDTH; bi = bi + 1) begin:bi_proc
		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				branch_history_table[bi] <= 'b0;
			end else if((predict_addr == bi) && renew_valid) begin
				branch_history_table[bi] <= {branch_history_table[bi][BRANCH_HISTORY_WIDTH - 2:0],renew_result};
			end
		end
	end	
endgenerate

localparam STRONG_JUMP = 2'b11;
localparam WEAK_JUMP = 2'b10;
localparam WEAK_NO_JUMP = 2'b01;
localparam STRONG_NOP_JUMP = 2'b00;

wire [BRANCH_HISTORY_WIDTH - 1:0] renew_pattern = branch_history_table[renew_addr];
reg [1:0] pattern_history_table [BRANCH_HISTORY_WIDTH - 1:0];
genvar pi;
generate
	for (pi = 0; pi < 2 ** BRANCH_HISTORY_WIDTH; pi = pi + 1) begin:pi_proc
		
		// wire predict_tmp = pattern_history_table[pi][1];

		always @ (posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				pattern_history_table[pi] <= STRONG_NOP_JUMP;
			end else if((renew_pattern == pi) && renew_valid) begin
				if(last_predict == renew_result) begin
					case (pattern_history_table[pi])
						STRONG_JUMP:pattern_history_table[pi] <= STRONG_JUMP;
						WEAK_JUMP:pattern_history_table[pi] <= STRONG_JUMP;
						STRONG_NOP_JUMP:pattern_history_table[pi] <= STRONG_NOP_JUMP;
						WEAK_NO_JUMP:pattern_history_table[pi] <= STRONG_NOP_JUMP;
						default:pattern_history_table[pi] <= STRONG_NOP_JUMP;
					endcase
				end else begin
					case (pattern_history_table[pi])
						STRONG_JUMP:pattern_history_table[pi] <= WEAK_JUMP;
						WEAK_JUMP:pattern_history_table[pi] <= STRONG_NOP_JUMP;
						STRONG_NOP_JUMP:pattern_history_table[pi] <= WEAK_NO_JUMP;
						WEAK_NO_JUMP:pattern_history_table[pi] <= STRONG_JUMP;
						default:pattern_history_table[pi] <= STRONG_NOP_JUMP;
					endcase
				end
			end
		end
	end
endgenerate

wire [BRANCH_HISTORY_WIDTH - 1:0] predict_pattern = pattern_history_table[predict_addr];
always @ (posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		predict_result <= 1'b0;
	end else if(predict_valid) begin
		predict_result <= pattern_history_table[predict_pattern][1];
	end
end

endmodule
