`include "define.v"

module id(

	input	wire	rst,
	input	wire[`InstAddrBus]	pc_i,
	input	wire[`InstBus]		inst_i,

	//处于执行阶段的指令的一些信息，用于解决load相关
  	input 	wire[`AluOpBus]		ex_aluop_i,

	//处于执行阶段的指令要写入的目的寄存器信息
	input	wire	ex_wreg_i,
	input	wire[`RegBus]	ex_wdata_i,
	input	wire[`RegAddrBus]	ex_wd_i,
	
	//处于访存阶段的指令要写入的目的寄存器信息
	input	wire	mem_wreg_i,
	input	wire[`RegBus]	mem_wdata_i,
	input	wire[`RegAddrBus]	mem_wd_i,
	
	input	wire[`RegBus]	reg1_data_i,
	input	wire[`RegBus]	reg2_data_i,

	//如果上一条指令是转移指令，那么下一条指令在译码的时候is_in_delayslot为true
	input wire                	is_in_delayslot_i,

	//送到regfile的信息
	output	reg					reg1_read_o,
	output	reg					reg2_read_o,     
	output	reg[`RegAddrBus]	reg1_addr_o,
	output	reg[`RegAddrBus]	reg2_addr_o, 	      
	
	//送到执行阶段的信息
	output	reg[`AluOpBus]		aluop_o,
	output	reg[`AluSelBus]		alusel_o,
	output	reg[`RegBus]		reg1_o,
	output	reg[`RegBus]		reg2_o,	
	output	reg[`RegAddrBus]	wd_o,		//目的寄存器地址
	output	reg					wreg_o,		//是否写入目的寄存器
	output wire[`RegBus]     	inst_o,

	//下一条指令是否在延迟槽中
	output 	reg                    next_inst_in_delayslot_o,
	
	output 	reg                	branch_flag_o,
	output 	reg[`RegBus]      	branch_target_address_o,       
	output 	reg[`RegBus]     	link_addr_o,
	output 	reg               	is_in_delayslot_o,

	output 	wire[31:0]        	excepttype_o,
  	output 	wire[`RegBus]    	current_inst_address_o,

	output	wire				stallreq
);

	wire[5:0] op = inst_i[31:26];
	wire[4:0] op2 = inst_i[10:6];
	wire[5:0] op3 = inst_i[5:0];
	wire[4:0] op4 = inst_i[20:16];
	reg[`RegBus]	imm;
	reg instvalid;

	wire[`RegBus] pc_plus_8;
	wire[`RegBus] pc_plus_4;
	wire[`RegBus] imm_sll2_signedext;

	reg stallreq_for_reg1_loadrelate;
	reg stallreq_for_reg2_loadrelate;
	wire pre_inst_is_load;  
	reg excepttype_is_syscall;
  	reg excepttype_is_eret;
	
	assign pc_plus_8 = pc_i + 8;		//后第二条指令地址
	assign pc_plus_4 = pc_i +4;			//后一条指令地址
	assign imm_sll2_signedext = {{14{inst_i[15]}}, inst_i[15:0], 2'b00};
	assign stallreq = stallreq_for_reg1_loadrelate | stallreq_for_reg2_loadrelate;
	assign pre_inst_is_load = ((ex_aluop_i == `EXE_LB_OP) || 
														(ex_aluop_i == `EXE_LBU_OP)||
														(ex_aluop_i == `EXE_LH_OP) ||
														(ex_aluop_i == `EXE_LHU_OP)||
														(ex_aluop_i == `EXE_LW_OP) ||
														(ex_aluop_i == `EXE_LWR_OP)||
														(ex_aluop_i == `EXE_LWL_OP)||
														(ex_aluop_i == `EXE_LL_OP) ||
														(ex_aluop_i == `EXE_SC_OP)) ? 1'b1 : 1'b0;

	assign inst_o = inst_i;

	//exceptiontype的低8bit留给外部中断，第9bit表示是否是syscall指令
  	//第10bit表示是否是无效指令，第11bit表示是否是trap指令
  	assign excepttype_o = {19'b0,excepttype_is_eret,2'b0,instvalid, excepttype_is_syscall,8'b0};
  
	assign current_inst_address_o = pc_plus_4;
  
	always @ (*) begin	
		if (rst == `RstEnable) begin
			aluop_o <= `EXE_NOP_OP;
			alusel_o <= `EXE_RES_NOP;
			wd_o <= `NOPRegAddr;
			wreg_o <= `WriteDisable;
			instvalid <= `InstValid;
			reg1_read_o <= 1'b0;
			reg2_read_o <= 1'b0;
			reg1_addr_o <= `NOPRegAddr;
			reg2_addr_o <= `NOPRegAddr;
			imm <= 32'h0;			
			link_addr_o <= `ZeroWord;
			branch_target_address_o <= `ZeroWord;
			branch_flag_o <= `NotBranch;
			next_inst_in_delayslot_o <= `NotInDelaySlot;
			excepttype_is_syscall <= `False_v;
			excepttype_is_eret <= `False_v;
	  	end else begin
			aluop_o <= `EXE_NOP_OP;
			alusel_o <= `EXE_RES_NOP;
			wd_o <= inst_i[15:11];
			wreg_o <= `WriteDisable;
			instvalid <= `InstInvalid;	   
			reg1_read_o <= 1'b0;
			reg2_read_o <= 1'b0;
			reg1_addr_o <= inst_i[25:21];
			reg2_addr_o <= inst_i[20:16];		
			imm <= `ZeroWord;
			link_addr_o <= `ZeroWord;
			branch_target_address_o <= `ZeroWord;
			branch_flag_o <= `NotBranch;
			next_inst_in_delayslot_o <= `NotInDelaySlot;
			excepttype_is_syscall <= `False_v;
			excepttype_is_eret <= `False_v;
		case (op)
		    `EXE_SPECIAL_INST:	begin
		    	case (op2)
		    		5'b00000:	begin
		    			case (op3)
		    				`EXE_OR:	
								begin
		    						wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_OR_OP;
		  							alusel_o <= `EXE_RES_LOGIC; 	
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;	
								end  
		    				`EXE_AND:	
								begin
		    						wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_AND_OP;
		  							alusel_o <= `EXE_RES_LOGIC;	  
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;	
		  							instvalid <= `InstValid;	
								end  	
		    				`EXE_XOR:	
								begin
		    						wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_XOR_OP;
		  							alusel_o <= `EXE_RES_LOGIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;	
		  							instvalid <= `InstValid;	
								end  				
		    				`EXE_NOR:	
								begin
		    						wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_NOR_OP;
		  							alusel_o <= `EXE_RES_LOGIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;	
		  							instvalid <= `InstValid;	
								end 
							`EXE_SLLV: 
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SLL_OP;
		  							alusel_o <= `EXE_RES_SHIFT;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;	
								end 
							`EXE_SRLV: 
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SRL_OP;
		  							alusel_o <= `EXE_RES_SHIFT;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;	
								end 					
							`EXE_SRAV:
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SRA_OP;
		  							alusel_o <= `EXE_RES_SHIFT;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;			
		  						end
							`EXE_MFHI: 
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_MFHI_OP;
		  							alusel_o <= `EXE_RES_MOVE;   
									reg1_read_o <= 1'b0;	
									reg2_read_o <= 1'b0;
		  							instvalid <= `InstValid;	
								end
							`EXE_MFLO:
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_MFLO_OP;
		  							alusel_o <= `EXE_RES_MOVE;   
									reg1_read_o <= 1'b0;	
									reg2_read_o <= 1'b0;
		  							instvalid <= `InstValid;	
								end
							`EXE_MTHI: 
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_MTHI_OP;
		  							reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b0; 
									instvalid <= `InstValid;	
								end
							`EXE_MTLO: 
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_MTLO_OP;
		  							reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b0; 
									instvalid <= `InstValid;	
								end
							`EXE_MOVN: 
								begin
									aluop_o <= `EXE_MOVN_OP;
									alusel_o <= `EXE_RES_MOVE;   
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;
								 	if(reg2_o != `ZeroWord) begin
	 									wreg_o <= `WriteEnable;
	 								end else begin
	 									wreg_o <= `WriteDisable;
	 								end
								end
							`EXE_MOVZ: 
								begin
									aluop_o <= `EXE_MOVZ_OP;
		  							alusel_o <= `EXE_RES_MOVE;   
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
		  							instvalid <= `InstValid;
								 	if(reg2_o == `ZeroWord) begin
	 									wreg_o <= `WriteEnable;
	 								end else begin
	 									wreg_o <= `WriteDisable;
	 								end		  							
								end	
							`EXE_SLT: //比较运算，比较结果放在目的寄存器，有符号数的比较
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SLT_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_SLTU: //无符号数比较
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SLTU_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_ADD: //寄存器加法指令，进行溢出判断如果异常则终止
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_ADD_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_ADDU: //不判断溢出的加法指令
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_ADDU_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_SUB: //寄存器减法指令，进行溢出判断如果异常则终止
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SUB_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_SUBU: //不判断溢出
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_SUBU_OP;
									alusel_o <= `EXE_RES_ARITHMETIC;		
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1;
									instvalid <= `InstValid;	
								end
							`EXE_MULT: //有符号数乘法指令，结果存放在HI和LO中，高32位存放在HI寄存器中，低32位存放在LO寄存器中
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_MULT_OP;
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1; 
									instvalid <= `InstValid;	
								end
							`EXE_MULTU: //无符号数相乘
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_MULTU_OP;
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1; 
									instvalid <= `InstValid;	
								end
							`EXE_DIV: 	//除法运算，结果存在HILO寄存器，需要读取寄存器
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_DIV_OP;
		  							reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1; 
									instvalid <= `InstValid;	
								end
							`EXE_DIVU: 
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_DIVU_OP;
		  							reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b1; 
									instvalid <= `InstValid;	
								end
							`EXE_JR: 
								begin
									wreg_o <= `WriteDisable;		
									aluop_o <= `EXE_JR_OP;
		  							alusel_o <= `EXE_RES_JUMP_BRANCH;   
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b0;
		  							link_addr_o <= `ZeroWord;
									branch_target_address_o <= reg1_o;
									branch_flag_o <= `Branch;
			            			next_inst_in_delayslot_o <= `InDelaySlot;
			           			 	instvalid <= `InstValid;	
								end
							`EXE_JALR: 
								begin
									wreg_o <= `WriteEnable;		
									aluop_o <= `EXE_JALR_OP;
									alusel_o <= `EXE_RES_JUMP_BRANCH;   
									reg1_read_o <= 1'b1;	
									reg2_read_o <= 1'b0;
									wd_o <= inst_i[15:11];
									link_addr_o <= pc_plus_8;
									branch_target_address_o <= reg1_o;
									branch_flag_o <= `Branch;
									next_inst_in_delayslot_o <= `InDelaySlot;
									instvalid <= `InstValid;	
								end											
						    default:	
								begin
						    	end
						  endcase
						 end
						default: 
							begin
							end
					endcase
				case (op3)
					`EXE_TEQ: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TEQ_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b0;	
							reg2_read_o <= 1'b0;
							instvalid <= `InstValid;
						end
					`EXE_TGE: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TGE_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b1;	
							reg2_read_o <= 1'b1;
							instvalid <= `InstValid;
						end		
					`EXE_TGEU: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TGEU_OP;
							alusel_o <= `EXE_RES_NOP;  
							reg1_read_o <= 1'b1;	
							reg2_read_o <= 1'b1;
							instvalid <= `InstValid;
						end	
					`EXE_TLT: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TLT_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b1;	
							reg2_read_o <= 1'b1;
							instvalid <= `InstValid;
						end
					`EXE_TLTU: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TLTU_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b1;	
							reg2_read_o <= 1'b1;
							instvalid <= `InstValid;
						end	
					`EXE_TNE: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_TNE_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b1;	
							reg2_read_o <= 1'b1;
							instvalid <= `InstValid;
						end
					`EXE_SYSCALL: 
						begin
							wreg_o <= `WriteDisable;		
							aluop_o <= `EXE_SYSCALL_OP;
							alusel_o <= `EXE_RES_NOP;   
							reg1_read_o <= 1'b0;	
							reg2_read_o <= 1'b0;
							instvalid <= `InstValid; 
							excepttype_is_syscall<= `True_v;
						end							 																					
					default:	
						begin
						end	
				endcase
			end							  
		  	`EXE_ORI:			
				begin                        //ORI指令
		  			wreg_o <= `WriteEnable;
					aluop_o <= `EXE_OR_OP;
		  			alusel_o <= `EXE_RES_LOGIC;
					reg1_read_o <= 1'b1;
					reg2_read_o <= 1'b0;	  	
					imm <= {16'h0, inst_i[15:0]};
					wd_o <= inst_i[20:16];
					instvalid <= `InstValid;	
		  		end
			`EXE_ANDI:			
				begin                        //ANDI指令
					wreg_o <= `WriteEnable;	
					aluop_o <= `EXE_AND_OP;
					alusel_o <= `EXE_RES_LOGIC;
					reg1_read_o <= 1'b1;
					reg2_read_o <= 1'b0;	  	
					imm <= {16'h0, inst_i[15:0]};	
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end	 	
		  	`EXE_XORI:						//XORI指令
				begin
		  			wreg_o <= `WriteEnable;	
					aluop_o <= `EXE_XOR_OP;
		  			alusel_o <= `EXE_RES_LOGIC;	
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {16'h0, inst_i[15:0]};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end	 		
		  	`EXE_LUI:	//置高位，立即数左移16位，送到目的寄存器中		
				begin
		  			wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_OR_OP;
					alusel_o <= `EXE_RES_LOGIC; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {inst_i[15:0], 16'h0};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end
			`EXE_SLTI:	//立即数符号扩展后与rs寄存器的值进行有符号数比较		
				begin
		  			wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_SLT_OP;
		  			alusel_o <= `EXE_RES_ARITHMETIC; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {{16{inst_i[15]}}, inst_i[15:0]};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end
			`EXE_SLTIU:	//进行无符号数比较		
				begin
		  			wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_SLTU_OP;
		  			alusel_o <= `EXE_RES_ARITHMETIC; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {{16{inst_i[15]}}, inst_i[15:0]};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end
			`EXE_ADDI:	//立即数符号扩展加法指令，计算溢出		
				begin
		  			wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_ADDI_OP;
		  			alusel_o <= `EXE_RES_ARITHMETIC; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {{16{inst_i[15]}}, inst_i[15:0]};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end
			`EXE_ADDIU:	//立即数符号扩展加法指令，不计算溢出		
				begin
		  			wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_ADDIU_OP;
		  			alusel_o <= `EXE_RES_ARITHMETIC; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					imm <= {{16{inst_i[15]}}, inst_i[15:0]};		
					wd_o <= inst_i[20:16];		  	
					instvalid <= `InstValid;	
				end
			`EXE_J:		//无条件跳转指令
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_J_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b0;	
					reg2_read_o <= 1'b0;
					link_addr_o <= `ZeroWord;
					branch_target_address_o <= {pc_plus_4[31:28], inst_i[25:0], 2'b00};
					branch_flag_o <= `Branch;
					next_inst_in_delayslot_o <= `InDelaySlot;		  	
					instvalid <= `InstValid;	
			end
			`EXE_JAL:	//调用指令，保存返回地址到31号寄存器中，并将下下条指令放在延迟槽中
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_JAL_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b0;	
					reg2_read_o <= 1'b0;
					wd_o <= 5'b11111;	
					link_addr_o <= pc_plus_8 ;
					branch_target_address_o <= {pc_plus_4[31:28], inst_i[25:0], 2'b00};
					branch_flag_o <= `Branch;
					next_inst_in_delayslot_o <= `InDelaySlot;		  	
					instvalid <= `InstValid;	
			end
			`EXE_BEQ:	//比较两个寄存器的值，如果相等则跳转		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_BEQ_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1;
					instvalid <= `InstValid;	
					if(reg1_o == reg2_o) begin
						branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
						branch_flag_o <= `Branch;
						next_inst_in_delayslot_o <= `InDelaySlot;		  	
					end
			end
			`EXE_BGTZ:	//比较一个寄存器的值，如果大于0则跳转		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_BGTZ_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;
					instvalid <= `InstValid;	
					if((reg1_o[31] == 1'b0) && (reg1_o != `ZeroWord)) begin
						branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
						branch_flag_o <= `Branch;
						next_inst_in_delayslot_o <= `InDelaySlot;		  	
					end
			end
			`EXE_BLEZ:	//比较一个寄存器的值，如果小于等于0则跳转		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_BLEZ_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;
					instvalid <= `InstValid;	
					if((reg1_o[31] == 1'b1) || (reg1_o == `ZeroWord)) begin
						branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
						branch_flag_o <= `Branch;
						next_inst_in_delayslot_o <= `InDelaySlot;		  	
					end
				end
			`EXE_BNE:	//比较两个寄存器的值，如果不相等则跳转		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_BLEZ_OP;
					alusel_o <= `EXE_RES_JUMP_BRANCH; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1;
					instvalid <= `InstValid;	
					if(reg1_o != reg2_o) begin
						branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
						branch_flag_o <= `Branch;
						next_inst_in_delayslot_o <= `InDelaySlot;		  	
					end
				end
			`EXE_LB:	//加载一个字节数据		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LB_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LBU:	//加载一个字节数据，不带符号扩展		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LBU_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LH:	//加载一个半字数据		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LH_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LHU:	//加载一个半字数据，不带符号扩展		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LHU_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LW:	//加载一个字数据		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LW_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LL:	//加载一个长字数据		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LL_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b0;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LWL:	//加载一个字数据，低位在前		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LWL_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_LWR:	//加载一个字数据，高位在前		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_LWR_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
				end
			`EXE_SB:	//存储一个字节数据		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_SB_OP;
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1; 
					instvalid <= `InstValid;	
		  		alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_SH:	//存储一个半字数据		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_SH_OP;
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1; 
					instvalid <= `InstValid;	
		  		alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_SW:	//存储一个字数据		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_SW_OP;
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1; 
					instvalid <= `InstValid;	
		  		alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_SWL:	//存储一个字数据，低位在前		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_SWL_OP;
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1; 
					instvalid <= `InstValid;	
		  		alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_SWR:	//存储一个字数据，高位在前		
				begin
					wreg_o <= `WriteDisable;		
					aluop_o <= `EXE_SWR_OP;
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1; 
					instvalid <= `InstValid;	
		  		alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_SC:	//存储一个字数据，比较并交换		
				begin
					wreg_o <= `WriteEnable;		
					aluop_o <= `EXE_SC_OP;
					alusel_o <= `EXE_RES_LOAD_STORE; 
					reg1_read_o <= 1'b1;	
					reg2_read_o <= 1'b1;	  	
					wd_o <= inst_i[20:16]; 
					instvalid <= `InstValid;	
					alusel_o <= `EXE_RES_LOAD_STORE; 
				end
			`EXE_REGIMM_INST:		
				begin
					case (op4)
						`EXE_BGEZ:	
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_BGEZ_OP;
								alusel_o <= `EXE_RES_JUMP_BRANCH; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;
								instvalid <= `InstValid;	
								if(reg1_o[31] == 1'b0) begin
									branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
									branch_flag_o <= `Branch;
									next_inst_in_delayslot_o <= `InDelaySlot;		  	
								end
							end
						`EXE_BGEZAL:		
							begin
								wreg_o <= `WriteEnable;		
								aluop_o <= `EXE_BGEZAL_OP;
								alusel_o <= `EXE_RES_JUMP_BRANCH; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;
								link_addr_o <= pc_plus_8; 
								wd_o <= 5'b11111;  	instvalid <= `InstValid;
								if(reg1_o[31] == 1'b0) begin
									branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
									branch_flag_o <= `Branch;
									next_inst_in_delayslot_o <= `InDelaySlot;
								end
							end
						`EXE_BLTZ:		
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_BGEZAL_OP;
								alusel_o <= `EXE_RES_JUMP_BRANCH; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;
								instvalid <= `InstValid;	
								if(reg1_o[31] == 1'b1) begin
									branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
									branch_flag_o <= `Branch;
									next_inst_in_delayslot_o <= `InDelaySlot;		  	
								end
							end
						`EXE_BLTZAL:		
							begin
								wreg_o <= `WriteEnable;		
								aluop_o <= `EXE_BGEZAL_OP;
								alusel_o <= `EXE_RES_JUMP_BRANCH; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;
								link_addr_o <= pc_plus_8;	
								wd_o <= 5'b11111; instvalid <= `InstValid;
								if(reg1_o[31] == 1'b1) begin
									branch_target_address_o <= pc_plus_4 + imm_sll2_signedext;
									branch_flag_o <= `Branch;
									next_inst_in_delayslot_o <= `InDelaySlot;
								end
							end
						`EXE_TEQI:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TEQI_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end
						`EXE_TGEI:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TGEI_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end
						`EXE_TGEIU:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TGEIU_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end
						`EXE_TLTI:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TLTI_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end
						`EXE_TLTIU:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TLTIU_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end
						`EXE_TNEI:			
							begin
								wreg_o <= `WriteDisable;		
								aluop_o <= `EXE_TNEI_OP;
								alusel_o <= `EXE_RES_NOP; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								imm <= {{16{inst_i[15]}}, inst_i[15:0]};		  	
								instvalid <= `InstValid;	
							end	
						default:	
							begin
							end
					endcase
				end		
			`EXE_SPECIAL2_INST:		
				begin
					case ( op3 )
						`EXE_CLZ:	//对rs的0进行计数，从高位开始，计算0的个数，存在rd中	
							begin
								wreg_o <= `WriteEnable;		
								aluop_o <= `EXE_CLZ_OP;
								alusel_o <= `EXE_RES_ARITHMETIC; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								instvalid <= `InstValid;	
							end
						`EXE_CLO:	//对rs的1进行计数，从高位开始，计算1的个数，存在rd中	
							begin
								wreg_o <= `WriteEnable;		
								aluop_o <= `EXE_CLO_OP;
								alusel_o <= `EXE_RES_ARITHMETIC; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b0;	  	
								instvalid <= `InstValid;	
							end
						`EXE_MUL:	//有符号数相乘，只保留第32位到rd中	
							begin
								wreg_o <= `WriteEnable;		
								aluop_o <= `EXE_MUL_OP;
								alusel_o <= `EXE_RES_MUL; 
								reg1_read_o <= 1'b1;	
								reg2_read_o <= 1'b1;	
								instvalid <= `InstValid;	  			
							end
						default:			
							begin
							end
					endcase
				end						  	
		    default:			
				begin
		    	end
		endcase


		if (inst_i[31:21] == 11'b0) begin
		  	if (op3 == `EXE_SLL) begin //SLL指令，逻辑左移
		  		wreg_o <= `WriteEnable;
				aluop_o <= `EXE_SLL_OP;
		  		alusel_o <= `EXE_RES_SHIFT; reg1_read_o <= 1'b0;
				reg2_read_o <= 1'b1;
				imm[4:0] <= inst_i[10:6];
				wd_o <= inst_i[15:11];
				instvalid <= `InstValid;

				end else if ( op3 == `EXE_SRL ) begin //SRL指令，逻辑右移
		  		wreg_o <= `WriteEnable;
				aluop_o <= `EXE_SRL_OP;
		  		alusel_o <= `EXE_RES_SHIFT;
				reg1_read_o <= 1'b0;
				reg2_read_o <= 1'b1;
				imm[4:0] <= inst_i[10:6];
				wd_o <= inst_i[15:11];
				instvalid <= `InstValid;

				end else if ( op3 == `EXE_SRA ) begin //SRA指令，算术右移
		  		wreg_o <= `WriteEnable;
				aluop_o <= `EXE_SRA_OP;
		  		alusel_o <= `EXE_RES_SHIFT;
				reg1_read_o <= 1'b0;
				reg2_read_o <= 1'b1;
				imm[4:0] <= inst_i[10:6];
				wd_o <= inst_i[15:11];
				instvalid <= `InstValid;	
				end
			end
		if(inst_i == `EXE_ERET) 
			begin
				wreg_o <= `WriteDisable;		
				aluop_o <= `EXE_ERET_OP;
				alusel_o <= `EXE_RES_NOP;   
				reg1_read_o <= 1'b0;	
				reg2_read_o <= 1'b0;
				instvalid <= `InstValid; 
				excepttype_is_eret<= `True_v;				
			end else if(inst_i[31:21] == 11'b01000000000 && inst_i[10:0] == 11'b00000000000) begin
				aluop_o <= `EXE_MFC0_OP;
				alusel_o <= `EXE_RES_MOVE;
				wd_o <= inst_i[20:16];
				wreg_o <= `WriteEnable;
				instvalid <= `InstValid;	   
				reg1_read_o <= 1'b0;
				reg2_read_o <= 1'b0;		
			end else if(inst_i[31:21] == 11'b01000000100 && inst_i[10:0] == 11'b00000000000) begin
				aluop_o <= `EXE_MTC0_OP;
				alusel_o <= `EXE_RES_NOP;
				wreg_o <= `WriteDisable;
				instvalid <= `InstValid;	   
				reg1_read_o <= 1'b1;
				reg1_addr_o <= inst_i[20:16];
				reg2_read_o <= 1'b0;					
			end
				  
		end 
	end
	

	always @ (*) begin
		if(rst == `RstEnable) begin
			reg1_o <= `ZeroWord;		
		end else if((reg1_read_o == 1'b1) && (ex_wreg_i == 1'b1) 
								&& (ex_wd_i == reg1_addr_o)) begin
			reg1_o <= ex_wdata_i; 
		end else if((reg1_read_o == 1'b1) && (mem_wreg_i == 1'b1) 
								&& (mem_wd_i == reg1_addr_o)) begin
			reg1_o <= mem_wdata_i; 			
		end else if(reg1_read_o == 1'b1) begin
			reg1_o <= reg1_data_i;
		end else if(reg1_read_o == 1'b0) begin
			reg1_o <= imm;
		end else begin
			reg1_o <= `ZeroWord;
		end
	end
	
	always @ (*) begin
		if(rst == `RstEnable) begin
			reg2_o <= `ZeroWord;
		end else if((reg2_read_o == 1'b1) && (ex_wreg_i == 1'b1) 
								&& (ex_wd_i == reg2_addr_o)) begin
			reg2_o <= ex_wdata_i; 
		end else if((reg2_read_o == 1'b1) && (mem_wreg_i == 1'b1) 
								&& (mem_wd_i == reg2_addr_o)) begin
			reg2_o <= mem_wdata_i;			
		end else if(reg2_read_o == 1'b1) begin
			reg2_o <= reg2_data_i;
		end else if(reg2_read_o == 1'b0) begin
			reg2_o <= imm;
		end else begin
			reg2_o <= `ZeroWord;
	  	end
	end

	//判断当前译码指令是否在延迟槽中
	always @ (*) begin
		if(rst == `RstEnable) begin
			is_in_delayslot_o <= `NotInDelaySlot;
		end else begin
		  is_in_delayslot_o <= is_in_delayslot_i;		
	  end
	end

endmodule