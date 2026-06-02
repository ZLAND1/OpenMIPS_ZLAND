`include "define.v"

module mioc(
    // 来自mips的输入
    input   wire            mips_ram_ce_i,            // 执行阶段通过EX/MEM阶段的控制信号
    input   wire            mips_ram_we_i,
    input   wire[`RegBus]   mips_ram_addr_i,
    input   wire[`RegBus]   mips_ram_wdata_i,
    input   wire[3:0]       mips_ram_sel_i,

    output  reg[`RegBus]    mips_ram_rdData_o,

    // 来自io模块的数据输入
    input   wire[`RegBus]   io_RdData_i,

    // 来自数存的数据发送给mips
    input   wire[`RegBus]   mips_ram_rdata_i,

    // 发给数存的数据输出
    output  reg             ram_io_Ce_o,
    output  reg             ram_io_We_o,
    output  reg[`RegBus]    ram_io_Addr_o,
    output  reg[3:0]        ram_io_Sel_o,
    output  reg[`RegBus]    ram_io_WtData_o,

    // 发给io模块的数据输出
    output  reg             ioCe,
    output  reg             ioWe,
    output  reg[`RegBus]    ioAddr,
    output  reg[3:0]        ioSel,
    output  reg[`RegBus]    ioWtData
);

    // 地址规划：
    // 数存：4KB → 0x0000_0000 ~ 0x0000_0FFF（低12位有效）
    // IO：   4KB → 0x7000_0000 ~ 0x7000_0FFF（高20位=0x70000，低12位有效）
    parameter RAM_ADDR_BASE  = 32'h0000_0000; // 数存基地址
    parameter IO_ADDR_PREFIX = 32'h7000_0000; // IO地址前缀
    parameter ADDR_MASK_4KB  = 32'h0000_0FFF; // 4KB地址掩码（低12位）

    // 第一步：判断地址归属（修正位运算优先级错误）
    wire is_io_addr = ( (mips_ram_addr_i & ~ADDR_MASK_4KB) == IO_ADDR_PREFIX ); // 地址前缀匹配IO
    wire is_ram_addr = ( (mips_ram_addr_i & ~ADDR_MASK_4KB) == RAM_ADDR_BASE ); // 地址前缀匹配数存

    // 第二步：选通数存/IO模块（组合逻辑，无latch风险）
    always @(*) begin
        // 默认值：所有模块禁用，避免不定态
        ioCe          = `RamDisable;
        ioWe          = `RamUnWrite;
        ioAddr        = `ZeroWord;
        ioSel         = `ZeroWord;
        ioWtData      = `ZeroWord;

        ram_io_Ce_o   = `RamDisable;
        ram_io_We_o   = `RamUnWrite;
        ram_io_Addr_o = `ZeroWord;
        ram_io_Sel_o  = `ZeroWord;
        ram_io_WtData_o = `ZeroWord;

        // MIPS使能时，判断地址归属
        if (mips_ram_ce_i == `RamEnable) begin
            if (is_io_addr) begin // 访问IO
                ioCe      = `RamEnable;
                ioWe      = mips_ram_we_i;
                ioAddr    = mips_ram_addr_i & ADDR_MASK_4KB; // 仅取低12位（IO内部地址）
                ioSel     = mips_ram_sel_i;
                ioWtData  = mips_ram_wdata_i;
            end else if (is_ram_addr) begin // 访问数存（4KB范围内）
                ram_io_Ce_o   = `RamEnable;
                ram_io_We_o   = mips_ram_we_i;
                ram_io_Addr_o = mips_ram_addr_i & ADDR_MASK_4KB; // 仅取低12位（数存内部地址）
                ram_io_Sel_o  = mips_ram_sel_i;
                ram_io_WtData_o = mips_ram_wdata_i;
            end
            // 非IO/数存地址：保持默认禁用状态
        end
    end

    // 第三步：返回读取数据给MIPS
    always @(*) begin
        mips_ram_rdData_o = `ZeroWord; // 默认返回0
        if (mips_ram_ce_i == `RamEnable) begin
            if (is_io_addr) begin // 读IO
                mips_ram_rdData_o = io_RdData_i;
            end else if (is_ram_addr) begin // 读数存
                mips_ram_rdData_o = mips_ram_rdata_i;
            end
        end
    end

endmodule