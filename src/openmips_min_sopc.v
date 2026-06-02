`include "define.v"

module openmips_min_sopc(
	input wire sys_clk,            // 100MHz时钟（Basys3）
	
	// 板载输入外设（给CPU传数据）
    input wire [15:0] switch_in,  // 16位拨码开关
    input wire [4:0] key_in,      // 5个按键（BTNU/BTND/BTNL/BTNR/BTNC）
    
    // 板载输出外设（CPU结果可视化）
    output reg [15:0] led_out,    // 16位LED
    output reg [7:0] seg_out,     // 数码管段选（CA~DP）
    output reg [3:0] dig_out      // 数码管位选（AN0~AN3）
);

	//时钟中断
	  
	wire[5:0] int;
	wire timer_int;

	assign int = {5'b00000, timer_int};

	//连接指令存储器
	wire[`InstAddrBus]	inst_addr;
	wire[`InstBus]		inst;
	wire 				rom_ce;

	//连接数据存储器data_ram
	wire mem_we_i;
	wire[`RegBus] mem_addr_i;
	wire[`RegBus] mem_data_i;
	wire[`RegBus] mem_data_o; 
	wire mem_ce_i;
	wire[3:0] mem_sel_i; 

	//IO向CPU输入
	wire cpu_clk;
	wire cpu_rst;
	wire[`RegBus] io_sw_data;
	wire[4:0] io_key_data;

	//CPU传递IO输出
	wire[`RegBus] io_seg_regdata;
	wire[`RegBus] io_led_pcdata;
	wire[`RegBus] io_seg_hilodata;

	wire [15:0] led_out_wire; // 新增wire类型中间信号
	wire [7:0] seg_out_wire; // 新增wire类型中间信号
	wire [3:0] dig_out_wire; // 新增wire类型中间信号

	always @(*) begin
		led_out = led_out_wire;
		seg_out = seg_out_wire;
		dig_out = dig_out_wire;
	end

 	openmips openmips0(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.int_i(int),

		.io_sw_data(io_sw_data),
		.io_key_data(io_key_data),
	
		.rom_addr_o(inst_addr),
		.rom_data_i(inst),
		.rom_ce_o(rom_ce),

		.ram_we_o(mem_we_i),
		.ram_addr_o(mem_addr_i),
		.ram_sel_o(mem_sel_i),
		.ram_data_o(mem_data_i),
		.ram_data_i(mem_data_o),
		.ram_ce_o(mem_ce_i),

		.timer_int_o(timer_int),

		.io_seg_regdata(io_seg_regdata),
		.io_led_pcdata(io_led_pcdata),
		.io_seg_hilodata(io_seg_hilodata)
	);
	
	inst_rom inst_rom0(
		.ce(rom_ce),
		.clk(cpu_clk),
		.rst(cpu_rst),
		.addr(inst_addr),
		.inst(inst)	
	);

	data_ram data_ram0(
		.clk(cpu_clk),
		.we(mem_we_i),
		.addr(mem_addr_i),
		.sel(mem_sel_i),
		.data_i(mem_data_i),
		.data_o(mem_data_o),
		.ce(mem_ce_i)		
	);

	io io0(
		.clk_100MHz(sys_clk),          // 100MHz时钟（Basys3）
    	.seg_data(io_seg_regdata),       		// 数码管显示数据（低16位有效）
    	.led_data(io_led_pcdata),       		// LED显示数据（低16位有效），显示当下PC取值
		.hilo_data(io_seg_hilodata),       	// hilo寄存器数据
    	.sw_data(io_sw_data),   			// IO通过开关输入的数据传给CPU
    	.key_data(io_key_data),      		// 按键状态
    	.cpu_rst(cpu_rst),            	// CPU复位，来自开关15
    	.cpu_clk(cpu_clk),            	// 单步CPU时钟
    
		// 板载输入外设
		.switch_in(switch_in),    		// 16位拨码开关
		.key_in(key_in),        		// 5个按键（BTNU/BTND/BTNL/BTNR/BTNC）
		
		// 板载输出外设
		.led_out(led_out_wire),      		// 16位LED
		.seg_out(seg_out_wire),       		// 数码管段选（CA~DP，低电平点亮）
		.dig_out(dig_out_wire)
	);




endmodule

/*
	定义了测试模块中的openmips_min_sopc，包含了指存，数存，IO接口模块和mips核。
*/



	/*
	mioc mioc0(
		//来自mips的输入
		.mips_ram_ce_i(mioc_ce),            //执行阶段通过EX/MEM阶段的控制信号
		.mips_ram_we_i(mioc_we),
		.mips_ram_addr_i(mioc_addr),
		.mips_ram_wdata_i(mioc_wtData),
		.mips_ram_sel_i(mioc_sel),

		.mips_ram_rdData_o(mioc_rdData),

		//来自io模块的数据输入
		.io_RdData_i(io_rdData),

		//来自数存的数据发送给mips
		.mips_ram_rdata_i(mem_data_o),

		//发给数存的数据输出
		.ram_io_Ce_o(mem_ce_i),
		.ram_io_We_o(mem_we_i),
		.ram_io_Addr_o(mem_addr_i),
		.ram_io_Sel_o(mem_sel_i),

		.ram_io_WtData_o(mem_data_i),

		//发给io模块的数据输出
		.ioCe(io_ce),
		.ioWe(io_we),
		.ioAddr(io_addr),
		.ioSel(io_sel),

		.ioWtData(io_wtData)
	);
	*/