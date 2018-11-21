//============================================================================
//  MSX top level for MiST
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

module MSX
(
    input         CLOCK_27[0],   // Input clock 27 MHz

    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    output        LED,

    output        AUDIO_L,
    output        AUDIO_R,

    input         UART_RX,

    input         SPI_SCK,
    output        SPI_DO,
    input         SPI_DI,
    input         SPI_SS2,
    input         SPI_SS3,
    input         CONF_DATA0,

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
    output        SDRAM_CKE
);

assign LED  = 1'b1;

`include "build_id.v"
parameter CONF_STR = {
	"MSX;;",
	"O2,CPU Clock,Normal,Turbo;",
	"O3,Slot1,Empty,MegaSCC+ 1MB;",
	"O45,Slot2,Empty,MegaSCC+ 2MB,MegaRAM 1MB,MegaRAM 2MB;",    
    "O6,RAM,2048kB,4096kB;",
	"O7,Swap joysticks,No,Yes;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};


////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys;
wire memclk;

pll pll
(
	.inclk0(CLOCK_27[0]),
	.c0(clk_sys),
    .c1(memclk),
	.c2(SDRAM_CLK),
	.locked(locked)
);

wire reset = status[0] | buttons[1] | ~locked;

//////////////////   MiST I/O   ///////////////////
wire  [7:0] joy_0;
wire  [7:0] joy_1;
wire  [1:0] buttons;
wire [31:0] status;
wire        ypbpr;
wire        scandoubler_disable;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_conf;
wire        sd_ack;
wire        sd_ack_conf;
wire        sd_sdhc;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [31:0] img_size;

wire        ps2_kbd_clk;
wire        ps2_kbd_data;

mist_io #(.STRLEN($size(CONF_STR)>>3), .PS2DIV(1500)) mist_io
(
        .clk_sys(clk_sys),
        .CONF_DATA0(CONF_DATA0),
        .SPI_SCK(SPI_SCK),
        .SPI_DI(SPI_DI),
        .SPI_DO(SPI_DO),

        .conf_str(CONF_STR),

        .status(status),
        .scandoubler_disable(scandoubler_disable),
        .ypbpr(ypbpr),
        .buttons(buttons),
        .joystick_0(joy_0),
        .joystick_1(joy_1),

        .sd_conf(sd_conf),
        .sd_ack(sd_ack),
        .sd_ack_conf(sd_ack_conf),
        .sd_sdhc(sd_sdhc),
        .sd_rd(sd_rd),
        .sd_wr(sd_wr),
        .sd_lba(sd_lba),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_din(sd_buff_din),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_wr(sd_buff_wr),

        .ps2_kbd_clk(ps2_kbd_clk),
        .ps2_kbd_data(ps2_kbd_data),

        // unused
        .switches(),
        .ps2_mouse_clk(),
        .ps2_mouse_data(),
        .joystick_analog_0(),
        .joystick_analog_1()
);

sd_card sd_card
(
        .clk_sys(clk_sys),
        .img_mounted(img_mounted),
        .img_size(img_size),
        .sd_conf(sd_conf),
        .sd_ack(sd_ack),
        .sd_ack_conf(sd_ack_conf),
        .sd_sdhc(sd_sdhc),
        .sd_rd(sd_rd),
        .sd_wr(sd_wr),
        .sd_lba(sd_lba),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_din(sd_buff_din),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_wr(sd_buff_wr),
        .allow_sdhc(1),
        .sd_sck(Sd_Ck),
        .sd_cs(Sd_Dt[3]),
        .sd_sdi(Sd_Cm),
        .sd_sdo(Sd_Dt[0])
);

wire [5:0] audio_l;
wire [5:0] audio_r;

wire [5:0] joya = status[7] ? ~joy_1[5:0] : ~joy_0[5:0];
wire [5:0] joyb = status[7] ? ~joy_0[5:0] : ~joy_1[5:0];
wire [5:0] msx_joya;
wire [5:0] msx_joyb;
wire       msx_stra;
wire       msx_strb;

wire       Sd_Ck;
wire       Sd_Cm;
wire [3:0] Sd_Dt;

wire       msx_ps2_kbd_clk = ps2_kbd_clk;
wire       msx_ps2_kbd_data = (ps2_kbd_data == 1'b0 ? ps2_kbd_data : 1'bZ);
reg  [7:0] dipsw;

always @(posedge clk_sys) begin
    dipsw <= {1'b0, ~status[6], ~status[5:4], ~status[3], ~scandoubler_disable, scandoubler_disable, ~status[2]};
end

always_comb begin
    for (integer i=0; i<=5; i++) begin
        msx_joya[i] <= (~joya[i] & ~msx_stra ? joya[i] : 1'bZ);
        msx_joyb[i] <= (~joyb[i] & ~msx_strb ? joyb[i] : 1'bZ);
    end
end

emsx_top emsx
(
//        -- Clock, Reset ports
        .clk21m     (clk_sys),
        .memclk     (memclk),
        .pSltRst_n  (~reset),
//        -- SD-RAM ports
        .pMemAdr   ( SDRAM_A ),
        .pMemDat   ( SDRAM_DQ ),
        .pMemLdq   ( SDRAM_DQML ),
        .pMemUdq   ( SDRAM_DQMH ),
        .pMemWe_n  ( SDRAM_nWE ),
        .pMemCas_n ( SDRAM_nCAS ),
        .pMemRas_n ( SDRAM_nRAS ),
        .pMemCs_n  ( SDRAM_nCS ),
        .pMemBa0   ( SDRAM_BA[0] ),
        .pMemBa1   ( SDRAM_BA[1] ),
        .pMemCke   ( SDRAM_CKE ),

//        -- PS/2 keyboard ports
        .pPs2Clk   (msx_ps2_kbd_clk),
        .pPs2Dat   (msx_ps2_kbd_data),

//        -- Joystick ports (Port_A, Port_B)
        .pJoyA      ( {msx_joya[5:4], msx_joya[0], msx_joya[1], msx_joya[2], msx_joya[3]} ),
        .pStra      ( msx_stra ),
        .pJoyB      ( {msx_joyb[5:4], msx_joyb[0], msx_joyb[1], msx_joyb[2], msx_joyb[3]} ),
        .pStrb      ( msx_strb ),

//        -- SD/MMC slot ports
        .pSd_Ck     (Sd_Ck),
        .pSd_Cm     (Sd_Cm),
        .pSd_Dt     (Sd_Dt),

//        -- DIP switch, Lamp ports
        .pDip       (dipsw),

//        -- Video, Audio/CMT ports
        .pDac_VR    (R_O),      // RGB_Red / Svideo_C
        .pDac_VG    (G_O),      // RGB_Grn / Svideo_Y
        .pDac_VB    (B_O),      // RGB_Blu / CompositeVideo
        .pVideoHS_n (HSync),    // HSync(RGB15K, VGA31K)
        .pVideoVS_n (VSync),    // VSync(RGB15K, VGA31K)

        .pDac_SL    (audio_l),
        .pDac_SR    (audio_r)
);

//////////////////   VIDEO   //////////////////
wire  [5:0] R_O;
wire  [5:0] G_O;
wire  [5:0] B_O;
wire        HSync, VSync, CSync;

wire [5:0] osd_r_o, osd_g_o, osd_b_o;

osd osd
(
    .clk_sys(clk_sys),
    .SPI_DI(SPI_DI),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .R_in(R_O),
    .G_in(G_O),
    .B_in(B_O),
    .HSync(HSync),
    .VSync(VSync),
    .R_out(osd_r_o),
    .G_out(osd_g_o),
    .B_out(osd_b_o)
    );

wire [5:0] Y, Pb, Pr;

rgb2ypbpr rgb2ypbpr 
(
	.red   ( osd_r_o ),
	.green ( osd_g_o ),
	.blue  ( osd_b_o ),
	.y     ( Y       ),
	.pb    ( Pb      ),
	.pr    ( Pr      )
);

assign VGA_R = ypbpr?Pr:osd_r_o;
assign VGA_G = ypbpr? Y:osd_g_o;
assign VGA_B = ypbpr?Pb:osd_b_o;
assign CSync = ~(HSync ^ VSync);
// a minimig vga->scart cable expects a composite sync signal on the VGA_HS output.
// and VCC on VGA_VS (to switch into rgb mode)
assign      VGA_HS = (scandoubler_disable || ypbpr) ? CSync : HSync;
assign      VGA_VS = (scandoubler_disable || ypbpr)? 1'b1 : VSync;

//////////////////   AUDIO   //////////////////
dac dac_l
(
	.clk(clk_sys),
	.audio_in(audio_l),
	.dac_out(AUDIO_L)
);

dac dac_r
(
	.clk(clk_sys),
	.audio_in(audio_r),
	.dac_out(AUDIO_R)
);

endmodule
