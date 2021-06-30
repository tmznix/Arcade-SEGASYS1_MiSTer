// Copyright (c) 2019 MiSTer-X

module HVGEN
(
        output       [8:0] HPOS,
        output       [8:0] VPOS,
        input              CLK,
        input              PCLK_EN,
        input       [11:0] iRGB,

        output reg  [11:0] oRGB,
        output             HBLK,
        output reg         VBLK = 1,
        output reg         HSYN = 1,
        output reg         VSYN = 1,

        input              H240,

        input signed [3:0] HOFFS,
        input signed [3:0] VOFFS
);

reg [8:0] hcnt = 0;
reg [8:0] vcnt = 0;

assign HPOS = hcnt-16;
assign VPOS = vcnt;

wire [8:0] HS_B = 296+HOFFS;
wire [8:0] HS_E = HS_B+16;

wire [8:0] VS_B = 234+VOFFS;
wire [8:0] VS_E = VS_B+4;

localparam [8:0] width = 320;
localparam [8:0] height = 260;

reg hblk240;
reg hblk256;

assign HBLK = H240 ? hblk240 : hblk256;

always @(posedge CLK) begin
	if (PCLK_EN) begin
		if (hcnt < width-1)
			hcnt <= hcnt+1;
		else begin
			hcnt <= 0;
			vcnt <= (vcnt+1) % height;
		end

		hblk256 <= (hcnt < 30) | (hcnt >= 286);
		hblk240 <= (hcnt < 38) | (hcnt >= 278);
		VBLK <= (vcnt >= 224);
		HSYN <= (hcnt < HS_B) | (hcnt >= HS_E);
		VSYN <= (vcnt < VS_B) | (vcnt >= VS_E);
		oRGB <= (HBLK|VBLK) ? 12'h0 : iRGB;
	end
end
endmodule
