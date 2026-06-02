`include "define.v"

module ex(

	input	wire	rst,
	
	//送到执行阶段的信息
	input	wire[`AluOpBus]		aluop_i,
	input	wire[`AluSelBus]	alusel_i,
	input	wire[`RegBus]		reg1_i,
	input	wire[`RegBus]		reg2_i,
	input	wire[`RegAddrBus]	wd_i,
	input	wire 				wreg_i,
	input 	wire[`RegBus]     	inst_i,
	input 	wire[31:0]        	excepttype_i,
	input 	wire[`RegBus]     	current_inst_address_i,

	//HI、LO寄存器的值
	input	wire[`RegBus]	hi_i,
	input	wire[`RegBus]	lo_i,

	//回写阶段的指令是否要写HI、LO，用于检测HI、LO的数据相关
	input	wire[`RegBus]	wb_hi_i,
	input	wire[`RegBus]	wb_lo_i,
	input	wire	wb_whilo_i,
	
	//访存阶段的指令是否要写HI、LO，用于检测HI、LO的数据相关
	input	wire[`RegBus]	mem_hi_i,
	input	wire[`RegBus]	mem_lo_i,
	input	wire			mem_whilo_i,

	input wire[`DoubleRegBus]     hilo_temp_i,
	input wire[1:0]               cnt_i,
	
	//与除法模块相连
	input wire[`DoubleRegBus]     div_result_i,
	input wire                    div_ready_i,

	//是否转移、以及link address
	input wire[`RegBus]           link_address_i,
	input wire                    is_in_delayslot_i,

	//访存阶段的指令是否要写CP0，用来检测数据相关
  	input wire                    mem_cp0_reg_we,
	input wire[4:0]               mem_cp0_reg_write_addr,
	input wire[`RegBus]           mem_cp0_reg_data,
	
	//回写阶段的指令是否要写CP0，用来检测数据相关
  	input wire                    wb_cp0_reg_we,
	input wire[4:0]               wb_cp0_reg_write_addr,
	input wire[`RegBus]           wb_cp0_reg_data,

	//与CP0相连，读取其中CP0寄存器的值
	input wire[`RegBus]           cp0_reg_data_i,
	output reg[4:0]               cp0_reg_read_addr_o,

	//向下一流水级传递，用于写CP0中的寄存器
	output reg                    cp0_reg_we_o,
	output reg[4:0]               cp0_reg_write_addr_o,
	output reg[`RegBus]           cp0_reg_data_o,
	
	output	reg[`RegAddrBus]	wd_o,
	output	reg					wreg_o,
	output	reg[`RegBus]		wdata_o,

	output	reg[`RegBus]		hi_o,
	output	reg[`RegBus]		lo_o,
	output	reg					whilo_o,

	output 	reg[`DoubleRegBus]     	hilo_temp_o,
	output 	reg[1:0]               	cnt_o,

	output 	reg[`RegBus]           	div_opdata1_o,
	output 	reg[`RegBus]           	div_opdata2_o,
	output	reg                    	div_start_o,
	output 	reg                    	signed_div_o,

	//下面新增的几个输出是为加载、存储指令准备的
	output	wire[`AluOpBus]        	aluop_o,
	output 	wire[`RegBus]          	mem_addr_o,
	output 	wire[`RegBus]         	reg2_o,

	output 	wire[31:0]             excepttype_o,
	output 	wire                   is_in_delayslot_o,
	output 	wire[`RegBus]          current_inst_address_o,

	output	reg						stallreq
	
);

	reg[`RegBus] logicout;			//逻辑运算结果
	reg[`RegBus] shiftres;			//移位运算结果	
	reg[`RegBus] moveres;			//移动地址结果	
	reg[`RegBus] arithmeticres;		//算术运算结果
	reg[`DoubleRegBus] mulres;		//乘法结果
	reg[`RegBus] HI;				
	reg[`RegBus] LO;
	wire[`RegBus] reg2_i_mux;		//操作数2的补码
	wire[`RegBus] reg1_i_not;		//操作数1的反码
	wire[`RegBus] result_sum;		//加法结果
	wire ov_sum;					//保存溢出
	wire reg1_eq_reg2;				//第一个数是否等于第二个数
	wire reg1_lt_reg2;				//第一个数是否小于第二个数
	wire[`RegBus] opdata1_mult;		//乘法被乘数
	wire[`RegBus] opdata2_mult;		//乘法乘数
	wire[`DoubleRegBus] hilo_temp;	//乘法结果的高低位，临时存储，64位
	reg[`DoubleRegBus] hilo_temp1;
	reg stallreq_for_madd_msub;		//累乘加减控制信号
	reg stallreq_for_div;			//除法控制信号
	reg trapassert;					//异常控制信号
	reg ovassert;					//溢出控制信号

	// 1. 仅识别SW指令+IO低12位偏移（0x0000~0x0FFF）
	// 识别IO相关的SW/LW指令（LW op=100011）
	wire is_sw      = (aluop_i == `EXE_SW_OP);
	wire is_lw      = (aluop_i == `EXE_LW_OP);
	wire is_io_mem  = (is_sw | is_lw) && (inst_i[15:12] == 4'h0);

	//aluop_o传递到访存阶段，用于加载、存储指令
	assign aluop_o = aluop_i;

	// 立即数扩展：IO-SW/LW都拼接0x7000，其他标准扩展
	wire [31:0] imm32 = is_io_mem ? {16'h7000, inst_i[15:0]} : {{16{inst_i[15]}},inst_i[15:0]};

	
	//mem_addr传递到访存阶段，是加载、存储指令对应的存储器地址
	assign mem_addr_o = reg1_i + imm32;

	//将两个操作数也传递到访存阶段，也是为记载、存储指令准备的
	assign reg2_o = reg2_i;

	assign excepttype_o = {excepttype_i[31:12],ovassert,trapassert,excepttype_i[9:8],8'h00};
  
	assign is_in_delayslot_o = is_in_delayslot_i;
	assign current_inst_address_o = current_inst_address_i;
	
	//逻辑运算集中处理
	always @ (*) begin
		if(rst == `RstEnable) begin
			logicout <= `ZeroWord;
		end else begin
			case (aluop_i)
				`EXE_OR_OP:			begin
					logicout <= reg1_i | reg2_i;
				end
				`EXE_AND_OP:		begin
					logicout <= reg1_i & reg2_i;
				end
				`EXE_NOR_OP:		begin
					logicout <= ~(reg1_i |reg2_i);
				end
				`EXE_XOR_OP:		begin
					logicout <= reg1_i ^ reg2_i;
				end
				default:				begin
					logicout <= `ZeroWord;
				end
			endcase
		end  
	end     
	
	//移位运算集中处理
	always @ (*) begin
		if(rst == `RstEnable) begin
			shiftres <= `ZeroWord;
		end else begin
			case (aluop_i)
				`EXE_SLL_OP:			
					begin
						shiftres <= reg2_i << reg1_i[4:0];
					end
				`EXE_SRL_OP:		
					begin
						shiftres <= reg2_i >> reg1_i[4:0];
					end
				`EXE_SRA_OP:		
					begin
						shiftres <= ({32{reg2_i[31]}} << (6'd32-{1'b0, reg1_i[4:0]})) 
													| reg2_i >> reg1_i[4:0];
					end
				default:				
					begin
						shiftres <= `ZeroWord;
					end
			endcase
		end    
	end    

	//操作数2的补码，在有符号数乘法以及有符号数比较时用到，其余为原码
	assign reg2_i_mux = ((aluop_i == `EXE_SUB_OP) || (aluop_i == `EXE_SUBU_OP) ||
											 (aluop_i == `EXE_SLT_OP)|| (aluop_i == `EXE_TLT_OP) ||
	                       (aluop_i == `EXE_TLTI_OP) || (aluop_i == `EXE_TGE_OP) ||
	                       (aluop_i == `EXE_TGEI_OP)) 
											 ? (~reg2_i)+1 : reg2_i;

	//加减法两个部分通过补码统一处理
	//第一是减法，操作数一为正，补码就是原码，操作数二为负，求补码后求和就是结果
	//第二是加法，直接加，因为立即数也是符号扩展后的
	assign result_sum = reg1_i + reg2_i_mux;										 

	//计算溢出公式
	assign ov_sum = ((!reg1_i[31] && !reg2_i_mux[31]) && result_sum[31]) ||
									((reg1_i[31] && reg2_i_mux[31]) && (!result_sum[31]));  
	
	//比较前是否大于后，用于比较指令的结果
	assign reg1_lt_reg2 = ((aluop_i == `EXE_SLT_OP) || (aluop_i == `EXE_TLT_OP) ||
	                       (aluop_i == `EXE_TLTI_OP) || (aluop_i == `EXE_TGE_OP) ||
	                       (aluop_i == `EXE_TGEI_OP)) ?
												 ((reg1_i[31] && !reg2_i[31]) || 
												 (!reg1_i[31] && !reg2_i[31] && result_sum[31])||
			                   (reg1_i[31] && reg2_i[31] && result_sum[31]))
			                   :	(reg1_i < reg2_i);
  
  	//操作数一的取反，实现计数‘1’的功能
	assign reg1_i_not = ~reg1_i;
	
	//算术运算集中判断						
	always @ (*) begin
		if(rst == `RstEnable) begin
			arithmeticres <= `ZeroWord; 
		end else begin
			case (aluop_i)
				`EXE_SLT_OP, `EXE_SLTU_OP:		
					begin
						arithmeticres <= reg1_lt_reg2 ;
					end
				`EXE_ADD_OP, `EXE_ADDU_OP, `EXE_ADDI_OP, `EXE_ADDIU_OP:		
					begin
						arithmeticres <= result_sum; 
					end
				`EXE_SUB_OP, `EXE_SUBU_OP:		
					begin
						arithmeticres <= result_sum; 
					end		
				`EXE_CLZ_OP:	//从高位开始if，如果是1，则输出0，如果是0，则下一位，下一位时是1时的输出为2，依次类推
					begin
						arithmeticres <= reg1_i[31] ? 0 : reg1_i[30] ? 1 : reg1_i[29] ? 2 :
														reg1_i[28] ? 3 : reg1_i[27] ? 4 : reg1_i[26] ? 5 :
														reg1_i[25] ? 6 : reg1_i[24] ? 7 : reg1_i[23] ? 8 : 
														reg1_i[22] ? 9 : reg1_i[21] ? 10 : reg1_i[20] ? 11 :
														reg1_i[19] ? 12 : reg1_i[18] ? 13 : reg1_i[17] ? 14 : 
														reg1_i[16] ? 15 : reg1_i[15] ? 16 : reg1_i[14] ? 17 : 
														reg1_i[13] ? 18 : reg1_i[12] ? 19 : reg1_i[11] ? 20 :
														reg1_i[10] ? 21 : reg1_i[9] ? 22 : reg1_i[8] ? 23 : 
														reg1_i[7] ? 24 : reg1_i[6] ? 25 : reg1_i[5] ? 26 : 
														reg1_i[4] ? 27 : reg1_i[3] ? 28 : reg1_i[2] ? 29 : 
														reg1_i[1] ? 30 : reg1_i[0] ? 31 : 32 ;
					end
				`EXE_CLO_OP:		
					begin
						arithmeticres <= (reg1_i_not[31] ? 0 : reg1_i_not[30] ? 1 : reg1_i_not[29] ? 2 :
														reg1_i_not[28] ? 3 : reg1_i_not[27] ? 4 : reg1_i_not[26] ? 5 :
														reg1_i_not[25] ? 6 : reg1_i_not[24] ? 7 : reg1_i_not[23] ? 8 : 
														reg1_i_not[22] ? 9 : reg1_i_not[21] ? 10 : reg1_i_not[20] ? 11 :
														reg1_i_not[19] ? 12 : reg1_i_not[18] ? 13 : reg1_i_not[17] ? 14 : 
														reg1_i_not[16] ? 15 : reg1_i_not[15] ? 16 : reg1_i_not[14] ? 17 : 
														reg1_i_not[13] ? 18 : reg1_i_not[12] ? 19 : reg1_i_not[11] ? 20 :
														reg1_i_not[10] ? 21 : reg1_i_not[9] ? 22 : reg1_i_not[8] ? 23 : 
														reg1_i_not[7] ? 24 : reg1_i_not[6] ? 25 : reg1_i_not[5] ? 26 : 
														reg1_i_not[4] ? 27 : reg1_i_not[3] ? 28 : reg1_i_not[2] ? 29 : 
														reg1_i_not[1] ? 30 : reg1_i_not[0] ? 31 : 32) ;
					end
				default:				
					begin
						arithmeticres <= `ZeroWord;
					end
			endcase
		end
	end

	always @ (*) begin
		if(rst == `RstEnable) begin
			trapassert <= `TrapNotAssert;
		end else begin
			trapassert <= `TrapNotAssert;
			case (aluop_i)
				`EXE_TEQ_OP, `EXE_TEQI_OP:		begin
					if( reg1_i == reg2_i ) begin
						trapassert <= `TrapAssert;
					end
				end
				`EXE_TGE_OP, `EXE_TGEI_OP, `EXE_TGEIU_OP, `EXE_TGEU_OP:		begin
					if( ~reg1_lt_reg2 ) begin
						trapassert <= `TrapAssert;
					end
				end
				`EXE_TLT_OP, `EXE_TLTI_OP, `EXE_TLTIU_OP, `EXE_TLTU_OP:		begin
					if( reg1_lt_reg2 ) begin
						trapassert <= `TrapAssert;
					end
				end
				`EXE_TNE_OP, `EXE_TNEI_OP:		begin
					if( reg1_i != reg2_i ) begin
						trapassert <= `TrapAssert;
					end
				end
				default:				begin
					trapassert <= `TrapNotAssert;
				end
			endcase
		end
	end

  	//取得乘法操作的操作数，如果是有符号除法且操作数是负数，那么取反加一
	assign opdata1_mult = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULT_OP))
													&& (reg1_i[31] == 1'b1)) ? (~reg1_i + 1) : reg1_i;

	assign opdata2_mult = (((aluop_i == `EXE_MUL_OP) || (aluop_i == `EXE_MULT_OP))
														&& (reg2_i[31] == 1'b1)) ? (~reg2_i + 1) : reg2_i;		

	assign hilo_temp = opdata1_mult * opdata2_mult;																				

	always @ (*) begin
		if(rst == `RstEnable) begin
			mulres <= {`ZeroWord,`ZeroWord};
		end else if ((aluop_i == `EXE_MULT_OP) || (aluop_i == `EXE_MUL_OP))begin
			if(reg1_i[31] ^ reg2_i[31] == 1'b1) begin
				mulres <= ~hilo_temp + 1;
			end else begin
			  	mulres <= hilo_temp;
			end
		end else begin
				mulres <= hilo_temp;
		end
	end

  	//得到最新的HI、LO寄存器的值，此处要解决指令数据相关问题
	always @ (*) begin
		if(rst == `RstEnable) begin
			{HI,LO} <= {`ZeroWord,`ZeroWord};
		end else if(mem_whilo_i == `WriteEnable) begin
			{HI,LO} <= {mem_hi_i,mem_lo_i};
		end else if(wb_whilo_i == `WriteEnable) begin
			{HI,LO} <= {wb_hi_i,wb_lo_i};
		end else begin
			{HI,LO} <= {hi_i,lo_i};			
		end
	end	

	//MFHI、MFLO、MOVN、MOVZ指令
	always @ (*) begin
		if(rst == `RstEnable) 
			begin
				moveres <= `ZeroWord;
			end else 
			begin
				moveres <= `ZeroWord;
					case (aluop_i)
						`EXE_MFHI_OP:		
							begin
								moveres <= HI;
							end
						`EXE_MFLO_OP:		
							begin
								moveres <= LO;
							end
						`EXE_MOVZ_OP:		
							begin
								moveres <= reg1_i;
							end
						`EXE_MOVN_OP:		
							begin
								moveres <= reg1_i;
							end
						`EXE_MFC0_OP:		
							begin
								cp0_reg_read_addr_o <= inst_i[15:11];
								moveres <= cp0_reg_data_i;
								if( mem_cp0_reg_we == `WriteEnable &&mem_cp0_reg_write_addr == inst_i[15:11] ) 
									begin
										moveres <= mem_cp0_reg_data;
								end else if( wb_cp0_reg_we == `WriteEnable &&wb_cp0_reg_write_addr == inst_i[15:11] ) 
									begin
										moveres <= wb_cp0_reg_data;
									end
							end	  
						default : 
							begin
							end
					endcase
	  		end
	end

	//流水线暂停，累乘加减以及除法指令
	always @ (*) 
		begin
			stallreq = stallreq_for_madd_msub || stallreq_for_div;
		end

	//DIV、DIVU指令	
	always @ (*) begin
		if(rst == `RstEnable) begin
			stallreq_for_div <= `NoStop;
	    div_opdata1_o <= `ZeroWord;
			div_opdata2_o <= `ZeroWord;
			div_start_o <= `DivStop;
			signed_div_o <= 1'b0;
		end else begin
			stallreq_for_div <= `NoStop;
	    div_opdata1_o <= `ZeroWord;
			div_opdata2_o <= `ZeroWord;
			div_start_o <= `DivStop;
			signed_div_o <= 1'b0;	
			case (aluop_i) 
				`EXE_DIV_OP:		
					begin
						if(div_ready_i == `DivResultNotReady) begin
						div_opdata1_o <= reg1_i;
							div_opdata2_o <= reg2_i;
							div_start_o <= `DivStart;
							signed_div_o <= 1'b1;
							stallreq_for_div <= `Stop;
						end else if(div_ready_i == `DivResultReady) begin
						div_opdata1_o <= reg1_i;
							div_opdata2_o <= reg2_i;
							div_start_o <= `DivStop;
							signed_div_o <= 1'b1;
							stallreq_for_div <= `NoStop;
						end else begin						
						div_opdata1_o <= `ZeroWord;
							div_opdata2_o <= `ZeroWord;
							div_start_o <= `DivStop;
							signed_div_o <= 1'b0;
							stallreq_for_div <= `NoStop;
						end					
					end
				`EXE_DIVU_OP:		
					begin
						if(div_ready_i == `DivResultNotReady) begin
						div_opdata1_o <= reg1_i;
							div_opdata2_o <= reg2_i;
							div_start_o <= `DivStart;
							signed_div_o <= 1'b0;
							stallreq_for_div <= `Stop;
						end else if(div_ready_i == `DivResultReady) begin
						div_opdata1_o <= reg1_i;
							div_opdata2_o <= reg2_i;
							div_start_o <= `DivStop;
							signed_div_o <= 1'b0;
							stallreq_for_div <= `NoStop;
						end else begin						
						div_opdata1_o <= `ZeroWord;
							div_opdata2_o <= `ZeroWord;
							div_start_o <= `DivStop;
							signed_div_o <= 1'b0;
							stallreq_for_div <= `NoStop;
						end					
					end
				default: begin
				end
			endcase
		end
	end	

	always @ (*) 
		begin
			//写入寄存器使能信号传递
			wd_o <= wd_i;

			if(((aluop_i == `EXE_ADD_OP) || (aluop_i == `EXE_ADDI_OP) || 
				(aluop_i == `EXE_SUB_OP)) && (ov_sum == 1'b1)) 
				begin
					wreg_o <= `WriteDisable; //先判断是否为需要判断溢出的指令，若溢出则无结果
					ovassert <= 1'b1;
				end else begin
					wreg_o <= wreg_i;
					ovassert <= 1'b0;
				end
			case ( alusel_i ) //通过计算大类返回结果，点对点给出结果
				`EXE_RES_LOGIC:		
					begin
						wdata_o <= logicout;		//逻辑运算结果
					end
				`EXE_RES_SHIFT:		
					begin
						wdata_o <= shiftres;		//移位运算结果
					end	 	
				`EXE_RES_MOVE:		
					begin
						wdata_o <= moveres;			//移动地址结果
					end	 	
				`EXE_RES_ARITHMETIC:	
					begin
						wdata_o <= arithmeticres;	//算术运算结果
					end
				`EXE_RES_MUL:		
					begin
						wdata_o <= mulres[31:0];	//乘法运算低32位结果
					end
				`EXE_RES_JUMP_BRANCH:	
					begin
						wdata_o <= link_address_i;
					end	 	
				default:					
					begin
						wdata_o <= `ZeroWord;
					end
			endcase
		end	

	//乘除法结果存入，HI、LO寄存器
	always @ (*) begin
		if(rst == `RstEnable) begin
			whilo_o <= `WriteDisable;
			hi_o <= `ZeroWord;
			lo_o <= `ZeroWord;		
		end else if((aluop_i == `EXE_MULT_OP) || (aluop_i == `EXE_MULTU_OP)) begin
			whilo_o <= `WriteEnable;
			hi_o <= mulres[63:32];
			lo_o <= mulres[31:0];			
		end else if((aluop_i == `EXE_MADD_OP) || (aluop_i == `EXE_MADDU_OP)) begin
			whilo_o <= `WriteEnable;
			hi_o <= hilo_temp1[63:32];
			lo_o <= hilo_temp1[31:0];
		end else if((aluop_i == `EXE_MSUB_OP) || (aluop_i == `EXE_MSUBU_OP)) begin
			whilo_o <= `WriteEnable;
			hi_o <= hilo_temp1[63:32];
			lo_o <= hilo_temp1[31:0];		
		end else if((aluop_i == `EXE_DIV_OP) || (aluop_i == `EXE_DIVU_OP)) begin
			whilo_o <= `WriteEnable;
			hi_o <= div_result_i[63:32];
			lo_o <= div_result_i[31:0];							
		end else if(aluop_i == `EXE_MTHI_OP) begin
			whilo_o <= `WriteEnable;
			hi_o <= reg1_i;
			lo_o <= LO;
		end else if(aluop_i == `EXE_MTLO_OP) begin
			whilo_o <= `WriteEnable;
			hi_o <= HI;
			lo_o <= reg1_i;
		end else begin
			whilo_o <= `WriteDisable;
			hi_o <= `ZeroWord;
			lo_o <= `ZeroWord;
		end				
	end		

	always @ (*) begin
		if(rst == `RstEnable) begin
			cp0_reg_write_addr_o <= 5'b00000;
			cp0_reg_we_o <= `WriteDisable;
			cp0_reg_data_o <= `ZeroWord;
		end else if(aluop_i == `EXE_MTC0_OP) begin
			cp0_reg_write_addr_o <= inst_i[15:11];
			cp0_reg_we_o <= `WriteEnable;
			cp0_reg_data_o <= reg1_i;
	  	end else begin
			cp0_reg_write_addr_o <= 5'b00000;
			cp0_reg_we_o <= `WriteDisable;
			cp0_reg_data_o <= `ZeroWord;
		end				
	end

endmodule