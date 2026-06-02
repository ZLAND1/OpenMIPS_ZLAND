reg [19:0] clk_div_cnt; // 100MHz / 1000000 = 100Hz, 需要20位计数器
reg scan_clk;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        clk_div_cnt <= 20'd0;
        scan_clk <= 1'b0;
    end else begin
        if (clk_div_cnt == 20'd499999) begin
            clk_div_cnt <= 20'd0;
            scan_clk <= ~scan_clk;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1'b1;
        end
    end
end