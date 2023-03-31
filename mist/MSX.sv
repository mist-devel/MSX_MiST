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
	output        UART_TX,

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

assign LED  = ~leds[0];

`include "build_id.v"
parameter CONF_STR = {
	"MSX;;",
	"S0,VHD,Mount;",
	"O2,CPU Clock,Normal,Turbo;",
	"O3,Slot1,Empty,MegaSCC+ 1MB;",
	"O45,Slot2,Empty,MegaSCC+ 2MB,MegaRAM 1MB,MegaRAM 2MB;",    
	"O6,RAM,2048kB,4096kB;",
	"O7,Swap joysticks,No,Yes;",
	"O8,VGA Output,CRT,LCD;",
	"O9,Tape sound,OFF,ON;",
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
	.locked(locked)
);

assign SDRAM_CLK = memclk;

//////////////////   MiST I/O   ///////////////////
wire  [7:0] joy_0;
wire  [7:0] joy_1;
wire  [1:0] buttons;
wire [63:0] status;
wire        ypbpr;
wire        no_csync;
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
wire [63:0] img_size;

wire        ps2_kbd_clk;
wire        ps2_kbd_data;

wire  [8:0] mouse_x;
wire  [8:0] mouse_y;
wire  [7:0] mouse_flags;
wire        mouse_strobe;

wire [63:0] rtc;

user_io #(.STRLEN($size(CONF_STR)>>3), .PS2DIV(100)) user_io
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

        .joystick_0(joy_0),
        .joystick_1(joy_1),

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
        .sd_din(sd_buff_din),
        .sd_dout(sd_buff_dout),
        .sd_dout_strobe(sd_buff_wr),

        .ps2_kbd_clk(ps2_kbd_clk),
        .ps2_kbd_data(ps2_kbd_data),

        .mouse_x(mouse_x),
        .mouse_y(mouse_y),
        .mouse_flags(mouse_flags),
        .mouse_strobe(mouse_strobe),

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
wire [7:0] leds;

reg reset;
reg  [27:0] img_reset_cnt = 0;
wire resetW = status[0] | buttons[1] | img_reset_cnt != 0;

always @(posedge clk_sys) begin
	if (img_reset_cnt != 0) img_reset_cnt <= img_reset_cnt - 1'd1;
	if (img_mounted) img_reset_cnt <= 28'h2000000;
	reset <= resetW;
	dipsw <= {1'b0, ~status[6], ~status[5:4], ~status[3], ~scandoubler_disable & status[8], scandoubler_disable, ~status[2]};
end

always_comb begin
    for (integer i=0; i<=5; i++) begin
        msx_joya[i] <= mouse_en ? (mouse[i] ? 1'bZ : mouse[i]) : (~joya[i] & ~msx_stra ? joya[i] : 1'bZ);
        msx_joyb[i] <= (~joyb[i] & ~msx_strb ? joyb[i] : 1'bZ);
    end
end

reg        mouse_en = 0;
reg  [5:0] mouse;

always @(posedge clk_sys) begin

    reg        stra_d;
    reg  [8:0] mouse_x_latch;
    reg  [8:0] mouse_y_latch;
    reg  [1:0] mouse_state;
    reg [17:0] mouse_timeout;

    if (reset) begin
        mouse_en <= 0;
        mouse_state <= 0;
    end
    else if (mouse_strobe) mouse_en <= 1;
    else if (~&joya) mouse_en <= 0;

    if (mouse_strobe) begin
        mouse_x_latch <= ~mouse_x + 1'd1; //2nd complement of x
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

wire  [5:0] Dac_SL, Dac_SR;
wire        Cmt_Out;

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
        .pLed       (leds),

//        -- Video, Audio/CMT ports
        .CmtIn      (UART_RX),
        .CmtOut     (Cmt_Out),
        .pDac_VR    (R_O),      // RGB_Red / Svideo_C
        .pDac_VG    (G_O),      // RGB_Grn / Svideo_Y
        .pDac_VB    (B_O),      // RGB_Blu / CompositeVideo
        .pVideoHS_n (HSync),    // HSync(RGB15K, VGA31K)
        .pVideoVS_n (VSync),    // VSync(RGB15K, VGA31K)

        .pDac_SL    (Dac_SL),
        .pDac_SR    (Dac_SR),

        .iRTC       (rtc),
		.oMidi      (UART_TX)
);

assign AUDIO_L = Dac_SL[0];
assign AUDIO_R = status[9] ? Cmt_Out : Dac_SR[0];

//////////////////   VIDEO   //////////////////
wire  [5:0] R_O;
wire  [5:0] G_O;
wire  [5:0] B_O;
wire        HSync, VSync;

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

wire [5:0] r, g, b;
wire       cs, hs, vs;

RGBtoYPbPr #(6) RGBtoYPbPr
(
	.clk      ( clk_sys ),
	.ena      ( ypbpr   ),
	.red_in   ( osd_r_o ),
	.green_in ( osd_g_o ),
	.blue_in  ( osd_b_o ),
	.hs_in    ( HSync   ),
	.vs_in    ( VSync   ),
	.cs_in    ( ~(HSync ^ VSync) ),
	.red_out  ( r       ),
	.green_out( g       ),
	.blue_out ( b       ),
	.hs_out   ( hs      ),
	.vs_out   ( vs      ),
	.cs_out   ( cs      )
);

always @(posedge clk_sys) begin
	VGA_R <= r;
	VGA_G <= g;
	VGA_B <= b;
	// a minimig vga->scart cable expects a composite sync signal on the VGA_HS output.
	// and VCC on VGA_VS (to switch into rgb mode)
	VGA_HS <= ((~no_csync & scandoubler_disable) || ypbpr)? cs : hs;
	VGA_VS <= ((~no_csync & scandoubler_disable) || ypbpr)? 1'b1 : vs;
end

endmodule
