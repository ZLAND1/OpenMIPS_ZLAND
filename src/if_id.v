`include "define.v"

module if_id(

	input	wire	clk,
	input	wire	rst,
	
	input	wire[5:0]			stall,	//暂停信号
	input 	wire             	flush,	//异常信号

	input	wire[`InstAddrBus]	if_pc,
	input	wire[`InstBus]		if_inst,
	output	reg[`InstAddrBus]	id_pc,
	output	reg[`InstBus]		id_inst  
	
);

	always @ (posedge clk) begin
		if (rst == `RstEnable) begin
			id_pc <= `ZeroWord;
			id_inst <= `ZeroWord;
		end else if(flush == 1'b1 ) begin	//异常信号清楚流水线
			id_pc <= `ZeroWord;
			id_inst <= `ZeroWord;
		end else if(stall[1] == `Stop && stall[2] == `NoStop) begin
			id_pc <= `ZeroWord;
			id_inst <= `ZeroWord;	
	  	end else if(stall[1] == `NoStop) begin
			id_pc <= if_pc;
			id_inst <= if_inst;
		end
	end

endmodule

/*
	为了流水线
*/