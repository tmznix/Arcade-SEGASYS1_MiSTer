// Copyright (c) 2017,19 MiSTer-X

`define EN_MCPU0 (ROMAD[18:15]==4'b000_1 )
`define EN_MCPU8 (ROMAD[18:16]==3'b001)
`define EN_MCPUD (ROMAD[18:15]==4'b110_0 )

module SEGASYS1_MAIN
(
	input				CLK40M,

	input				RESET,

	input   [7:0]	INP0,
	input   [7:0]	INP1,
	input   [7:0]	INP2,

	input   [7:0]	DSW0,
	input   [7:0]	DSW1,
	input           system2,

	input				VBLK,
	input				VIDCS,
	input   [7:0]	VIDDO,
	output [15:0]	CPUAD,
	output  [7:0]	CPUDO,
	output		  	CPUWR,
	
	output reg		  SNDRQ,
	output reg [7:0] SNDNO,
	
	output reg [7:0] VIDMD,

	input				ROMCL,		// Downloaded ROM image
	input   [24:0]	ROMAD,
	input	  [7:0]	ROMDT,
	input				ROMEN,
	
	input 			PAUSE_N,
	input  [15:0]	HSAD,
	output [7:0]	HSDO,
	input  [7:0]	HSDI,
	input				HSWE
);

reg [3:0] clkdiv;
always @(posedge CLK40M) clkdiv <= clkdiv+1'd1;
wire CLK3M_EN = clkdiv[2:0] == 0;

wire			AXSCL   = CLK40M;
wire      CPUCL_EN = CLK3M_EN;

wire  [7:0]	CPUDI;

wire	cpu_m1;
wire	cpu_mreq, cpu_iorq;
wire	_cpu_rd, _cpu_wr;

Z80IP maincpu(
	.reset(RESET),
	.clk(CLK40M),
	.clk_en(CPUCL_EN),
	.adr(CPUAD),
	.data_in(CPUDI),
	.data_out(CPUDO),
	.m1(cpu_m1),
	.mx(cpu_mreq),
	.ix(cpu_iorq),
	.rd(_cpu_rd),
	.wr(_cpu_wr),
	.intreq(VBLK),
	.nmireq(1'b0),
	.wait_n(PAUSE_N)
);

assign CPUWR = _cpu_wr & cpu_mreq;

// Input Port
wire			cpu_cs_port;
wire [7:0]	cpu_rd_port;
SEGASYS1_IPORT port(CPUAD,cpu_iorq, INP0,INP1,INP2, DSW0,DSW1, cpu_cs_port,cpu_rd_port);


// Program ROM
wire			cpu_cs_mrom0 = (CPUAD[15]    == 1'b0 ) & cpu_mreq;
wire			cpu_cs_mrom1 = (CPUAD[15:14] == 2'b10) & cpu_mreq;

wire [7:0]	cpu_rd_mrom0;
wire [7:0]	cpu_rd_mrom1;
wire [7:0]	cpu_rd_mromd;

wire [14:0] rad;
wire  [7:0] rdt;

SEGASYS1_PRGDEC decr(AXSCL,cpu_m1,CPUAD,cpu_rd_mrom0, rad,rdt, ROMCL,ROMAD,ROMDT,ROMEN);

DLROM #(15,8) rom0(CLK40M, nocrypt ? CPUAD : rad, rdt, ROMCL,ROMAD,ROMDT,ROMEN & `EN_MCPU0);	// ($0000-$7FFF encrypted)

DLROM #(15,8) romd(CLK40M, CPUAD, cpu_rd_mromd, ROMCL,ROMAD,ROMDT,ROMEN & `EN_MCPUD);	// ($0000-$7FFF non-encrypted data)

// CPU Region $8000-$BFFF non-encrypted
// ROM banks 0-3
wire [1:0] cpu_bank = {system2 ? VIDMD[3] : VIDMD[6],VIDMD[2]};
DLROM #(16,8) rom8(CLK40M, {cpu_bank,CPUAD[13:0]}, cpu_rd_mrom1, ROMCL,ROMAD,ROMDT,ROMEN & `EN_MCPU8);

