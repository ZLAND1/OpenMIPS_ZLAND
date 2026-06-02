`include "define.v"

module hilo_reg(

	input	wire	clk,
	input	wire	rst,
	
	input wire				we,
	input wire[`RegBus]		hi_i,
	input wire[`RegBus]		lo_i,
	
	output reg[`RegBus]		hi_o,
	output reg[`RegBus]		lo_o,
	output reg[63:0]		io_seg_hilodata
	
);

	always @ (posedge clk) begin
		if (rst == `RstEnable) begin
					hi_o <= `ZeroWord;
					lo_o <= `ZeroWord;
		end else if((we == `WriteEnable)) begin
					hi_o <= hi_i;
					lo_o <= lo_i;
		end
	end

	always @ (*) begin
		io_seg_hilodata <= {hi_o, lo_o};
	end

endmodule