// Black-box stubs of the VHDL entities, for linting the Verilog/SV top level
module pll(input inclk0, output c0, output c1, output c2, output locked);
endmodule
module msx2_core #(parameter MSX1 = 0, parameter SIM_FAST = 0)(
  input clk21m, input memclk, input reset_n, input pll_locked,
  output pMemCke, output pMemCs_n, output pMemRas_n, output pMemCas_n, output pMemWe_n,
  output pMemUdq, output pMemLdq, output pMemBa1, output pMemBa0, output [12:0] pMemAdr, inout [15:0] pMemDat,
  inout pPs2Clk, inout pPs2Dat,
  inout [5:0] pJoyA, output pStrA, inout [5:0] pJoyB, output pStrB,
  output [5:0] pVideoR, output [5:0] pVideoG, output [5:0] pVideoB, output pVideoHS_n, output pVideoVS_n, output pVideoBlank,
  output [13:0] audio_o, output pDacOut,
  input CmtIn, output CmtOut, output CmtMotor,
  input [63:0] iRTC,
  output fdc_cs, output fdc_rd, output fdc_wr, output [2:0] fdc_adr, output [7:0] fdc_dbo, input [7:0] fdc_dbi,
  output cpu_ce, output msx_reset, output disk_on,
  input dl_download, input [7:0] dl_index, input dl_wr, input [26:0] dl_addr, input [7:0] dl_data,
  input eject1, input eject2, output sys_rom_ok,
  input [2:0] cfg_speed, input [2:0] cfg_ram, input [2:0] cfg_mapper1, input [2:0] cfg_mapper2,
  input cfg_disk, input cfg_music, input [2:0] cfg_psg_vol, input [2:0] cfg_scc_vol, input [2:0] cfg_fm_vol,
  input cfg_tape_snd, input [1:0] cfg_vmode, input cfg_vga, input cfg_lcd, input [1:0] cfg_kbd, input cfg_v9958, input cfg_ram30
);
endmodule