reg nocrypt = 0;
always @(posedge CLK40M) if(ROMEN & `EN_MCPUD) nocrypt <= 1;

// Work RAM
wire [7:0]	cpu_rd_mram;
wire			cpu_cs_mram = (CPUAD[15:12] == 4'b1100) & cpu_mreq;
//SRAM_4096 mainram(CLK40M, CPUAD[11:0], cpu_rd_mram, cpu_cs_mram & CPUWR, CPUDO );
/*
	input					clk,
	input	    [11:0]	adrs,
	output reg [7:0]	out,
	input					wr,
	input		  [7:0]	in
*/

dpram #(.aWidth(12),.dWidth(8))
mainram(
	.clk_a(CLK40M),
	.addr_a(CPUAD[11:0]),
	.we_a(cpu_cs_mram & CPUWR),
	.d_a(CPUDO),
	.q_a(cpu_rd_mram),

	.clk_b(CLK40M),
	.addr_b(HSAD[11:0]),
	.we_b(HSWE),
	.d_b(HSDI),
	.q_b(HSDO)

);

// Video mode latch & Sound Request
wire cpu_cs_sreq = ((CPUAD[7:0] == 8'h14)|(CPUAD[7:0] == 8'h18)) & cpu_iorq;
wire cpu_cs_vidm = ((CPUAD[7:0] == 8'h15)|(CPUAD[7:0] == 8'h19)) & cpu_iorq;

wire cpu_wr_sreq = cpu_cs_sreq & _cpu_wr;
wire cpu_wr_vidm = cpu_cs_vidm & _cpu_wr;

always @(posedge CLK40M or posedge RESET) begin
	if (RESET) begin
		VIDMD <= 0;
		SNDRQ <= 0;
		SNDNO <= 0;
	end
	else begin
		if (cpu_wr_vidm)
			VIDMD <= CPUDO;
		if (cpu_wr_sreq) begin
			SNDNO <= CPUDO;
			SNDRQ <= 1'b1;
		end else
			SNDRQ <= 1'b0;

	end
end


// CPU data selector
dataselector6 mcpudisel(
	CPUDI,
	VIDCS & cpu_mreq, VIDDO,
	cpu_cs_vidm,  VIDMD,
	cpu_cs_port,  cpu_rd_port,
	cpu_cs_mram,  cpu_rd_mram,
	cpu_cs_mrom0, ~nocrypt ? cpu_rd_mrom0 : cpu_m1 ? cpu_rd_mromd : rdt,
	cpu_cs_mrom1, cpu_rd_mrom1,
	8'hFF
);

endmodule


module SEGASYS1_IPORT
(
	input [15:0]	CPUAD,
	input				CPUIO,

	input  [7:0]	INP0,
	input  [7:0]	INP1,
	input  [7:0]	INP2,

	input  [7:0]	DSW0,
	input  [7:0]	DSW1,

	output			DV,
	output [7:0]	OD
);

wire cs_port1 =  (CPUAD[4:2] == 3'b0_00) & CPUIO;
wire cs_port2 =  (CPUAD[4:2] == 3'b0_01) & CPUIO;
wire cs_portS =  (CPUAD[4:2] == 3'b0_10) & CPUIO;
wire cs_portA =  (CPUAD[4:2] == 3'b0_11) & ~CPUAD[0] & CPUIO;
wire cs_portB =(((CPUAD[4:2] == 3'b0_11) &  CPUAD[0]) | (CPUAD[4:2] == 3'b1_00)) & CPUIO;

wire [7:0] inp;
dataselector5 dsel(
	inp,
	cs_port1,INP0,
	cs_port2,INP1,
	cs_portS,INP2,
	cs_portA,DSW0,
	cs_portB,DSW1,
	8'hFF
);

assign DV = cs_port1|cs_port2|cs_portS|cs_portA|cs_portB;
assign OD = inp;

endmodule

