//============================================================================
//  msx_fdc.sv - Philips style floppy disk interface for the MSX2 MiST core
//
//  WD2793 (wd1793.sv by Sorgelig / Viacheslav Slavinsky) plus the Philips
//  control registers, as found in the NMS 8245/8250/8280 and VY-0010.
//  The disk ROM itself is read from SDRAM by msx2_core (slot 3-3, 4000h).
//
//    7FF8h  WD2793 status / command
//    7FF9h  WD2793 track
//    7FFAh  WD2793 sector
//    7FFBh  WD2793 data
//    7FFCh  bit 0: side select
//    7FFDh  bit 1,0: drive (00/10 = A, 01 = B, 11 = none), bit 7: motor on
//    7FFFh  read: bit 7 = /DRQ, bit 6 = /INTRQ
//
//  Drive A: is a .DSK image mounted through the MiST OSD (SD image 0).
//  Supported images: 720 kB (2DD, 9 sectors/track, 2 sides) and
//  360 kB (1DD, 9 sectors/track, 1 side).  The image is written back when
//  the MSX writes to the disk.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module msx_fdc
(
	input         clk,          // 21.48 MHz
	input         reset,        // MSX reset

	// bus from msx2_core (7FF8h-7FFFh of slot 3-3)
	input         cs,
	input         rd,           // level, for the whole CPU read
	input         wr,           // level, for the whole CPU write
	input   [2:0] adr,
	input   [7:0] din,
	output  [7:0] dout,

	// MiST SD image (drive A:)
	input         img_mounted,
	input  [31:0] img_size,
	input         img_wp,
	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	output        disk_led       // motor on (drive activity)
);

reg  [7:0] side_reg  = 8'h00;
reg  [7:0] drive_reg = 8'h00;
reg        img_ok    = 1'b0;

wire       cs_wd   = cs & ~adr[2];
wire       wr_side = cs & wr & (adr == 3'd4);
wire       wr_drv  = cs & wr & (adr == 3'd5);

reg        old_wr_side, old_wr_drv;
always @(posedge clk) begin
	old_wr_side <= wr_side;
	old_wr_drv  <= wr_drv;
	if(reset) begin
		side_reg  <= 8'h00;
		drive_reg <= 8'h00;
	end else begin
		if(wr_side & ~old_wr_side) side_reg  <= din;
		if(wr_drv  & ~old_wr_drv ) drive_reg <= din;
	end

	if(img_mounted) img_ok <= (img_size != 0);
end

// drive A: is selected when bit 0 of the drive register is 0
wire ready = img_ok & ~drive_reg[0];

// single sided images (up to 360 kB) have no side interleave
wire single_sided = (img_size[31:0] <= 32'd368640);

wire [7:0] wd_dout;
wire       drq, intrq;

wd1793 #(.RWMODE(1), .EDSK(0), .CE_MUL(6)) fdc
(
	.clk_sys(clk),
	.ce(1'b1),
	.reset(reset),
	.io_en(cs_wd),
	.rd(rd),
	.wr(wr),
	.addr(adr[1:0]),
	.din(din),
	.dout(wd_dout),
	.drq(drq),
	.intrq(intrq),
	.busy(),

	.wp(img_wp),

	.size_code(3'd2),           // 512 bytes x 9 sectors
	.layout(single_sided),      // 1: no side interleave in the image
	.side(side_reg[0]),
	.ready(ready),

	.img_mounted(img_mounted),
	.img_size(img_size[19:0]),
	.prepare(),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.input_active(1'b0),
	.input_addr(20'h0),
	.input_data(8'h0),
	.input_wr(1'b0),
	.buff_addr(),
	.buff_read(),
	.buff_din(8'h0)
);

assign dout = ~adr[2]       ? wd_dout :
              (adr == 3'd4) ? side_reg :
              (adr == 3'd5) ? drive_reg :
              (adr == 3'd7) ? {~drq, ~intrq, 6'b000000} :   // like openMSX PhilipsFDC
                              8'hFF;

assign disk_led = drive_reg[7];

endmodule
