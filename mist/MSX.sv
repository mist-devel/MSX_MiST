//============================================================================
//  MSX2 for MiST
//
//  A real MSX2 (Philips NMS 8245 like) built from the OneChipMSX / OCM-PLD
//  components (T80, ESE-VDP, PSG, OPLL, SCC) of the MSX core for MiST by
//  gyurco.  The system ROMs, the ROM cartridges, the floppy disks (.DSK)
//  and the tapes (.CAS) are loaded from the MiST OSD (F12).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

`ifdef VGA_8BIT
`define MSX_VGA_BITS 8
`else
`define MSX_VGA_BITS 6
`endif

module MSX #(parameter VGA_BITS = `MSX_VGA_BITS)
(
	input         CLOCK_27,

	output        LED,
	output reg [VGA_BITS-1:0] VGA_R,
	output reg [VGA_BITS-1:0] VGA_G,
	output reg [VGA_BITS-1:0] VGA_B,
	output reg    VGA_HS,
	output reg    VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output reg [7:0] HDMI_R,
	output reg [7:0] HDMI_G,
	output reg [7:0] HDMI_B,
	output reg    HDMI_HS,
	output reg    HDMI_VS,
	output        HDMI_PCLK,
	output reg    HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif
	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,
	input         SPI_SS3,
	input         CONF_DATA0,

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif
	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output reg    HDMI_BCK,
	output reg    HDMI_LRCK,
	output reg    HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
`ifdef USE_MIDI_PINS
	input         MIDI_IN,
	output        MIDI_OUT,
`endif
	input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
wire SPI_SS4 = 1;
`endif

`ifdef USE_QSPI
assign QDAT = 4'hZ;
`else
wire QSCK = 1'b0;
wire QCSn = 1'b1;
wire [3:0] QDAT = 4'h0;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`else
localparam bit BIG_OSD = 0;
`endif

`ifdef DUAL_SDRAM
assign SDRAM2_A = 13'hZZZZ;
assign SDRAM2_BA = 0;
assign SDRAM2_DQML = 0;
assign SDRAM2_DQMH = 0;
assign SDRAM2_CKE = 0;
assign SDRAM2_CLK = 0;
assign SDRAM2_nCS = 1;
assign SDRAM2_DQ = 16'hZZZZ;
assign SDRAM2_nCAS = 0;
assign SDRAM2_nRAS = 0;
assign SDRAM2_nWE = 0;
`endif

`ifdef USE_MIDI_PINS
assign MIDI_OUT = 1'b1;
`endif
assign UART_TX = 1'b1;

`include "build_id.v"

////////////////////////////////////////////////////////////////////////////
// OSD menu
//
// data_io index:  0 = MSX2.ROM (main+sub+disk[+music] ROMs, loaded at start)
//                 1 = MSX2.R01 sub ROM, 2 = MSX2.R02 disk ROM,
//                 3 = MSX2.R03 MSX-MUSIC ROM (optional, loaded at start)
//                 7 = cartridge slot 1, 8 = cartridge slot 2
// SD images:      0 = disk drive A: (.DSK), 1 = cassette (.CAS)
////////////////////////////////////////////////////////////////////////////

`ifdef MSX1_CORE
// MSX1: 64 kB RAM without mapper, TMS9918 like video (V9938 in MSX1 modes)
localparam MSX1 = 1;
localparam CONF_STR = {
	"MSX1;;",
	"F7,ROM,Cartridge slot 1;",
	"F8,ROM,Cartridge slot 2;",
	"S0U,DSK,Disk drive A:;",
	"S1U,CAS,Cassette;",
	"T1,Rewind cassette;",
	"T2,Eject cartridges & reset;",
	"P1,System;",
	"P1O46,CPU speed,3.58MHz,5.37MHz,6.96MHz,8.06MHz,10.74MHz;",
	"P1OA,Disk drive,Enabled,Disabled;",
	"P1OB,MSX-MUSIC (FM),Enabled,Disabled;",
	"P1OCD,Keyboard,Italian,US,Japanese;",
	"P1OF,Swap joysticks,No,Yes;",
	"P1OG,RAM slot,3 (normal),3-2 (Philips);",
	"P2,Cartridges;",
	"P2OHJ,Slot 1 mapper,Auto,Plain ROM,Konami SCC,Konami,ASCII 8K,ASCII 16K,Generic 8K;",
	"P2OKM,Slot 2 mapper,Auto,Plain ROM,Konami SCC,Konami,ASCII 8K,ASCII 16K,Generic 8K;",
	"P3,Audio & Video;",
	"P3ONO,PSG volume,Normal,High,Low,Off;",
	"P3OPQ,SCC volume,Normal,High,Low,Off;",
	"P3ORS,FM volume,Normal,High,Low,Off;",
	"P3OT,Cassette sound,Off,On;",
	"P3OU,Cassette speed,1200 baud,2400 baud;",
	"P3OV,Video frequency,50Hz (PAL),60Hz (NTSC);",
	"P3OX,VGA timing,CRT,LCD;",
	"P3OY,Tape progress bar,On,Off;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};
`else
localparam MSX1 = 0;
localparam CONF_STR = {
	"MSX2;;",
	"F7,ROM,Cartridge slot 1;",
	"F8,ROM,Cartridge slot 2;",
	"S0U,DSK,Disk drive A:;",
	"S1U,CAS,Cassette;",
	"T1,Rewind cassette;",
	"T2,Eject cartridges & reset;",
	"P1,System;",
	"P1O46,CPU speed,3.58MHz,5.37MHz,6.96MHz,8.06MHz,10.74MHz;",
	"P1O79,RAM (mapper),512KB,1MB,2MB,4MB,128KB,256KB,64KB;",
	"P1OA,Disk drive,Enabled,Disabled;",
	"P1OB,MSX-MUSIC (FM),Enabled,Disabled;",
	"P1OCD,Keyboard,Italian,US,Japanese;",
	"P1OE,VDP ID,V9938 (MSX2),V9958 (MSX2+);",
	"P1OF,Swap joysticks,No,Yes;",
	"P1OG,RAM slot,3-2 (Philips),3-0 (Sony);",
	"P2,Cartridges;",
	"P2OHJ,Slot 1 mapper,Auto,Plain ROM,Konami SCC,Konami,ASCII 8K,ASCII 16K,Generic 8K;",
	"P2OKM,Slot 2 mapper,Auto,Plain ROM,Konami SCC,Konami,ASCII 8K,ASCII 16K,Generic 8K;",
	"P3,Audio & Video;",
	"P3ONO,PSG volume,Normal,High,Low,Off;",
	"P3OPQ,SCC volume,Normal,High,Low,Off;",
	"P3ORS,FM volume,Normal,High,Low,Off;",
	"P3OT,Cassette sound,Off,On;",
	"P3OU,Cassette speed,1200 baud,2400 baud;",
	"P3OVW,Video frequency,Auto (BIOS),60Hz (NTSC),50Hz (PAL);",
	"P3OX,VGA timing,CRT,LCD;",
	"P3OY,Tape progress bar,On,Off;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};
`endif

////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys;           // 21.48 MHz
wire memclk;            // 85.92 MHz
`ifdef USE_HDMI
wire hdmiclk;
`endif

pll pll
(
	.inclk0(CLOCK_27),
	.c0(memclk),
	.c1(clk_sys),
`ifdef USE_HDMI
	.c2(hdmiclk),
`endif
	.locked(locked)
);

assign SDRAM_CLK = memclk;

//////////////////   MiST I/O   ///////////////////

wire  [31:0] joy_0;
wire  [31:0] joy_1;
wire   [1:0] buttons;
wire  [63:0] status;
wire         ypbpr;
wire         no_csync;
wire         scandoubler_disable;

wire  [31:0] sd_lba;
wire   [1:0] sd_rd;
wire   [1:0] sd_wr;
wire         sd_ack;
wire   [1:0] sd_ack_x;
wire   [8:0] sd_buff_addr;
wire   [7:0] sd_buff_dout;
wire   [7:0] sd_buff_din;
wire         sd_buff_wr;
wire   [1:0] img_mounted;
wire  [63:0] img_size;

wire         ps2_kbd_clk;
wire         ps2_kbd_data;

// the PS/2 lines of the keyboard interface are bidirectional (it sends the
// LED commands): the data from the IO controller is wired as open collector,
// like in the original MSX core
wire         msx_ps2_kbd_clk  = ps2_kbd_clk;
wire         msx_ps2_kbd_data = (ps2_kbd_data == 1'b0) ? 1'b0 : 1'bZ;

wire   [8:0] mouse_x;
wire   [8:0] mouse_y;
wire   [7:0] mouse_flags;
wire         mouse_strobe;

wire  [63:0] rtc;

`ifdef USE_HDMI
wire         i2c_start;
wire         i2c_read;
wire   [6:0] i2c_addr;
wire   [7:0] i2c_subaddr;
wire   [7:0] i2c_dout;
wire   [7:0] i2c_din;
wire         i2c_ack;
wire         i2c_end;
`endif

user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(2), .PS2DIV(100), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(
	.clk_sys(clk_sys),
	.clk_sd(clk_sys),
	.SPI_SS_IO(CONF_DATA0),
	.SPI_CLK(SPI_SCK),
	.SPI_MOSI(SPI_DI),
	.SPI_MISO(SPI_DO),

	.conf_str(CONF_STR),

	.status(status),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr(ypbpr),
	.no_csync(no_csync),
	.buttons(buttons),
	.rtc(rtc),
`ifdef USE_HDMI
	.i2c_start(i2c_start),
	.i2c_read(i2c_read),
	.i2c_addr(i2c_addr),
	.i2c_subaddr(i2c_subaddr),
	.i2c_dout(i2c_dout),
	.i2c_din(i2c_din),
	.i2c_ack(i2c_ack),
	.i2c_end(i2c_end),
`endif
	.joystick_0(joy_0),
	.joystick_1(joy_1),

	.sd_conf(1'b0),
	.sd_sdhc(1'b1),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_ack_x(sd_ack_x),
	.sd_ack_conf(),
	.sd_buff_addr(sd_buff_addr),
	.sd_dout(sd_buff_dout),
	.sd_din(sd_buff_din),
	.sd_dout_strobe(sd_buff_wr),
	.sd_din_strobe(),
	.img_mounted(img_mounted),
	.img_size(img_size),

	.ps2_kbd_clk(ps2_kbd_clk),
	.ps2_kbd_data(ps2_kbd_data),

	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_flags(mouse_flags),
	.mouse_strobe(mouse_strobe)
);

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

data_io data_io
(
	.clk_sys(clk_sys),
	.SPI_SCK(SPI_SCK),
	.SPI_SS2(SPI_SS2),
	.SPI_SS4(SPI_SS4),
	.SPI_DI(SPI_DI),
	.SPI_DO(SPI_DO),
	.QCSn(QCSn),
	.QSCK(QSCK),
	.QDAT(QDAT),
	.clkref_n(1'b0),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout)
);

//////////////////   Settings   ///////////////////

// OSD volume: Normal, High, Low, Off
function [2:0] vol(input [1:0] v);
	case(v)
		2'd0: vol = 3'd4;
		2'd1: vol = 3'd6;
		2'd2: vol = 3'd2;
		2'd3: vol = 3'd0;
	endcase
endfunction

wire  [2:0] cfg_speed   = (status[6:4] > 3'd4) ? 3'd4 : status[6:4];
wire  [2:0] cfg_ram     = status[9:7];
wire        cfg_disk    = ~status[10];
wire        cfg_music   = ~status[11];
wire  [1:0] cfg_kbd     = (status[13:12] == 2'd0) ? 2'b01 :      // Italian
                          (status[13:12] == 2'd1) ? 2'b00 :      // US
                                                    2'b10;       // Japanese
wire        cfg_v9958   = status[14];
wire        joy_swap    = status[15];
wire        cfg_ram30   = status[16];
wire  [2:0] cfg_mapper1 = (status[19:17] == 3'd7) ? 3'd0 : status[19:17];
wire  [2:0] cfg_mapper2 = (status[22:20] == 3'd7) ? 3'd0 : status[22:20];
wire  [2:0] cfg_psg_vol = vol(status[24:23]);
wire  [2:0] cfg_scc_vol = vol(status[26:25]);
wire  [2:0] cfg_fm_vol  = vol(status[28:27]);
wire        cfg_tape_snd= status[29];
wire        cas_fast    = status[30];
// MSX2: Auto (BIOS) / 60Hz / 50Hz - MSX1: 50Hz / 60Hz (an MSX1 BIOS never sets the PAL bit of the VDP)
wire  [1:0] cfg_vmode   = MSX1 ? (status[31] ? 2'b01 : 2'b10) :
                          (status[32:31] == 2'd3) ? 2'd0 : status[32:31];
wire        cfg_lcd     = status[33];
wire        cfg_tape_bar= ~status[34];

wire        cas_rewind  = status[1];
wire        cart_eject  = status[2];

//////////////////   Reset   ///////////////////

wire        sys_rom_ok;
reg  [23:0] rst_cnt = 24'hFFFFFF;
reg         msx_reset_n = 0;
reg         eject_d;

// cartridge / ROM upload: the MSX is held in reset while the file is written
// to SDRAM and it restarts afterwards, like after inserting a cartridge
wire        dl_reset = ioctl_download;

// changing the hardware (RAM, cartridge mappers, disk drive, MSX-MUSIC)
// restarts the MSX, like switching it off and on with the new setup
wire [12:0] hw_cfg = {status[22:17], status[11:10], status[9:7], status[16], 1'b0};
reg  [12:0] hw_cfg_d;
reg         hw_changed;
always @(posedge clk_sys) begin
	hw_cfg_d   <= hw_cfg;
	hw_changed <= (hw_cfg != hw_cfg_d);
end

always @(posedge clk_sys) begin
	eject_d <= cart_eject;

	if(~locked)
`ifdef USE_HDMI
		rst_cnt <= 24'hFFFFFF;                      // 0.8 s for the HDMI transmitter
`else
		rst_cnt <= 24'h1FFFFF;                      // 0.1 s
`endif
	else if(status[0] | buttons[1] | dl_reset | (cart_eject & ~eject_d) | hw_changed)
		rst_cnt <= 24'h1FFFF;                       // 6 ms
	else if(rst_cnt != 0)
		rst_cnt <= rst_cnt - 1'd1;

	msx_reset_n <= (rst_cnt == 0) & sys_rom_ok;
end

//////////////////   Joysticks / mouse   ///////////////////

wire [5:0] joya = joy_swap ? ~joy_1[5:0] : ~joy_0[5:0];
wire [5:0] joyb = joy_swap ? ~joy_0[5:0] : ~joy_1[5:0];
wire [5:0] msx_joya;
wire [5:0] msx_joyb;
wire       msx_stra;
wire       msx_strb;
wire       msx_reset;

reg        mouse_en = 0;
reg  [5:0] mouse;

// open collector outputs, like the joystick ports of a real MSX
genvar gi;
generate
	for (gi=0; gi<=5; gi=gi+1) begin : joy_oc
		assign msx_joya[gi] = mouse_en ? (mouse[gi] ? 1'bZ : 1'b0) : ((~joya[gi] & ~msx_stra) ? 1'b0 : 1'bZ);
		assign msx_joyb[gi] = (~joyb[gi] & ~msx_strb) ? 1'b0 : 1'bZ;
	end
endgenerate

// MSX mouse (on joystick port A) emulated with the USB/PS2 mouse
always @(posedge clk_sys) begin
	reg        stra_d;
	reg  [8:0] mouse_x_latch;
	reg  [8:0] mouse_y_latch;
	reg  [1:0] mouse_state;
	reg [17:0] mouse_timeout;

	if (msx_reset) begin
		mouse_en <= 0;
		mouse_state <= 0;
	end
	else if (mouse_strobe) mouse_en <= 1;
	else if (~&joya) mouse_en <= 0;

	if (mouse_strobe) begin
		mouse_x_latch <= ~mouse_x + 1'd1;
		mouse_y_latch <= mouse_y;
	end

	mouse[5:4] <= ~mouse_flags[1:0];
	if (mouse_en) begin
		if (mouse_timeout) begin
			mouse_timeout <= mouse_timeout - 1'd1;
			if (mouse_timeout == 1) mouse_state <= 0;
		end

		stra_d <= msx_stra;
		if (stra_d ^ msx_stra) begin
			mouse_timeout <= 18'd100000;
			mouse_state <= mouse_state + 1'd1;
			case (mouse_state)
			2'b00: mouse[3:0] <= {mouse_x_latch[5],mouse_x_latch[6],mouse_x_latch[7],mouse_x_latch[8]};
			2'b01: mouse[3:0] <= {mouse_x_latch[1],mouse_x_latch[2],mouse_x_latch[3],mouse_x_latch[4]};
			2'b10: mouse[3:0] <= {mouse_y_latch[5],mouse_y_latch[6],mouse_y_latch[7],mouse_y_latch[8]};
			2'b11:
			begin
				mouse[3:0] <= {mouse_y_latch[1],mouse_y_latch[2],mouse_y_latch[3],mouse_y_latch[4]};
				mouse_x_latch <= 0;
				mouse_y_latch <= 0;
			end
			endcase
		end
	end
end

//////////////////   Cassette   ///////////////////

reg  rx_d, rx;
always @(posedge clk_sys) begin
	rx_d <= UART_RX;
	rx   <= rx_d;
end

wire ear_in;
`ifdef USE_AUDIO_IN
assign ear_in = AUDIO_IN;
`else
assign ear_in = rx;               // a real data recorder can be connected here
`endif

wire        cas_motor;
wire        cas_out;
wire        cas_active;
wire  [7:0] cas_progress;
wire [31:0] cas_lba;
wire        cas_rd;

cas_player cas_player
(
	.clk(clk_sys),
	.rewind(cas_rewind),
	.fast(cas_fast),
	.motor(cas_motor),
	.img_mounted(img_mounted[1]),
	.img_size(img_size[31:0]),
	.sd_lba(cas_lba),
	.sd_rd(cas_rd),
	.sd_ack(cas_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),
	.cas_out(cas_out),
	.active(cas_active),
	.progress(cas_progress)
);

wire cmt_in = cas_active ? cas_out : ear_in;

//////////////////   Floppy disk   ///////////////////

wire        fdc_cs, fdc_rd, fdc_wr;
wire  [2:0] fdc_adr;
wire  [7:0] fdc_dbo, fdc_dbi;
wire        disk_on;
wire [31:0] fdc_lba;
wire        fdc_sd_rd, fdc_sd_wr;
wire        disk_led;

msx_fdc msx_fdc
(
	.clk(clk_sys),
	.reset(msx_reset | ~disk_on),
	.cs(fdc_cs),
	.rd(fdc_rd),
	.wr(fdc_wr),
	.adr(fdc_adr),
	.din(fdc_dbo),
	.dout(fdc_dbi),
	.img_mounted(img_mounted[0]),
	.img_size(img_size[31:0]),
	.img_wp(1'b0),
	.sd_lba(fdc_lba),
	.sd_rd(fdc_sd_rd),
	.sd_wr(fdc_sd_wr),
	.sd_ack(fdc_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.disk_led(disk_led)
);

// SD image arbiter: only one sector request at a time is passed to the IO
// controller, so the common sd_ack is enough (works also with firmware
// versions that don't send the per-drive acknowledge)
reg  [1:0] sd_grant = 2'd0;            // 0 = none, 1 = floppy, 2 = cassette
always @(posedge clk_sys) begin
	case(sd_grant)
		2'd0: if(fdc_sd_rd | fdc_sd_wr) sd_grant <= 2'd1;
		      else if(cas_rd)          sd_grant <= 2'd2;
		2'd1: if(~sd_ack & ~fdc_sd_rd & ~fdc_sd_wr) sd_grant <= 2'd0;
		2'd2: if(~sd_ack & ~cas_rd) sd_grant <= 2'd0;
		default: sd_grant <= 2'd0;
	endcase
end

wire   fdc_ack = sd_ack & (sd_grant == 2'd1);
wire   cas_ack = sd_ack & (sd_grant == 2'd2);

assign sd_rd  = {cas_rd & (sd_grant == 2'd2), fdc_sd_rd & (sd_grant == 2'd1)};
assign sd_wr  = {1'b0,                        fdc_sd_wr & (sd_grant == 2'd1)};
assign sd_lba = (sd_grant == 2'd2) ? cas_lba : fdc_lba;

//////////////////   MSX2   ///////////////////

wire  [5:0] R_O, G_O, B_O;
wire        HSync, VSync, Blank;
wire [13:0] audio;
wire        dac_out;
wire        cmt_out;

msx2_core #(.MSX1(MSX1)) msx2
(
	.clk21m(clk_sys),
	.memclk(memclk),
	.reset_n(msx_reset_n),
	.pll_locked(locked),

	.pMemCke(SDRAM_CKE),
	.pMemCs_n(SDRAM_nCS),
	.pMemRas_n(SDRAM_nRAS),
	.pMemCas_n(SDRAM_nCAS),
	.pMemWe_n(SDRAM_nWE),
	.pMemUdq(SDRAM_DQMH),
	.pMemLdq(SDRAM_DQML),
	.pMemBa1(SDRAM_BA[1]),
	.pMemBa0(SDRAM_BA[0]),
	.pMemAdr(SDRAM_A),
	.pMemDat(SDRAM_DQ),

	.pPs2Clk(msx_ps2_kbd_clk),
	.pPs2Dat(msx_ps2_kbd_data),

	.pJoyA({msx_joya[5:4], msx_joya[0], msx_joya[1], msx_joya[2], msx_joya[3]}),
	.pStrA(msx_stra),
	.pJoyB({msx_joyb[5:4], msx_joyb[0], msx_joyb[1], msx_joyb[2], msx_joyb[3]}),
	.pStrB(msx_strb),

	.pVideoR(R_O),
	.pVideoG(G_O),
	.pVideoB(B_O),
	.pVideoHS_n(HSync),
	.pVideoVS_n(VSync),
	.pVideoBlank(Blank),

	.audio_o(audio),
	.pDacOut(dac_out),

	.CmtIn(cmt_in),
	.CmtOut(cmt_out),
	.CmtMotor(cas_motor),

	.iRTC(rtc),

	.fdc_cs(fdc_cs),
	.fdc_rd(fdc_rd),
	.fdc_wr(fdc_wr),
	.fdc_adr(fdc_adr),
	.fdc_dbo(fdc_dbo),
	.fdc_dbi(fdc_dbi),
	.cpu_ce(),
	.msx_reset(msx_reset),
	.disk_on(disk_on),

	.dl_download(ioctl_download),
	.dl_index(ioctl_index),
	.dl_wr(ioctl_wr),
	.dl_addr(ioctl_addr),
	.dl_data(ioctl_dout),
	.eject1(cart_eject),
	.eject2(cart_eject),
	.sys_rom_ok(sys_rom_ok),

	.cfg_speed(cfg_speed),
	.cfg_ram(cfg_ram),
	.cfg_mapper1(cfg_mapper1),
	.cfg_mapper2(cfg_mapper2),
	.cfg_disk(cfg_disk),
	.cfg_music(cfg_music),
	.cfg_psg_vol(cfg_psg_vol),
	.cfg_scc_vol(cfg_scc_vol),
	.cfg_fm_vol(cfg_fm_vol),
	.cfg_tape_snd(cfg_tape_snd),
	.cfg_vmode(cfg_vmode),
	.cfg_vga(~scandoubler_disable),
	.cfg_lcd(cfg_lcd),
	.cfg_kbd(cfg_kbd),
	.cfg_v9958(cfg_v9958),
	.cfg_ram30(cfg_ram30)
);

assign AUDIO_L = dac_out;
assign AUDIO_R = dac_out;

assign LED = ~(disk_led | ioctl_download | (cas_active & cas_motor));

//////////////////   VIDEO   //////////////////

wire [7:0] osd_r_o, osd_g_o, osd_b_o;

// cassette progress bar (OSD option), drawn under the OSD
wire [5:0] bar_r, bar_g, bar_b;

tape_bar tape_bar
(
	.clk(clk_sys),
	.enable(cfg_tape_bar),
	.playing(cas_active & cas_motor),
	.progress(cas_progress),
	.hs_n(HSync),
	.vs_n(VSync),
	.r_in(R_O),
	.g_in(G_O),
	.b_in(B_O),
	.r_out(bar_r),
	.g_out(bar_g),
	.b_out(bar_b)
);

osd #(.OUT_COLOR_DEPTH(8), .BIG_OSD(BIG_OSD)) osd
(
	.clk_sys(clk_sys),
	.ce(1'b0),
	.rotate(2'b00),
	.SPI_DI(SPI_DI),
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
	.HBlank(1'b0),
	.VBlank(1'b0),
	.R_in({bar_r, bar_r[5:4]}),
	.G_in({bar_g, bar_g[5:4]}),
	.B_in({bar_b, bar_b[5:4]}),
	.HSync(HSync),
	.VSync(VSync),
	.R_out(osd_r_o),
	.G_out(osd_g_o),
	.B_out(osd_b_o)
);

wire [7:0] r, g, b;
wire       cs, hs, vs, bl;

RGBtoYPbPr #(8) RGBtoYPbPr
(
	.clk      ( clk_sys ),
	.ena      ( ypbpr   ),
	.red_in   ( osd_r_o ),
	.green_in ( osd_g_o ),
	.blue_in  ( osd_b_o ),
	.hs_in    ( HSync   ),
	.vs_in    ( VSync   ),
	.cs_in    ( ~(HSync ^ VSync) ),
	.hb_in    ( Blank   ),
	.vb_in    ( 1'b0    ),
	.red_out  ( r       ),
	.green_out( g       ),
	.blue_out ( b       ),
	.hs_out   ( hs      ),
	.vs_out   ( vs      ),
	.cs_out   ( cs      ),
	.hb_out   ( bl      )
);

always @(posedge clk_sys) begin
	VGA_R <= r[7:8-VGA_BITS];
	VGA_G <= g[7:8-VGA_BITS];
	VGA_B <= b[7:8-VGA_BITS];
	// a minimig vga->scart cable expects a composite sync signal on the VGA_HS output.
	// and VCC on VGA_VS (to switch into rgb mode)
	VGA_HS <= ((~no_csync & scandoubler_disable) || ypbpr)? cs : hs;
	VGA_VS <= ((~no_csync & scandoubler_disable) || ypbpr)? 1'b1 : vs;
end

`ifdef USE_HDMI
i2c_master #(22_000_000) i2c_master (
	.CLK         (clk_sys),
	.I2C_START   (i2c_start),
	.I2C_READ    (i2c_read),
	.I2C_ADDR    (i2c_addr),
	.I2C_SUBADDR (i2c_subaddr),
	.I2C_WDATA   (i2c_dout),
	.I2C_RDATA   (i2c_din),
	.I2C_END     (i2c_end),
	.I2C_ACK     (i2c_ack),

	//I2C bus
	.I2C_SCL     (HDMI_SCL),
	.I2C_SDA     (HDMI_SDA)
);

assign HDMI_PCLK = hdmiclk;
always @(posedge hdmiclk) begin
	HDMI_R <= r;
	HDMI_G <= g;
	HDMI_B <= b;
	HDMI_HS <= hs;
	HDMI_VS <= vs;
	HDMI_DE <= !bl;
end
`endif

`ifdef I2S_AUDIO
i2s i2s (
	.reset(~msx_reset_n),
	.clk(clk_sys),
	.clk_rate(32'd21_480_000),
	.sclk(I2S_BCK),
	.lrclk(I2S_LRCK),
	.sdata(I2S_DATA),
	.left_chan({1'b0, audio, 1'b0}),
	.right_chan({1'b0, audio, 1'b0})
);

`ifdef I2S_AUDIO_HDMI
assign HDMI_MCLK = 0;
always @(posedge clk_sys) begin
	HDMI_BCK <= I2S_BCK;
	HDMI_LRCK <= I2S_LRCK;
	HDMI_SDATA <= I2S_DATA;
end
`endif
`endif

`ifdef SPDIF_AUDIO
spdif spdif (
	.rst_i(1'b0),
	.clk_i(clk_sys),
	.clk_rate_i(32'd21_480_000),
	.spdif_o(SPDIF),
	.sample_i({2{1'b0, audio, 1'b0}})
);
`endif

endmodule
