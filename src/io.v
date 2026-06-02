`include "define.v"

module io(
    input wire clk_100MHz,          // 100MHz时钟（Basys3）
    input [`RegBus] seg_data,       // 数码管显示数据（低16位有效）
    input [`RegBus] led_data,       // LED显示数据（低16位有效），显示当下PC取值
    input [`RegBus] hilo_data,      // hilo寄存器数据
    output reg [`RegBus] sw_data,   // IO通过开关输入的数据传给CPU
    output reg [4:0] key_data,      // 按键状态
    output wire cpu_rst,            // CPU复位，来自开关15
    output wire cpu_clk,            // 重写CPU时钟
    
    // 板载输入外设
    input wire [15:0] switch_in,    // 16位拨码开关
    input wire [4:0] key_in,        // 5个按键（BTNU/BTND/BTNL/BTNR/BTNC）
    
    // 板载输出外设
    output reg [15:0] led_out,      // 16位LED
    output reg [7:0] seg_out,       // 数码管段选（CA~DP，低电平点亮）
    output reg [3:0] dig_out        // 数码管位选（AN0~AN3，低电平选通）
);  
    reg [19:0] cnt_btn; 
    reg btn_stable;
    reg btn_stable_delay;

    reg [7:0] get_seg_code;         //段码
    reg [3:0] get_dig;              //位码
    reg [3:0] num;                  //显示数码
    reg [15:0] scan_cnt;
    reg clktocpu;
    reg cpu_rst_sync1, cpu_rst_sync2;
    wire segdata_hilo_ch;
    wire [`RegBus] hilodata;

    // 新增分频计数器（需定义为reg型，放在模块内部）
    reg [26:0] clk_div_cnt; // 27位计数器，最大可计到134,217,727，满足100M计数需求
    reg clk_1hz_level;      // 1秒切换一次的电平信号（0.5Hz时钟）

    assign hilodata = hilo_data;



    always @(posedge clk_100MHz) begin
        if (key_in[0] == 1'b1) begin
            if (cnt_btn < 20'd100_0000) cnt_btn <= cnt_btn + 1;   //按键消抖，再说
            else 
            btn_stable <= 1'b1;
        end else begin
            cnt_btn <= 20'd0;
            btn_stable <= 1'b0;
        end
        btn_stable_delay <= btn_stable;
    end

    

    // 100MHz分频到1秒切换一次电平的时序逻辑
    always @(posedge clk_100MHz) begin // 建议加复位rst_n，若无则去掉negedge rst_n
        if (cpu_rst) begin // 复位（可选，无复位则注释此段）
            clk_div_cnt <= 27'd0;
            clk_1hz_level <= 1'b0;
        end else begin
            if (clk_div_cnt == 27'd99_999_999) begin // 计数到100M次（1秒）
                clk_div_cnt <= 27'd0;
                clk_1hz_level <= ~clk_1hz_level; // 翻转电平（1秒切换一次）
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
            end
        end
    end

    always @(*) begin
        if (switch_in[14] == 1'b1) begin
            clktocpu <= btn_stable & (~btn_stable_delay);     //若开关14高电平则使用断步时钟控制
        end else begin
            //clktocpu <=clk_100MHz;  //否则使用正常的系统时钟
            clktocpu <= clk_1hz_level;
        end                          
    end

    assign cpu_clk = clktocpu;

    always @(posedge clk_100MHz) begin
        if(switch_in[15]) begin
            scan_cnt <= 16'b0; // 复位清零，消除初始x态
        end else begin
            scan_cnt <= scan_cnt + 1; // 100MHz分频产生扫描时钟
        end
    end

    assign segdata_hilo_ch = switch_in[13]; // 高低位选择信号

    wire hilo_seg_hi = switch_in[12]; // hi寄存器读使能
    wire hilo_seg_lo = switch_in[11]; // lo寄存器读使能
    wire hilore = hilo_seg_hi ^ hilo_seg_lo; // 读使能信号的异或

    always @(scan_cnt or seg_data) begin
        case(scan_cnt[15:14])
            2'b00: begin 
                get_dig = 4'b1110;
                if((hilore) == 1'b1) begin
                    if(segdata_hilo_ch) begin
                        num <= hilodata[3:0];
                    end else begin
                        num <= hilodata[19:16];
                    end
                end else if(segdata_hilo_ch) begin  
                    num <= seg_data[3:0];
                end else begin
                    num <= seg_data[19:16];
                end
            end // 第1位
            2'b01: begin 
                get_dig = 4'b1101;
                if((hilore) == 1'b1) begin
                    if(segdata_hilo_ch) begin
                        num <= hilodata[7:4];
                    end else begin
                        num <= hilodata[23:20];
                    end
                end else
                if(segdata_hilo_ch) begin
                    num <= seg_data[7:4];  
                end else begin 
                    num <= seg_data[23:20];
                end 
            end // 第2位
            2'b10: begin 
                get_dig = 4'b1011;
                if((hilore) == 1'b1) begin
                    if(segdata_hilo_ch) begin
                        num <= hilodata[11:8];
                    end else begin
                        num <= hilodata[27:24];
                    end
                end else
                if(segdata_hilo_ch) begin
                    num <= seg_data[11:8]; 
                end else begin
                    num <= seg_data[27:24];
                end
            end // 第3位
            2'b11: begin 
                get_dig = 4'b0111;
                if((hilore) == 1'b1) begin
                    if(segdata_hilo_ch) begin
                        num <= hilodata[15:12];
                    end else begin
                        num <= hilodata[31:28];
                    end
                end else
                if(segdata_hilo_ch) begin
                    num <= seg_data[15:12];
                end else begin 
                    num <= seg_data[31:28];
                end 
            end // 第4位
        endcase
    end
    

    // 组合逻辑：4位输入→7段数码管编码（共阴极，低电平灭，高电平亮）
    always @(*) 
        begin
            case(num)
                4'h0: get_seg_code = 8'b11000000; // 0（DP灭，A~F亮，G灭）
                4'h1: get_seg_code = 8'b11111001; // 1（仅B、C亮）
                4'h2: get_seg_code = 8'b10100100; // 2
                4'h3: get_seg_code = 8'b10110000; // 3
                4'h4: get_seg_code = 8'b10011001; // 4
                4'h5: get_seg_code = 8'b10010010; // 5
                4'h6: get_seg_code = 8'b10000010; // 6
                4'h7: get_seg_code = 8'b11111000; // 7
                4'h8: get_seg_code = 8'b10000000; // 8
                4'h9: get_seg_code = 8'b10010000; // 9
                4'ha: get_seg_code = 8'b10001000; // A
                4'hb: get_seg_code = 8'b10000011; // B
                4'hc: get_seg_code = 8'b11000110; // C
                4'hd: get_seg_code = 8'b10100001; // D
                4'he: get_seg_code = 8'b10000110; // E
                4'hf: get_seg_code = 8'b10001110; // F
                default: get_seg_code = 8'b11111111; // 全灭（DP灭，所有段灭）
            endcase
        end

    always @(*) begin
        if (switch_in[15] == 1'b1) begin
            led_out <= 16'h0000; // 复位LED
            dig_out <= 4'b1111; // 复位数码管位选
            seg_out <= 8'b11111111; // 复位数码管段选
        end else begin
            sw_data <= {16'h0 , switch_in}; //开关输入给CPU
            key_data <= key_in;
            led_out <= led_data[17:2]; //LED数据由CPU的PC传入
            dig_out <= get_dig;
            seg_out <= get_seg_code;
        end
    end

    
    always @(posedge clk_100MHz) begin
        cpu_rst_sync1 <= switch_in[15];  // 第一级同步
        cpu_rst_sync2 <= cpu_rst_sync1;  // 第二级同步，消除亚稳态
    end

    assign cpu_rst = cpu_rst_sync2;  // 最终同步复位信号
    //assign cpu_rst = switch_in[15]; //开关15复位CPU，高电平有效

endmodule


/*
    预备功能设计
    由于basys3开发板可视化输入输出方式简单有4种
    输入：16位拨码开关，5个按键
    输出：4位7段数码管，16位LED

    关于MIPSCPU的指令测试，我们需要看到的信息大致有：
    当前执行的指令是什么（简化为当前执行的是第几条指令）
    查看寄存器的值（即可以查看寄存器内的结果是否正确）
    可以断步查询，即单步执行，需要用到中断或者流水线断流等可能的技术

    控制方法如下：
    SW[15]控制复位信号，高电平有效
    SW[14]是断步Debug模式，1为断步模式，在此情况下，按键上key[0]按下一次则产生一个上升沿
    SW[13]是高低位选择信号，1为高位，0为低位
    SW[12:11]是hilo寄存器读使能，异或后1为使能，0为禁止，其中两个都为1时则无效，继续显示通用寄存器的值，SW[12]为1时显示HI的值，SW[11]为1时显示LO的值
    SW[4:0]是输入寄存器号，通过4位数码管来观察寄存器的低16位的值，可以通过SW[13]切换显示的高低位
    LED[15:0]是输出当前取指令的条数，即pc[17:2]
*/