`include "define.v"

module pc_reg(

	input	wire	clk,
	input	wire	rst,

	//控制信号
	input	wire[5:0]			stall,
	input 	wire               	flush,
	input 	wire[`RegBus]      	new_pc,

	//跳转信号
	//来自译码阶段的信息
	input wire                    branch_flag_i,
	input wire[`RegBus]           branch_target_address_i,

	output	reg[`InstAddrBus]	pc,
	output	reg		ce
	
);

	always @ (posedge clk) begin
		if (rst == `RstEnable) begin 
			pc <= 32'h0;
		end else if (ce == `ChipDisable) begin
			pc <= 32'h0;
		end else begin
			if(flush == 1'b1) begin
				pc <= new_pc;
			end else if (stall[0] == `NoStop) begin
			if(branch_flag_i == `Branch) begin
					pc <= branch_target_address_i;
			end else begin			
				pc <= pc + 4'h4;
			end
		end
		end
	end
	
	always @ (posedge clk) begin
		if (rst == `RstEnable) begin 	
			ce <= `ChipDisable;
		end else begin 				
			ce <= `ChipEnable;
		end
	end

endmodule


