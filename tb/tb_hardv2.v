`timescale 1ns/1ns  // 仿真时间单位：1s，精度：1ms

// 测试顶层模块：验证openmips_min_sopc的功能
module tb_openmips_min_sopc();

// -------------------------- 1. 生成仿真激励信号 --------------------------
reg         clk;      // 仿真时钟（100MHz，周期10ns）
//reg         rst;      // 仿真复位（模拟SW15按键，低电平有效）
reg [15:0]  switch_in;// 模拟拨码开关输入（全关）
reg [4:0]   key_in;   // 模拟按键输入（全松开）

// -------------------------- 2. 声明输出信号（观测用） --------------------------
wire [15:0] led_out;  // LED输出（观测是否按指令亮灭）
wire [7:0]  seg_out;  // 数码管段选（观测段码是否正确）
wire [3:0]  dig_out;  // 数码管位选（观测扫描是否循环）

// -------------------------- 3. 例化被测模块 --------------------------
openmips_min_sopc openmips_min_sopc_inst(
    .sys_clk    (clk),
    .switch_in  (switch_in),
    .key_in     (key_in),
    .led_out    (led_out),
    .seg_out    (seg_out),
    .dig_out    (dig_out)
);

// -------------------------- 4. 生成时钟（100MHz） --------------------------
initial begin
    clk = 1'b0;                  // 初始低电平
    forever #5 clk = ~clk;       // 每5ns翻转一次，周期10ns（100MHz）
end

// -------------------------- 模拟外设输入（开关/按键） --------------------------
initial begin
    #100;                       
    switch_in = 16'b1000000000000000;                  // 按下复位键（低电平，复位有效）
    #10;                       
    switch_in = 16'b0011100000000000; 
    #2000;
    switch_in = 16'b0100000000000000;
    #200;
    switch_in = 16'b1000000000000000;


    // 可选：仿真中模拟按键按下（比如第5us时按上键）
    // #5000 key_in[0] = 1'b0;    // 5us时按下上键（key_in[0]对应BTNU）
end

endmodule