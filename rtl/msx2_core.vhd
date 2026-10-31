--
-- msx2_core.vhd
--   MSX2 computer core for the MiST board.
--
--   Derived from emsx_top.vhd of the OCM-PLD Pack v3.9.1 (ESE MSX-SYSTEM3 /
--   1chipMSX) as ported to MiST by gyurco. See the original copyright notice
--   below. Changes for the "MSX2 MiST" core (2026):
--     * removed the IPL-ROM, the MegaSD (SD card / hard disk) interface and
--       the EPCS BIOS loader; system ROMs and cartridges are now uploaded by
--       the MiST IO controller into SDRAM (rom_loader.vhd)
--     * removed the OCM specific hardware: switched I/O ports (40h-4Fh),
--       Kanji ROM, extra mapper, ESP8266 WiFi, MIDI, turboR PCM, S1990,
--       port F2h/F4h, ESE-SCC/ESE-RAM cartridges, LEDs and DIP switches
--     * all settings come from the MiST OSD (cfg_* ports)
--     * slot map of a real MSX2 (see below), power-on state of a real MSX
--     * ROM cartridges with mappers in slot 1 and 2 (cart_slot.vhd)
--     * Philips style floppy disk interface (WD2793 outside of this entity)
--     * selectable memory mapper size, CPU speed and keyboard layout
--
--   Slot map:
--     0   (0-0) MAIN-ROM 32K           [0-2 MSX-MUSIC 16K when enabled; slot 0 is
--                                        expanded only in this case]
--     1         cartridge slot 1
--     2         cartridge slot 2
--     3-0       empty (RAM here when cfg_ram30 = '1', like Sony/Panasonic)
--     3-1       SUB-ROM 16K (0000h-3FFFh)
--     3-2       RAM (memory mapper, 64K-4M), like the Philips machines
--     3-3       DISK-ROM 16K (4000h-7FFFh) + WD2793 at 7FF8h-7FFFh (Philips)
--
--   MSX1 (generic MSX1 = 1):
--     3         64K RAM in a slot that is not expanded, like most MSX1
--               (cfg_ram30 = '1': slot 3 expanded with the RAM in 3-2)
--     2         the disk interface works like a VY-0010 cartridge plugged
--               in slot 2: it is there only when slot 2 has no cartridge
--
--   SDRAM map (25 bit byte address, 32 MB):
--     0x0000000-0x03FFFFF  memory mapper RAM (4 MB)
--     0x0600000-0x061FFFF  system ROMs (main 0x00000, sub 0x08000,
--                          disk 0x0C000, MSX-MUSIC 0x10000)
--     0x0700000-0x07FFFFF  VRAM (handled by the VDP access path)
--     0x1000000-0x17FFFFF  cartridge slot 1
--     0x1800000-0x1FFFFFF  cartridge slot 2
--
-- -------------------------------------------------------------------------
-- emsx_top.vhd
--   ESE MSX-SYSTEM3 / MSX clone on a Cyclone FPGA (ALTERA)
--   Revision 1.00
--
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
---------------------------------------------------------------------------------
-- OCM-PLD Pack v3.9.1 by KdL (2022.09.24) / MSX2+ Stable Release for 1chipMSX
-- Special thanks to t.hara, caro, mygodess & all MRC users (http://www.msx.org)
---------------------------------------------------------------------------------
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
    use work.vdp_package.all;

entity msx2_core is
    generic(
        SIM_FAST        : boolean := false;                         -- simulation only: short power-on timers
        MSX1            : integer := 0                              -- 1: MSX1 (64K RAM without mapper, no RTC,
                                                                    --    no SUB-ROM, MSX1 file layout)
    );
    port(
        -- Clock, Reset
        clk21m          : in    std_logic;                          -- 21.48MHz
        memclk          : in    std_logic;                          -- 85.92MHz = 21.48MHz x 4
        reset_n         : in    std_logic;                          -- reset request (active low)
        pll_locked      : in    std_logic := '1';                   -- SDRAM init waits for stable clocks

        -- SDRAM
        pMemCke         : out   std_logic;
        pMemCs_n        : out   std_logic;
        pMemRas_n       : out   std_logic;
        pMemCas_n       : out   std_logic;
        pMemWe_n        : out   std_logic;
        pMemUdq         : out   std_logic;
        pMemLdq         : out   std_logic;
        pMemBa1         : out   std_logic;
        pMemBa0         : out   std_logic;
        pMemAdr         : out   std_logic_vector( 12 downto 0 );
        pMemDat         : inout std_logic_vector( 15 downto 0 );

        -- PS/2 keyboard
        pPs2Clk         : inout std_logic;
        pPs2Dat         : inout std_logic;

        -- Joystick ports (Port_A, Port_B)
        pJoyA           : inout std_logic_vector(  5 downto 0 );
        pStrA           : out   std_logic;
        pJoyB           : inout std_logic_vector(  5 downto 0 );
        pStrB           : out   std_logic;

        -- Video
        pVideoR         : out   std_logic_vector(  5 downto 0 );
        pVideoG         : out   std_logic_vector(  5 downto 0 );
        pVideoB         : out   std_logic_vector(  5 downto 0 );
        pVideoHS_n      : out   std_logic;
        pVideoVS_n      : out   std_logic;
        pVideoBlank     : out   std_logic;

        -- Audio
        audio_o         : out   std_logic_vector( 13 downto 0 );
        pDacOut         : out   std_logic;                          -- 1 bit PWM DAC

        -- Cassette
        CmtIn           : in    std_logic;
        CmtOut          : out   std_logic;
        CmtMotor        : out   std_logic;                          -- '1' = motor on

        -- Real Time Clock
        iRTC            : in    std_logic_vector( 63 downto 0 );

        -- Floppy disk controller (WD2793, outside)
        fdc_cs          : out   std_logic;                          -- CPU accesses 7FF8h-7FFFh of slot 3-3
        fdc_rd          : out   std_logic;                          -- read strobe (level)
        fdc_wr          : out   std_logic;                          -- write strobe (level)
        fdc_adr         : out   std_logic_vector(  2 downto 0 );
        fdc_dbo         : out   std_logic_vector(  7 downto 0 );    -- data from CPU
        fdc_dbi         : in    std_logic_vector(  7 downto 0 );    -- data to CPU
        cpu_ce          : out   std_logic;                          -- one pulse per CPU clock
        msx_reset       : out   std_logic;                          -- internal reset
        disk_on         : out   std_logic;                          -- disk interface present

        -- File upload from the MiST IO controller (data_io)
        dl_download     : in    std_logic;
        dl_index        : in    std_logic_vector(  7 downto 0 );
        dl_wr           : in    std_logic;
        dl_addr         : in    std_logic_vector( 26 downto 0 );
        dl_data         : in    std_logic_vector(  7 downto 0 );
        eject1          : in    std_logic;
        eject2          : in    std_logic;
        sys_rom_ok      : out   std_logic;                          -- main and sub ROM present

        -- Configuration (OSD)
        cfg_speed       : in    std_logic_vector(  2 downto 0 );    -- 3.58/5.37/6.96/8.06/10.74MHz
        cfg_ram         : in    std_logic_vector(  2 downto 0 );    -- see mapper.vhd
        cfg_mapper1     : in    std_logic_vector(  2 downto 0 );    -- 0=auto, see cart_slot.vhd
        cfg_mapper2     : in    std_logic_vector(  2 downto 0 );
        cfg_disk        : in    std_logic;                          -- '1' = disk drive enabled
        cfg_music       : in    std_logic;                          -- '1' = MSX-MUSIC enabled
        cfg_psg_vol     : in    std_logic_vector(  2 downto 0 );    -- 0=off, 7=max
        cfg_scc_vol     : in    std_logic_vector(  2 downto 0 );
        cfg_fm_vol      : in    std_logic_vector(  2 downto 0 );
        cfg_tape_snd    : in    std_logic;                          -- '1' = hear the cassette
        cfg_vmode       : in    std_logic_vector(  1 downto 0 );    -- 00=BIOS, 01=60Hz, 10=50Hz
        cfg_vga         : in    std_logic;                          -- '1' = 31kHz output
        cfg_lcd         : in    std_logic;                          -- '1' = VGA timing for LCDs
        cfg_kbd         : in    std_logic_vector(  1 downto 0 );    -- 00=US, 01=Italian, 10=Japanese
        cfg_v9958       : in    std_logic;                          -- '1' = report a V9958 VDP
        cfg_ram30       : in    std_logic                           -- MSX2: '1' = RAM in slot 3-0 instead of 3-2
                                                                    -- MSX1: '1' = slot 3 expanded, RAM in 3-2
    );
end msx2_core;

architecture RTL of msx2_core is

    -- CPU
    component t80a
        port(
            RESET_n     : in    std_logic;
            R800_mode   : in    std_logic;
            CLK_n       : in    std_logic;
            WAIT_n      : in    std_logic;
            INT_n       : in    std_logic;
            NMI_n       : in    std_logic;
            BUSRQ_n     : in    std_logic;
            M1_n        : out   std_logic;
            MREQ_n      : out   std_logic;
            IORQ_n      : out   std_logic;
            RD_n        : out   std_logic;
            WR_n        : out   std_logic;
            RFSH_n      : out   std_logic;
            HALT_n      : out   std_logic;
            BUSAK_n     : out   std_logic;
            A           : out   std_logic_vector( 15 downto 0 );
            D           : inout std_logic_vector(  7 downto 0 )
        );
    end component;

    component mapper
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            mem         : in    std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );
            size        : in    std_logic_vector(  2 downto 0 );
            ramreq      : out   std_logic;
            ramwrt      : out   std_logic;
            ramadr      : out   std_logic_vector( 21 downto 0 );
            ramdbi      : in    std_logic_vector(  7 downto 0 );
            ramdbo      : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    component eseps2
        port (
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            Kmap        : in    std_logic;
            KmapIt      : in    std_logic;
            Caps        : inout std_logic;
            Kana        : inout std_logic;
            Paus        : inout std_logic;
            Scro        : inout std_logic;
            Reso        : inout std_logic;
            FKeys       : buffer std_logic_vector(  7 downto 0 );
            pPs2Clk     : inout std_logic;
            pPs2Dat     : inout std_logic;
            PpiPortC    : in     std_logic_vector(  7 downto 0 );
            pKeyX       : out    std_logic_vector(  7 downto 0 );
            CmtScro     : inout std_logic
        );
    end component;

    component rtc_mist
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            rtc         : in    std_logic_vector( 63 downto 0 );
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 )
        );
    end component;

    component vdp
        port(
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            req             : in    std_logic;
            ack             : out   std_logic;
            wrt             : in    std_logic;
            adr             : in    std_logic_vector( 15 downto 0 );
            dbi             : out   std_logic_vector(  7 downto 0 );
            dbo             : in    std_logic_vector(  7 downto 0 );
            int_n           : out   std_logic;
            pRamOe_n        : out   std_logic;
            pRamWe_n        : out   std_logic;
            pRamAdr         : out   std_logic_vector( 16 downto 0 );
            pRamDbi         : in    std_logic_vector( 15 downto 0 );
            pRamDbo         : out   std_logic_vector(  7 downto 0 );
            VdpSpeedMode    : in    std_logic;
            RatioMode       : in    std_logic_vector(  2 downto 0 );
            centerYJK_R25_n : in    std_logic;
            pVideoR         : out   std_logic_vector(  5 downto 0 );
            pVideoG         : out   std_logic_vector(  5 downto 0 );
            pVideoB         : out   std_logic_vector(  5 downto 0 );
            pVideoHS_n      : out   std_logic;
            pVideoVS_n      : out   std_logic;
            pVideoCS_n      : out   std_logic;
            pVideoDHClk     : out   std_logic;
            pVideoDLClk     : out   std_logic;
            pVideoBlank     : out   std_logic;
            DispReso        : in    std_logic;
            ntsc_pal_type   : in    std_logic;
            forced_v_mode   : in    std_logic;
            legacy_vga      : in    std_logic;
            VDP_ID          : in    std_logic_vector(  4 downto 0 );
            OFFSET_Y        : in    std_logic_vector(  6 downto 0 )
        );
    end component;

    component psg
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );
            joya        : inout std_logic_vector(  5 downto 0 );
            stra        : out   std_logic;
            joyb        : inout std_logic_vector(  5 downto 0 );
            strb        : out   std_logic;
            kana        : out   std_logic;
            cmtin       : in    std_logic;
            keymode     : in    std_logic;
            wave        : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    component cart_slot
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );
            ramreq      : out   std_logic;
            ramadr      : out   std_logic_vector( 22 downto 0 );
            ramdbi      : in    std_logic_vector(  7 downto 0 );
            mapper      : in    std_logic_vector(  2 downto 0 );
            rom_mask    : in    std_logic_vector( 22 downto 0 );
            rom_last    : in    std_logic_vector( 22 downto 0 );
            plain_base  : in    std_logic_vector(  1 downto 0 );
            wave        : out   std_logic_vector( 14 downto 0 )
        );
    end component;

    component rom_loader
        generic(
            MSX1            : integer := 0
        );
        port(
            clk21m          : in    std_logic;
            dl_download     : in    std_logic;
            dl_index        : in    std_logic_vector(  7 downto 0 );
            dl_wr           : in    std_logic;
            dl_addr         : in    std_logic_vector( 26 downto 0 );
            dl_data         : in    std_logic_vector(  7 downto 0 );
            wr_req          : out   std_logic;
            wr_adr          : out   std_logic_vector( 24 downto 0 );
            wr_dat          : out   std_logic_vector(  7 downto 0 );
            rom_main_ok     : out   std_logic;
            rom_sub_ok      : out   std_logic;
            rom_disk_ok     : out   std_logic;
            rom_music_ok    : out   std_logic;
            eject1          : in    std_logic;
            eject2          : in    std_logic;
            cart1_present   : out   std_logic;
            cart1_mapper    : out   std_logic_vector(  2 downto 0 );
            cart1_mask      : out   std_logic_vector( 22 downto 0 );
            cart1_last      : out   std_logic_vector( 22 downto 0 );
            cart1_base      : out   std_logic_vector(  1 downto 0 );
            cart2_present   : out   std_logic;
            cart2_mapper    : out   std_logic_vector(  2 downto 0 );
            cart2_mask      : out   std_logic_vector( 22 downto 0 );
            cart2_last      : out   std_logic_vector( 22 downto 0 );
            cart2_base      : out   std_logic_vector(  1 downto 0 )
        );
    end component;

    component eseopll
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            enawait     : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );
            wav         : out   std_logic_vector(  9 downto 0 )
            );
    end component;

    component esepwm
        generic (
            msbi    : integer
        );
        port(
            clk     : in    std_logic;
            reset   : in    std_logic;
            DACin   : in    std_logic_vector( msbi downto 0 );
            DACout  : out   std_logic
        );
    end component;

    component scc_mix_mul
        port(
            a           : in    std_logic_vector( 15 downto 0 );    -- 16bits signed
            b           : in    std_logic_vector(  2 downto 0 );    --  3bits unsigned
            c           : out   std_logic_vector( 18 downto 0 )     -- 19bits signed
        );
    end component;

    component lpf2
        generic (
            msbi    : integer
        );
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            clkena  : in    std_logic;
            idata   : in    std_logic_vector( msbi downto 0 );
            odata   : out   std_logic_vector( msbi downto 0 )
        );
    end component;

    component interpo
        generic (
            msbi    : integer
        );
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            clkena  : in    std_logic;
            idata   : in    std_logic_vector( msbi downto 0 );
            odata   : out   std_logic_vector( msbi downto 0 )
        );
    end component;

    -- Settings latched while in reset
    signal  Slot0Mode       : std_logic := '0';                     -- '1' = slot 0 expanded (MSX-MUSIC)
    signal  DiskEna         : std_logic := '0';                     -- '1' = disk ROM + FDC in slot 3-3
    signal  RamSub          : std_logic_vector(  1 downto 0 ) := "10";  -- subslot of slot 3 with the RAM
    signal  Slot3Exp        : std_logic := '1';                     -- '1' = slot 3 is expanded
    signal  DiskSlt         : std_logic;                            -- the CPU is in the slot of the disk interface
    signal  CustomSpeed     : std_logic_vector(  3 downto 0 ) := "0010";
    signal  Kmap            : std_logic;
    signal  KmapIt          : std_logic;

    -- Clock, Reset control signals
    signal  cpuclk          : std_logic := '1';
    signal  clkena          : std_logic := '0';
    signal  clkdiv          : std_logic_vector(  1 downto 0 ) := "10";
    signal  ff_clksel       : std_logic := '0';
    signal  ff_clksel5m_n   : std_logic := '1';
    signal  reset           : std_logic := '1';
    signal  RstSeq          : std_logic_vector(  4 downto 0 ) := (others => '0');
    signal  ff_locked       : std_logic_vector(  1 downto 0 ) := "00";
    signal  FreeCounter     : std_logic_vector( 15 downto 0 ) := (others => '0');
    signal  iCpuClk         : std_logic;
    signal  ff_cpuclk_d     : std_logic := '0';
    signal  power_on_reset  : std_logic := '0';
    signal  cpu_reset_n     : std_logic;
    signal  dac_reset       : std_logic;
    signal  xSltRst_n       : std_logic := '0';

    -- CPU bus
    signal  CpuM1_n         : std_logic;
    signal  CpuRfsh_n       : std_logic;
    signal  CpuMerq_n       : std_logic;
    signal  CpuIorq_n       : std_logic;
    signal  CpuRd_n         : std_logic;
    signal  CpuWr_n         : std_logic;
    signal  CpuA            : std_logic_vector( 15 downto 0 );
    signal  CpuD            : std_logic_vector(  7 downto 0 );
    signal  CpuInt_n        : std_logic;
    signal  BusDir_o        : std_logic;

    signal  iSltRfsh_n      : std_logic;
    signal  iSltMerq_n      : std_logic;
    signal  iSltIorq_n      : std_logic;
    signal  xSltRd_n        : std_logic;
    signal  xSltWr_n        : std_logic;
    signal  iSltAdr         : std_logic_vector( 15 downto 0 );
    signal  iSltDat         : std_logic_vector(  7 downto 0 );
    signal  dlydbi          : std_logic_vector(  7 downto 0 );
    signal  wait_n_s        : std_logic := '1';

    -- Internal bus signals (common)
    signal  req             : std_logic;
    signal  ack             : std_logic;
    signal  iack            : std_logic;
    signal  mem             : std_logic;
    signal  wrt             : std_logic;
    signal  adr             : std_logic_vector( 15 downto 0 );
    signal  dbi             : std_logic_vector(  7 downto 0 );
    signal  dbo             : std_logic_vector(  7 downto 0 );

    -- Primary, Expansion slot signals
    signal  ExpDbi          : std_logic_vector(  7 downto 0 );
    signal  ExpSlot0        : std_logic_vector(  7 downto 0 );
    signal  ExpSlot3        : std_logic_vector(  7 downto 0 );
    signal  PriSltNum       : std_logic_vector(  1 downto 0 );
    signal  ExpSltNum0      : std_logic_vector(  1 downto 0 );
    signal  ExpSltNum3      : std_logic_vector(  1 downto 0 );

    -- Slot decode signals
    signal  iSltMap         : std_logic;
    signal  jSltMem         : std_logic;
    signal  iSltCart1       : std_logic;
    signal  jSltCart1       : std_logic;
    signal  iSltCart2       : std_logic;
    signal  jSltCart2       : std_logic;
    signal  iSltFdc         : std_logic;

    -- ROM decode signals
    signal  RomReq          : std_logic;
    signal  rom_main        : std_logic;
    signal  rom_music       : std_logic;
    signal  rom_sub         : std_logic;
    signal  rom_disk        : std_logic;

    -- Mapper RAM signals
    signal  MapReq          : std_logic;
    signal  MapDbi          : std_logic_vector(  7 downto 0 );
    signal  MapRam          : std_logic;
    signal  MapWrt          : std_logic;
    signal  MapAdr          : std_logic_vector( 21 downto 0 );
    signal  MapSize         : std_logic_vector(  2 downto 0 );

    -- PPI(8255) signals
    signal  PpiReq          : std_logic;
    signal  PpiDbi          : std_logic_vector(  7 downto 0 );
    signal  PpiPortA        : std_logic_vector(  7 downto 0 );
    signal  PpiPortB        : std_logic_vector(  7 downto 0 );
    signal  PpiPortC        : std_logic_vector(  7 downto 0 );

    signal  w_page_dec      : std_logic_vector(  3 downto 0 );
    signal  w_prislt_dec    : std_logic_vector(  3 downto 0 );
    signal  w_expslt0_dec   : std_logic_vector(  3 downto 0 );
    signal  w_expslt3_dec   : std_logic_vector(  3 downto 0 );

    -- PS/2 signals
    signal  Paus            : std_logic;
    signal  Scro            : std_logic;
    signal  Reso            : std_logic;
    signal  Kana            : std_logic;
    signal  Caps            : std_logic;
    signal  Fkeys           : std_logic_vector(  7 downto 0 );
    signal  CmtScro         : std_logic := '0';

    -- 1bit sound port signal
    alias   KeyClick        : std_logic is PpiPortC(7);

    -- RTC signals
    signal  RtcReq          : std_logic;
    signal  RtcDbi          : std_logic_vector(  7 downto 0 );

    -- VDP signals
    signal  VdpReq          : std_logic;
    signal  VdpDbi          : std_logic_vector(  7 downto 0 );
    signal  VideoDLClk      : std_logic;
    signal  VideoDHClk      : std_logic;
    signal  VideoBlank      : std_logic;
    signal  WeVdp_n         : std_logic;
    signal  VdpAdr          : std_logic_vector( 16 downto 0 );
    signal  VrmDbo          : std_logic_vector(  7 downto 0 );
    signal  VrmDbi          : std_logic_vector( 15 downto 0 );
    signal  pVdpInt_n       : std_logic;
    signal  ntsc_pal_type   : std_logic;
    signal  forced_v_mode   : std_logic;
    signal  legacy_vga      : std_logic;
    signal  Reso_v          : std_logic;
    signal  VDP_ID          : std_logic_vector(  4 downto 0 );
    constant OFFSET_Y       : std_logic_vector(  6 downto 0 ) := "0010011";
    constant vram_slot_ids  : std_logic_vector(  7 downto 0 ) := "00010000";
    signal  vram_page       : std_logic_vector(  7 downto 0 );

    -- Video signals
    signal  VideoR          : std_logic_vector( 5 downto 0 );
    signal  VideoG          : std_logic_vector( 5 downto 0 );
    signal  VideoB          : std_logic_vector( 5 downto 0 );
    signal  VideoHS_n       : std_logic;
    signal  VideoVS_n       : std_logic;
    signal  VideoCS_n       : std_logic;

    -- PSG signals
    signal  PsgReq          : std_logic;
    signal  PsgDbi          : std_logic_vector(  7 downto 0 );
    signal  PsgAmp          : std_logic_vector(  7 downto 0 );

    -- Cartridge signals
    signal  Cart1Req        : std_logic;
    signal  Cart1Ack        : std_logic;
    signal  Cart1Dbi        : std_logic_vector(  7 downto 0 );
    signal  Cart1Ram        : std_logic;
    signal  Cart1Adr        : std_logic_vector( 22 downto 0 );
    signal  Cart1Wav        : std_logic_vector( 14 downto 0 );
    signal  Cart1Map        : std_logic_vector(  2 downto 0 );

    signal  Cart2Req        : std_logic;
    signal  Cart2Ack        : std_logic;
    signal  Cart2Dbi        : std_logic_vector(  7 downto 0 );
    signal  Cart2Ram        : std_logic;
    signal  Cart2Adr        : std_logic_vector( 22 downto 0 );
    signal  Cart2Wav        : std_logic_vector( 14 downto 0 );
    signal  Cart2Map        : std_logic_vector(  2 downto 0 );

    -- loader / system ROM state
    signal  ld_wr_req       : std_logic;
    signal  ld_wr_adr       : std_logic_vector( 24 downto 0 );
    signal  ld_wr_dat       : std_logic_vector(  7 downto 0 );
    signal  rom_main_ok     : std_logic;
    signal  rom_sub_ok      : std_logic;
    signal  rom_disk_ok     : std_logic;
    signal  rom_music_ok    : std_logic;
    signal  cart1_present   : std_logic;
    signal  cart1_det       : std_logic_vector(  2 downto 0 );
    signal  cart1_mask      : std_logic_vector( 22 downto 0 );
    signal  cart1_last      : std_logic_vector( 22 downto 0 );
    signal  cart1_base      : std_logic_vector(  1 downto 0 );
    signal  cart2_present   : std_logic;
    signal  cart2_det       : std_logic_vector(  2 downto 0 );
    signal  cart2_mask      : std_logic_vector( 22 downto 0 );
    signal  cart2_last      : std_logic_vector( 22 downto 0 );
    signal  cart2_base      : std_logic_vector(  1 downto 0 );

    -- loader FIFO (write: clk21m, read: memclk)
    type    ldfifo_t is array (0 to 15) of std_logic_vector( 32 downto 0 );
    signal  ld_fifo         : ldfifo_t;
    signal  ld_wp           : std_logic_vector(  3 downto 0 ) := (others => '0');
    signal  ld_rp           : std_logic_vector(  3 downto 0 ) := (others => '0');
    signal  ld_q            : std_logic_vector( 32 downto 0 ) := (others => '0');
    signal  ld_avail_d1     : std_logic := '0';
    signal  ld_avail        : std_logic := '0';
    signal  ld_take         : std_logic;
    signal  ld_go           : std_logic := '0';
    signal  ld_adr          : std_logic_vector( 24 downto 0 );
    signal  ld_dat          : std_logic_vector(  7 downto 0 );

    -- OPLL signals
    signal  OpllReq         : std_logic;
    signal  OpllAck         : std_logic;
    signal  OpllAmp         : std_logic_vector(  9 downto 0 );
    signal  OpllEnaWait     : std_logic;

    -- Sound signals
    constant DAC_msbi       : integer := 13;
    signal  DACin           : std_logic_vector(DAC_msbi downto 0);
    signal  DACout          : std_logic;

    signal  OpllVol         : std_logic_vector(  2 downto 0 );
    signal  SccVol          : std_logic_vector(  2 downto 0 );
    signal  PsgVol          : std_logic_vector(  2 downto 0 );
    constant MstrVol        : std_logic_vector(  2 downto 0 ) := "000";

    -- External memory signals
    signal  RamReq          : std_logic;
    signal  RamAck          : std_logic;
    signal  RamDbi          : std_logic_vector(  7 downto 0 );
    signal  CpuAdr          : std_logic_vector( 24 downto 0 );
    signal  SdrRowAdr       : std_logic_vector( 24 downto 0 );    -- CPU or loader address (row phase)
    signal  SdrColAdr       : std_logic_vector( 24 downto 0 );    -- CPU or loader address (column phase)

    -- SD-RAM control signals
    signal  SdrSta          : std_logic_vector(  2 downto 0 );
    signal  SdrCmd          : std_logic_vector(  3 downto 0 );
    signal  SdrBa           : std_logic_vector(  1 downto 0 ) := "00";
    signal  SdrUdq          : std_logic;
    signal  SdrLdq          : std_logic;
    signal  SdrAdr          : std_logic_vector( 12 downto 0 ) := (others => '0');
    signal  SdrDat          : std_logic_vector( 15 downto 0 );

    constant SdrCmd_de      : std_logic_vector(  3 downto 0 ) := "1111";    -- deselect
    constant SdrCmd_pr      : std_logic_vector(  3 downto 0 ) := "0010";    -- precharge all
    constant SdrCmd_re      : std_logic_vector(  3 downto 0 ) := "0001";    -- refresh
    constant SdrCmd_ms      : std_logic_vector(  3 downto 0 ) := "0000";    -- mode register set
    constant SdrCmd_xx      : std_logic_vector(  3 downto 0 ) := "0111";    -- no operation
    constant SdrCmd_ac      : std_logic_vector(  3 downto 0 ) := "0011";    -- activate
    constant SdrCmd_rd      : std_logic_vector(  3 downto 0 ) := "0101";    -- read
    constant SdrCmd_wr      : std_logic_vector(  3 downto 0 ) := "0100";    -- write

    -- Clock divider
    signal  clkdiv3         : std_logic_vector(  1 downto 0 ) := "10";
    signal  ff_mem_seq      : std_logic_vector(  1 downto 0 ) := "00";

    -- free run counter
    signal  ff_clk21m_cnt   : std_logic_vector( 20 downto 0 ) := (others => '0');

    -- DRAM arbiter
    signal  w_wrt_req       : std_logic;

    -- SD-RAM controller
    signal  ff_sdr_seq      : std_logic_vector(  2 downto 0 ) := "000";
    signal  ff_rfsh_cnt     : std_logic_vector(  8 downto 0 ) := (others => '0');
    signal  ff_force_rfsh   : std_logic := '0';
    signal  w_rfsh          : std_logic;

    -- Mixer
    signal  ff_prepsg       : std_logic_vector(  8 downto 0 );
    signal  ff_prescc       : std_logic_vector( 15 downto 0 );
    signal  ff_psg          : std_logic_vector( DACin'high + 2 downto DACin'low );
    signal  ff_scc          : std_logic_vector( DACin'high + 2 downto DACin'low );
    signal  w_scc           : std_logic_vector( 18 downto 0 );
    signal  m_SccVol        : std_logic_vector(  2 downto 0 );
    signal  ff_opll         : std_logic_vector( DACin'high + 2 downto DACin'low );
    signal  ff_pre_dacin    : std_logic_vector( DACin'high + 2 downto DACin'low );
    constant c_opll_offset  : std_logic_vector( DACin'high + 2 downto DACin'low ) := ( ff_pre_dacin'high => '1', others => '0' );
    constant c_opll_zero    : std_logic_vector( OpllAmp'range ) := ( OpllAmp'high => '1', others => '0' );
    signal  TapeClick       : std_logic;

    -- Sound output filter
    signal  lpf1_wave       : std_logic_vector( DACin'high downto 0 );
    signal  lpf5_wave       : std_logic_vector( DACin'high downto 0 );

begin

    ----------------------------------------------------------------
    -- Clock generator (21.48MHz > 3.58MHz)
    ----------------------------------------------------------------

     -- Clock enabler : 3.58MHz = 21.48MHz / 6
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            clkena  <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "00" )then
                clkena <= cpuclk;
            else
                clkena <= '0';
            end if;
        end if;
    end process;

    -- CPUCLK : 3.58MHz = 21.48MHz / 6
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "10" )then
                cpuclk <= not cpuclk;
            end if;
        end if;
    end process;

    -- CPUCLK Prescaler : 21.48MHz / 6
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "00" )then
                clkdiv3 <= "10";
            else
                clkdiv3 <=  clkdiv3 - 1;
            end if;
        end if;
    end process;

    -- Turbo Clocks Prescaler : 21.48MHz / 4
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            clkdiv <=  clkdiv - 1;
        end if;
    end process;

    -- CPU speed selection (changed only during a CPU wait cycle)
    --   cfg_speed: 000=3.58MHz 001=5.37MHz 010=6.96MHz 011=8.06MHz 1xx=10.74MHz
    --   6.96/8.06MHz are obtained running at 10.74MHz with extra wait states
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '0' )then
            if( cpuclk = '0' and clkdiv = "00" and wait_n_s = '0' )then
                case cfg_speed is
                    when "000" =>                           -- 3.58MHz
                        ff_clksel5m_n   <= '1';
                        ff_clksel       <= '0';
                    when "001" =>                           -- 5.37MHz
                        ff_clksel5m_n   <= '0';
                        ff_clksel       <= '0';
                    when "010" =>                           -- 6.96MHz
                        ff_clksel5m_n   <= '1';
                        ff_clksel       <= '1';
                        CustomSpeed     <= "0011";
                    when "011" =>                           -- 8.06MHz
                        ff_clksel5m_n   <= '1';
                        ff_clksel       <= '1';
                        CustomSpeed     <= "0010";
                    when others =>                          -- 10.74MHz
                        ff_clksel5m_n   <= '1';
                        ff_clksel       <= '1';
                        CustomSpeed     <= "0000";
                end case;
            end if;
        end if;
    end process;

    -- cpu clock assignment
    iCpuClk <=  '1'         when( power_on_reset = '0' )else
                cpuclk      when( reset = '1' )else                     --  3.58MHz
                clkdiv(0)   when( ff_clksel = '1' )else                 -- 10.74MHz
                clkdiv(1)   when( ff_clksel5m_n = '0' )else             --  5.37MHz
                cpuclk;                                                 --  3.58MHz

    -- one enable pulse per CPU clock (for the floppy controller timings)
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_cpuclk_d <= iCpuClk;
        end if;
    end process;
    cpu_ce <= iCpuClk and not ff_cpuclk_d;

    ----------------------------------------------------------------
    -- Reset control
    ----------------------------------------------------------------

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            -- 00 > 01 > 11 > 10
            ff_mem_seq <= ff_mem_seq(0) & (not ff_mem_seq(1));
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_mem_seq = "00" )then
                FreeCounter <= FreeCounter + 1;
            end if;
        end if;
    end process;

    -- SDRAM initialisation sequence, after the FPGA configuration and the
    -- PLL lock: 4 idle steps of 48us (> 100us), then precharge, refresh,
    -- mode set and memory clear with steps of 3us (total about 0.3ms).
    -- It is short because the IO controller starts the upload of the
    -- system ROMs soon after the FPGA configuration, and the loader can
    -- write to the SDRAM only after this sequence.
    process( memclk )
        variable step : boolean;
    begin
        if( memclk'event and memclk = '1' )then
            ff_locked <= ff_locked(0) & pll_locked;
            if( SIM_FAST )then
                step := FreeCounter( 3 downto 0 ) = "1111";
            elsif( RstSeq(4 downto 2) = "000" )then
                step := FreeCounter( 9 downto 0 ) = "1111111111";
            else
                step := FreeCounter( 5 downto 0 ) = "111111";
            end if;
            if( ff_locked(1) = '0' )then
                RstSeq <= (others => '0');                          -- restart after a PLL unlock
            elsif( ff_mem_seq = "00" and RstSeq /= "11111" and step )then
                RstSeq <= RstSeq + 1;
            end if;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            xSltRst_n <= reset_n;
        end if;
    end process;

    -- reset assignment
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( RstSeq = "11111" )then
                reset <= not xSltRst_n;
            else
                reset <= '1';                                       -- SDRAM is not ready yet
            end if;
        end if;
    end process;

    msx_reset   <= reset;
    cpu_reset_n <= not reset;
    dac_reset   <= not power_on_reset;

    -- power on reset
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_clk21m_cnt( 19 downto 15 ) = "11001" or            -- about 38ms
                (SIM_FAST and ff_clk21m_cnt( 9 downto 5 ) = "11001") )then
                power_on_reset <= '1';
            end if;
        end if;
    end process;

    -- free run counter
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_clk21m_cnt <= ff_clk21m_cnt + 1;
        end if;
    end process;

    -- settings that can change only during reset
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( reset = '1' )then
                Slot0Mode <= cfg_music and rom_music_ok;
                DiskEna   <= cfg_disk  and rom_disk_ok;
                if( MSX1 /= 0 )then
                    RamSub   <= "10";
                    Slot3Exp <= cfg_ram30;
                elsif( cfg_ram30 = '1' )then
                    RamSub   <= "00";
                    Slot3Exp <= '1';
                else
                    RamSub   <= "10";
                    Slot3Exp <= '1';
                end if;
            end if;
            -- the keyboard layout can change at any time
            Kmap      <= not (cfg_kbd(1) and not cfg_kbd(0));       -- '0' = Japanese
            KmapIt    <= cfg_kbd(0) and not cfg_kbd(1);
        end if;
    end process;

    disk_on    <= DiskEna;

    -- MSX1: 64 kB of RAM without memory mapper (the mapper keeps its reset
    -- segments 3, 2, 1, 0 because its I/O ports are not decoded)
    MapSize    <= "110" when( MSX1 /= 0 )else cfg_ram;
    sys_rom_ok <= rom_main_ok when( MSX1 /= 0 )else rom_main_ok and rom_sub_ok;

    ----------------------------------------------------------------
    -- Z80 CPU wait control
    ----------------------------------------------------------------
    process( iCpuClk, reset )

        variable iCpuM1_n   : std_logic;
        variable jSltMerq_n : std_logic;
        variable jSltIorq_n : std_logic;
        variable count      : std_logic_vector(3 downto 0);

    begin

        if( reset = '1' )then
            iCpuM1_n    := '1';
            jSltIorq_n  := '1';
            jSltMerq_n  := '1';
            count       := "0000";
            wait_n_s    <= '1';

        elsif( iCpuClk'event and iCpuClk = '1' )then

            if( CpuMerq_n = '0' and jSltMerq_n = '1' )then
                if( ff_clksel = '1' )then
                    count := CustomSpeed;                               -- 6.96MHz / 8.06MHz (simulated)
                elsif( ff_clksel5m_n = '0' and (iSltCart1 = '1' or iSltCart2 = '1') )then
                    count := "0001";
                end if;
            elsif( CpuIorq_n = '0' and jSltIorq_n = '1' )then           -- wait for I/O devices
                if( ff_clksel = '1' )then
                    count := "0110";
                elsif( ff_clksel5m_n = '0' )then
                    count := "0110";
                end if;
            elsif( count /= "0000" )then                                -- countdown timer
                count := count - 1;
            end if;

            if( CpuM1_n = '0' and iCpuM1_n = '1' )then                  -- one wait state in M1 (MSX standard)
                wait_n_s <= '0';
            elsif( count /= "0000" )then
                wait_n_s <= '0';
            elsif( (ff_clksel = '1' or ff_clksel5m_n = '0') and OpllReq = '1' and OpllAck = '0' )then
                wait_n_s <= '0';
            else
                wait_n_s <= '1';
            end if;

            iCpuM1_n    := CpuM1_n;
            jSltIorq_n  := CpuIorq_n;
            jSltMerq_n  := CpuMerq_n;

        end if;

    end process;

    ----------------------------------------------------------------
    -- CPU data bus: every read is answered by an internal device
    ----------------------------------------------------------------
    BusDir_o    <=  not CpuRd_n;
    CpuD        <=  dbi when( BusDir_o = '1' )else (others => 'Z');
    CpuInt_n    <=  pVdpInt_n;

    ----------------------------------------------------------------
    -- On chip internal bus control
    ----------------------------------------------------------------
    process( clk21m, reset )

        variable ExpDec : std_logic;

    begin

        if( reset = '1' )then

            iSltRfsh_n      <= '1';
            iSltMerq_n      <= '1';
            iSltIorq_n      <= '1';
            xSltRd_n        <= '1';
            xSltWr_n        <= '1';
            iSltAdr         <= (others => '1');
            iSltDat         <= (others => '1');

            iack            <= '0';

            dlydbi          <= (others => '1');
            ExpDec          := '0';

        elsif( clk21m'event and clk21m = '1' )then

            -- CPU bus signals
            iSltRfsh_n      <= CpuRfsh_n;
            iSltMerq_n      <= CpuMerq_n;
            iSltIorq_n      <= CpuIorq_n;
            xSltRd_n        <= CpuRd_n;
            xSltWr_n        <= CpuWr_n;
            iSltAdr         <= CpuA;
            iSltDat         <= CpuD;

            if( iSltMerq_n  = '1' and iSltIorq_n = '1' )then
                iack <= '0';
            elsif( ack = '1' )then
                iack <= '1';
            end if;

            -- input assignments for internal devices
            if( mem = '1' and ExpDec = '1' )then
                dlydbi <= ExpDbi;
            elsif( mem = '1' and iSltFdc = '1' )then                                            -- WD2793 (Philips)
                dlydbi <= fdc_dbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "100110" )then                            -- VDP (V9938/V9958)
                dlydbi <= VdpDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "101000" )then                            -- PSG (AY-3-8910)
                dlydbi <= PsgDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "101010" )then                            -- PPI (8255)
                dlydbi <= PpiDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "111111" and MSX1 = 0 )then               -- Memory-mapper
                dlydbi <= MapDbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "1011010" and MSX1 = 0 )then              -- RTC (RP-5C01)
                dlydbi <= RtcDbi;
            else
                dlydbi <= (others => '1');
            end if;

            if( adr = X"FFFF" )then
                ExpDec := '1';
            else
                ExpDec := '0';
            end if;

        end if;

    end process;

    ----------------------------------------------------------------
    process( clk21m, reset )
    begin

        if( reset = '1' )then

            jSltCart1   <= '0';
            jSltCart2   <= '0';
            jSltMem     <= '0';

            wrt <= '0';

        elsif( clk21m'event and clk21m = '0' )then

            if( mem = '1' and iSltCart1 = '1' )then
                jSltCart1 <= '1';
            else
                jSltCart1 <= '0';
            end if;

            if( mem = '1' and iSltCart2 = '1' )then
                jSltCart2 <= '1';
            else
                jSltCart2 <= '0';
            end if;

            if( mem = '1' and ((iSltMap or rom_main or rom_music or rom_sub or rom_disk) = '1') )then
                jSltMem <= '1';
            else
                jSltMem <= '0';
            end if;

            if( req = '0' )then
                wrt <= not CpuWr_n;                                     -- 1=write, 0=read
            end if;

        end if;

    end process;

    -- access request, CPU > Components
    req     <=  '1'         when( ((iSltMerq_n = '0') or (iSltIorq_n = '0')) and
                                  ((xSltRd_n = '0') or (xSltWr_n = '0')) and iack = '0' )else '0';

    mem     <=  iSltIorq_n;                                             -- 1=memory area, 0=I/O area
    dbo     <=  iSltDat;                                                -- CPU data (CPU > device)
    adr     <=  iSltAdr;                                                -- CPU address (CPU > device)

    -- access acknowledge, Components > CPU
    ack     <=  RamAck      when( RamReq = '1' )else                    -- MapAck, ROMs, cartridge ROM
                Cart1Ack    when( jSltCart1 = '1' )else                 -- SCC
                Cart2Ack    when( jSltCart2 = '1' )else
                OpllAck     when( OpllReq = '1' )else                   -- OpllAck
                req;                                                    -- PsgAck, PpiAck, VdpAck, RtcAck, ...

    dbi     <=  Cart1Dbi    when( jSltCart1 = '1' )else
                Cart2Dbi    when( jSltCart2 = '1' )else
                RamDbi      when( jSltMem   = '1' )else
                dlydbi;

    ----------------------------------------------------------------
    -- PPI(8255) / primary-slot, keyboard, 1bit sound port
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            PpiPortA    <= "00000000";          -- all pages in slot 0 (MAIN-ROM), like a real MSX
            PpiPortC    <= "01010000";          -- CAPS lamp off, cassette motor off
        elsif( clk21m'event and clk21m = '1' )then
            -- I/O port access on A8-ABh ... PPI(8255) access
            if( PpiReq = '1' )then
                if( wrt = '1' and adr(1 downto 0) = "00" )then
                    PpiPortA    <= dbo;
                elsif( wrt = '1' and adr(1 downto 0) = "10" )then
                    PpiPortC  <= dbo;
                elsif( wrt = '1' and adr(1 downto 0) = "11" and dbo(7) = '0' )then
                    case dbo(3 downto 1) is
                        when "000"  => PpiPortC(0) <= dbo(0); -- key_matrix Y(0)
                        when "001"  => PpiPortC(1) <= dbo(0); -- key_matrix Y(1)
                        when "010"  => PpiPortC(2) <= dbo(0); -- key_matrix Y(2)
                        when "011"  => PpiPortC(3) <= dbo(0); -- key_matrix Y(3)
                        when "100"  => PpiPortC(4) <= dbo(0); -- cassete motor on (0=On,1=Off)
                        when "101"  => PpiPortC(5) <= dbo(0); -- cassete audio out
                        when "110"  => PpiPortC(6) <= dbo(0); -- CAPS lamp (0=On,1=Off)
                        when others => PpiPortC(7) <= dbo(0); -- 1bit sound port
                    end case;
                end if;
            end if;
        end if;
    end process;

    Caps    <=  PpiPortC(6);

    -- I/O port access on A8-ABh ... PPI(8255) register read
    PpiDbi  <=  PpiPortA when adr(1 downto 0) = "00" else
                PpiPortB when adr(1 downto 0) = "01" else
                PpiPortC when adr(1 downto 0) = "10" else
                (others => '1');

    ----------------------------------------------------------------
    -- Expansion slot
    ----------------------------------------------------------------

    -- slot #0 (expanded only when MSX-MUSIC is present)
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ExpSlot0 <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( req = '1' and iSltMerq_n = '0' and wrt = '1' and adr = X"FFFF" )then
                if( PpiPortA(7 downto 6) = "00" and Slot0Mode = '1' )then
                    ExpSlot0 <= dbo;
                end if;
            end if;
        end if;
    end process;

    -- slot #3
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ExpSlot3 <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( req = '1' and iSltMerq_n = '0' and wrt = '1' and adr = X"FFFF" )then
                if( PpiPortA(7 downto 6) = "11" and Slot3Exp = '1' )then
                    ExpSlot3 <= dbo;
                end if;
            end if;
        end if;
    end process;

    -- primary slot number
    with adr(15 downto 14) select PriSltNum <=
        PpiPortA(1 downto 0) when "00",
        PpiPortA(3 downto 2) when "01",
        PpiPortA(5 downto 4) when "10",
        PpiPortA(7 downto 6) when others;

    -- expansion slot number : slot 0
    with adr(15 downto 14) select ExpSltNum0 <=
        ExpSlot0(1 downto 0) when "00",
        ExpSlot0(3 downto 2) when "01",
        ExpSlot0(5 downto 4) when "10",
        ExpSlot0(7 downto 6) when others;

    -- expansion slot number : slot 3
    with adr(15 downto 14) select ExpSltNum3 <=
        ExpSlot3(1 downto 0) when "00",
        ExpSlot3(3 downto 2) when "01",
        ExpSlot3(5 downto 4) when "10",
        ExpSlot3(7 downto 6) when others;

    -- expansion slot register read (FFFFh of an expanded slot)
    ExpDbi  <=  not ExpSlot0    when( PpiPortA(7 downto 6) = "00" and Slot0Mode = '1' )else
                not ExpSlot3    when( PpiPortA(7 downto 6) = "11" and Slot3Exp = '1' )else
                (others => '1');

    ----------------------------------------------------------------
    --  Slot/Page Decode
    ----------------------------------------------------------------
    with( adr(15 downto 14) ) select w_page_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( PriSltNum ) select w_prislt_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( ExpSltNum0 ) select w_expslt0_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( ExpSltNum3 ) select w_expslt3_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    ----------------------------------------------------------------
    --  Address Decode for CPU
    ----------------------------------------------------------------
    -- Slot 0(-0) : MAIN-ROM 0000-7FFFh
    rom_main    <=  mem when( (w_prislt_dec(0) and (w_expslt0_dec(0) or (not Slot0Mode)) and (w_page_dec(0) or w_page_dec(1))) = '1' and rom_main_ok = '1' )else
                    '0';
    -- Slot 0-2 : MSX-MUSIC 4000-7FFFh
    rom_music   <=  mem when( (w_prislt_dec(0) and w_expslt0_dec(2) and Slot0Mode and w_page_dec(1)) = '1' )else
                    '0';
    -- Slot 1, 2 : cartridges (the expansion register FFFFh is not decoded)
    iSltCart1   <=  mem when( w_prislt_dec(1) = '1' )else '0';
    iSltCart2   <=  mem when( w_prislt_dec(2) = '1' and not (MSX1 /= 0 and DiskEna = '1' and cart2_present = '0') )else '0';
    -- Slot 3-2 (or 3-0) : memory mapper
    iSltMap     <=  mem when( w_prislt_dec(3) = '1' and Slot3Exp = '0' )else
                    mem when( w_prislt_dec(3) = '1' and ExpSltNum3 = RamSub and adr /= X"FFFF" )else
                    '0';
    -- Slot 3-1 : SUB-ROM 0000-3FFFh
    rom_sub     <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(1) and w_page_dec(0)) = '1' and rom_sub_ok = '1' and MSX1 = 0 )else
                    '0';
    -- Slot 3-3 (MSX1: slot 2 without cartridge) : DISK-ROM 4000-7FF7h, WD2793 7FF8-7FFFh (mirror BFF8-BFFFh)
    DiskSlt     <=  (w_prislt_dec(2) and not cart2_present) when( MSX1 /= 0 )else
                    (w_prislt_dec(3) and w_expslt3_dec(3));
    iSltFdc     <=  mem when( (DiskSlt and (w_page_dec(1) or w_page_dec(2))) = '1' and
                              adr(13 downto 3) = "11111111111" and DiskEna = '1' )else
                    '0';
    rom_disk    <=  mem when( (DiskSlt and w_page_dec(1)) = '1' and
                              adr(13 downto 3) /= "11111111111" and DiskEna = '1' )else
                    '0';

    -- SDRAM access request
    RamReq  <=  Cart1Ram or Cart2Ram or MapRam or RomReq;

    -- access request to component
    VdpReq      <=  req when( mem = '0' and adr(7 downto 2) = "100110"                      )else '0';  -- I/O:98-9Bh / VDP (V9938/V9958)
    PsgReq      <=  req when( mem = '0' and adr(7 downto 2) = "101000"                      )else '0';  -- I/O:A0-A3h / PSG (AY-3-8910)
    PpiReq      <=  req when( mem = '0' and adr(7 downto 2) = "101010"                      )else '0';  -- I/O:A8-ABh / PPI (8255)
    OpllReq     <=  req when( mem = '0' and adr(7 downto 1) = "0111110" and Slot0Mode = '1' )else '0';  -- I/O:7C-7Dh / OPLL (YM2413)
    RomReq      <=  req when( (rom_main or rom_music or rom_sub or rom_disk) = '1'          )else '0';
    MapReq      <=  req when( mem = '0' and adr(7 downto 2) = "111111" and MSX1 = 0         )else       -- I/O:FC-FFh / Memory-mapper
                    req when( iSltMap = '1'                                                 )else '0';  -- MEM:       / Memory-mapper
    Cart1Req    <=  req when( iSltCart1 = '1'                                               )else '0';
    Cart2Req    <=  req when( iSltCart2 = '1'                                               )else '0';
    RtcReq      <=  req when( mem = '0' and adr(7 downto 1) = "1011010" and MSX1 = 0        )else '0';  -- I/O:B4-B5h / RTC (RP-5C01)

    -- floppy disk controller bus (strobes are the CPU ones, held for the whole access)
    fdc_cs      <=  iSltFdc;
    fdc_rd      <=  iSltFdc and not xSltRd_n;
    fdc_wr      <=  iSltFdc and not xSltWr_n;
    fdc_adr     <=  adr(2 downto 0);
    fdc_dbo     <=  dbo;

    ----------------------------------------------------------------
    -- Cartridges
    ----------------------------------------------------------------
    Cart1Map    <=  "000"           when( cart1_present = '0' )else
                    cart1_det       when( cfg_mapper1 = "000" )else
                    cfg_mapper1;
    Cart2Map    <=  "000"           when( cart2_present = '0' )else
                    cart2_det       when( cfg_mapper2 = "000" )else
                    cfg_mapper2;

    ----------------------------------------------------------------
    -- Video output
    ----------------------------------------------------------------
    VDP_ID          <=  "00010" when( cfg_v9958 = '1' and MSX1 = 0 )else "00000";    -- V9958 / V9938
    ntsc_pal_type   <=  '1' when( cfg_vmode = "00" )else '0';           -- '1' = follow VDP R#9
    forced_v_mode   <=  cfg_vmode(1);                                   -- '1' = 50Hz
    Reso_v          <=  cfg_vga;
    legacy_vga      <=  not cfg_lcd;

    process (clk21m)
    begin
        if( clk21m'event and clk21m = '1' )then
            pVideoBlank <= VideoBlank;
            pVideoR     <= VideoR;
            pVideoG     <= VideoG;
            pVideoB     <= VideoB;
            pVideoHS_n  <= VideoHS_n;
            pVideoVS_n  <= VideoVS_n;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Sound output
    ----------------------------------------------------------------
    PsgVol  <= cfg_psg_vol;
    SccVol  <= cfg_scc_vol;
    OpllVol <= cfg_fm_vol;

    -- cassette sound (like the speaker of a real data recorder)
    TapeClick <= CmtIn and cfg_tape_snd and not PpiPortC(4);

    -- mixer (pipe lined)
    u_mul: scc_mix_mul
    port map (
        a   => ff_prescc        ,           -- 16bits signed
        b   => m_SccVol         ,           --  3bits unsigned
        c   => w_scc                        -- 19bits signed
    );

    process( clk21m )
        constant h_ramp : integer := -1;
        constant m_ramp : integer :=  2;
        constant l_ramp : integer :=  6;
        constant h_thrd : integer := 12;
        constant m_thrd : integer :=  9;
        constant x_thrd : integer :=  1;
        variable c_Psg  : std_logic_vector(  3 downto  0 );
        variable c_Scc  : std_logic_vector(  3 downto  0 );
        variable c_Opll : std_logic_vector(  3 downto  0 );
        variable chPsg  : std_logic_vector( ff_prepsg'range );
        variable chOpll : std_logic_vector( ff_pre_dacin'range );
    begin
        if( clk21m'event and clk21m = '1' )then

            -- amplitude ramp of the PSG (full range)
            ff_prepsg <= ("0" & PsgAmp) + (KeyClick & "00000") + (TapeClick & "0000");
            c_Psg       := ("1" & PsgVol) - ("0" & MstrVol);
            if( PsgVol = "000" or MstrVol = "111" )then
                ff_psg      <= ( others => '0' );
            elsif( c_Psg > h_thrd )then
                chPsg       := ff_prepsg;
                ff_psg      <= "0" & ("0" & (chPsg * (PsgVol - MstrVol + h_ramp + x_thrd)) + chPsg( chPsg'high - 4 downto  0 )) & "00";
            elsif( c_Psg > (m_thrd - x_thrd) )then
                chPsg       := "0" & ff_prepsg( ff_prepsg'high downto 1 );
                ff_psg      <= "0" & ("0" & (chPsg * (PsgVol - MstrVol + m_ramp + x_thrd)) + chPsg( chPsg'high - 4 downto  0 )) & "00";
            else
                chPsg       := "00" & ff_prepsg( ff_prepsg'high downto 2 );
                ff_psg      <= "0" & ("0" & (chPsg * (PsgVol - MstrVol + l_ramp + x_thrd)) + chPsg( chPsg'high - 4 downto  0 )) & "00";
            end if;

            -- amplitude ramp of the SCC-I (full range)
            ff_prescc   <= (Cart1Wav(14) & Cart1Wav) + (Cart2Wav(14) & Cart2Wav);
            c_Scc       := ("1" & SccVol) - ("0" & MstrVol);
            if( SccVol = "000" or MstrVol = "111" )then
                m_SccVol    <= "000";
                ff_scc      <= ( others => w_scc(18) );
            elsif( c_Scc > h_thrd )then
                m_SccVol    <= SccVol - MstrVol + h_ramp;
                ff_scc      <= w_scc(18) & w_scc( 18 downto  4 );
            elsif( c_Scc > m_thrd )then
                m_SccVol    <= SccVol - MstrVol + m_ramp;
                ff_scc      <= w_scc(18) & w_scc(18) & w_scc( 18 downto  5 );
            else
                m_SccVol    <= SccVol - MstrVol + l_ramp;
                ff_scc      <= w_scc(18) & w_scc(18) & w_scc(18) & w_scc( 18 downto  6 );
            end if;

            -- amplitude ramp of the OPLL (full range)
            c_Opll      := ("1" & OpllVol) - ("0" & MstrVol);
            if( OpllVol = "000" or MstrVol = "111" or Slot0Mode = '0' )then
                ff_opll <= c_opll_offset;
            elsif( OpllAmp < c_opll_zero )then
                if( c_Opll > h_thrd )then
                    chOpll   := ((c_opll_zero - OpllAmp) * (OpllVol - MstrVol + h_ramp)) & "000";
                elsif( c_Opll > m_thrd )then
                    chOpll   := "0" & ((c_opll_zero - OpllAmp) * (OpllVol - MstrVol + m_ramp)) & "00";
                else
                    chOpll   := "00" & ((c_opll_zero - OpllAmp) * (OpllVol - MstrVol + l_ramp)) & "0";
                end if;
                ff_opll <= c_opll_offset - (chOpll - chOpll( chOpll'high downto  3 ));
            else
                if( c_Opll > h_thrd )then
                    chOpll   := ((OpllAmp - c_opll_zero) * (OpllVol - MstrVol + h_ramp)) & "000";
                elsif( c_Opll > m_thrd )then
                    chOpll   := "0" & ((OpllAmp - c_opll_zero) * (OpllVol - MstrVol + m_ramp)) & "00";
                else
                    chOpll   := "00" & ((OpllAmp - c_opll_zero) * (OpllVol - MstrVol + l_ramp)) & "0";
                end if;
                ff_opll <= c_opll_offset + (chOpll - chOpll( chOpll'high downto  3 ));
            end if;
        end if;
    end process;

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then

            -- ff_pre_dacin assignment
            ff_pre_dacin <= (not ff_psg) + ff_scc + ff_opll;

            -- amplitude limiter
            case ff_pre_dacin( ff_pre_dacin'high downto ff_pre_dacin'high - 2 ) is
                when "100" => DACin <= ff_pre_dacin( ff_pre_dacin'high ) & ff_pre_dacin( ff_pre_dacin'high - 3 downto 0 );
                when "011" => DACin <= ff_pre_dacin( ff_pre_dacin'high ) & ff_pre_dacin( ff_pre_dacin'high - 3 downto 0 );
                when others => DACin <= (others => ff_pre_dacin( ff_pre_dacin'high ));
            end case;

        end if;
    end process;

    pDacOut <=  DACout;

    -- Cassette Magnetic Tape (CMT) interface
    CmtOut   <= PpiPortC(5);
    CmtMotor <= not PpiPortC(4);

    -----------------------------------------------------------------
    -- External memory access
    -----------------------------------------------------------------
    -- Memo: SdrAdr(12 downto 11) <= CpuAdr(24 downto 23);
    --       SdrBa ( 1 downto  0) <= CpuAdr(22 downto 21);
    --       row = CpuAdr(24 downto 23) & CpuAdr(11 downto 1), column = CpuAdr(20 downto 12)
    -----------------------------------------------------------------
    CpuAdr  <=  "000"              & MapAdr                     when( iSltMap   = '1' )else     -- 0x0000000 mapper RAM (4 MB)
                "10"               & Cart1Adr                   when( iSltCart1 = '1' )else     -- 0x1000000 cartridge 1
                "11"               & Cart2Adr                   when( iSltCart2 = '1' )else     -- 0x1800000 cartridge 2
                "0011000" & "00"   & "0"  & adr(14 downto 0)    when( rom_main  = '1' )else     -- 0x0600000 MAIN-ROM
                "0011000" & "00"   & "10" & adr(13 downto 0)    when( rom_sub   = '1' )else     -- 0x0608000 SUB-ROM
                "0011000" & "00"   & "11" & adr(13 downto 0)    when( rom_disk  = '1' )else     -- 0x060C000 DISK-ROM
                "0011000" & "01"   & "00" & adr(13 downto 0)    when( rom_music = '1' )else     -- 0x0610000 MSX-MUSIC
                "0011000" & "11"   & X"FFFF";                                                   -- 0x063FFFF (unused)

    -- the loader takes the CPU slots of the SDRAM controller
    ld_adr      <=  ld_q( 32 downto 8 );
    ld_dat      <=  ld_q(  7 downto 0 );
    ld_take     <=  '1' when( ld_avail = '1' and VideoDLClk = '0' and RstSeq = "11111" )else '0';
    SdrRowAdr   <=  ld_adr when( ld_take = '1' )else CpuAdr;     -- used when the row is latched ("000")
    SdrColAdr   <=  ld_adr when( ld_go   = '1' )else CpuAdr;     -- used afterwards

    ----------------------------------------------------------------
    -- Loader FIFO
    ----------------------------------------------------------------
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( ld_wr_req = '1' )then
                ld_fifo( conv_integer(ld_wp) ) <= ld_wr_adr & ld_wr_dat;
                ld_wp <= ld_wp + 1;
            end if;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            ld_q <= ld_fifo( conv_integer(ld_rp) );
            -- two cycles of delay so that ld_q is valid before the data is used
            if( ld_wp /= ld_rp )then
                ld_avail_d1 <= '1';
            else
                ld_avail_d1 <= '0';
            end if;
            if( ld_wp /= ld_rp )then
                ld_avail <= ld_avail_d1;
            else
                ld_avail <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- SDRAM access
    ----------------------------------------------------------------
    --   SdrSta = "000" => idle
    --   SdrSta = "001" => precharge all
    --   SdrSta = "010" => refresh
    --   SdrSta = "011" => mode register set
    --   SdrSta = "100" => read cpu
    --   SdrSta = "101" => write cpu / loader
    --   SdrSta = "110" => read vdp
    --   SdrSta = "111" => write vdp
    ----------------------------------------------------------------
    w_wrt_req   <=  (RamReq and MapWrt and iSltMap);

    -- During the MSX reset the VDP stops its DHClk/DLClk: the SDRAM
    -- sequencer then runs freely, every slot is a CPU slot (used by the
    -- loader) and the refresh is generated here.
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( reset = '0' )then
                ff_rfsh_cnt   <= (others => '0');
                ff_force_rfsh <= '0';
            else
                ff_rfsh_cnt <= ff_rfsh_cnt + 1;
                if( ff_rfsh_cnt = "111111111" )then
                    ff_force_rfsh <= '1';                           -- every 6us
                elsif( ff_sdr_seq = "111" and RstSeq = "11111" )then
                    ff_force_rfsh <= '0';
                end if;
            end if;
        end if;
    end process;

    w_rfsh  <= '1' when( (iSltRfsh_n = '0' and VideoDLClk = '1') or ff_force_rfsh = '1' )else '0';

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "111" )then
                if( RstSeq(4 downto 2) = "000" )then
                    SdrSta <= "000";                                                -- idle
                elsif( RstSeq(4 downto 2) = "001" )then
                    SdrSta <= "0" & RstSeq(1 downto 0);                             -- idle, precharge, refresh, mode set
                elsif( RstSeq(4 downto 3) /= "11" )then
                    SdrSta <= "101";                                                -- write (memory clear)
                elsif( w_rfsh = '1' )then
                    SdrSta <= "010";                                                -- refresh
                else
                    SdrSta(2) <= '1';                                               -- read/write cpu/vdp
                end if;
            elsif( ff_sdr_seq = "001" and SdrSta(2) = '1' and RstSeq(4 downto 3) = "11" )then
                SdrSta(1) <= VideoDLClk;                                            -- 0:cpu, 1:vdp
                if( VideoDLClk = '0' )then
                    SdrSta(0) <= w_wrt_req or ld_go;    -- for cpu / loader
                else
                    SdrSta(0) <= not WeVdp_n;           -- for vdp
                end if;
            end if;
        end if;
    end process;

    -- loader slot: decided when the row address is latched, released after the write
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "000" )then
                if( SdrSta(2) = '1' )then
                    ld_go <= ld_take;
                else
                    ld_go <= '0';
                end if;
            elsif( ff_sdr_seq = "011" )then
                if( ld_go = '1' )then
                    ld_rp <= ld_rp + 1;
                end if;
            elsif( ff_sdr_seq = "111" )then
                ld_go <= '0';
            end if;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( SdrSta(2) = '1' )then               -- cpu/vdp read/write
                        SdrCmd <= SdrCmd_ac;
                    elsif( SdrSta(1 downto 0) = "00" )then  -- idle
                        SdrCmd <= SdrCmd_xx;
                    elsif( SdrSta(1 downto 0) = "01" )then  -- precharge all
                        SdrCmd <= SdrCmd_pr;
                    elsif( SdrSta(1 downto 0) = "10" )then  -- refresh
                        SdrCmd <= SdrCmd_re;
                    else                                    -- mode register set
                        SdrCmd <= SdrCmd_ms;
                    end if;
                when "001" =>
                    SdrCmd <= SdrCmd_xx;
                when "010" =>
                    if( SdrSta(2) = '1' )then
                        if( SdrSta(0) = '0' )then
                            SdrCmd <= SdrCmd_rd;            -- "100"(cpu read) / "110"(vdp read)
                        else
                            SdrCmd <= SdrCmd_wr;            -- "101"(cpu write) / "111"(vdp write)
                        end if;
                    end if;
                when "011" =>
                    SdrCmd <= SdrCmd_xx;
                when others =>
                    null;
            end case;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    SdrUdq <= '1';
                    SdrLdq <= '1';
                when "010" =>
                    if( SdrSta(2) = '1' )then
                        if( SdrSta(0) = '0' )then
                            SdrUdq <= '0';
                            SdrLdq <= '0';
                        else
                            if( RstSeq(4 downto 3) /= "11" )then
                                SdrUdq <= '0';
                                SdrLdq <= '0';
                            elsif( VideoDLClk = '0' )then
                                SdrUdq <= not SdrColAdr(0);
                                SdrLdq <= SdrColAdr(0);
                            else
                                SdrUdq <= not VdpAdr(16);
                                SdrLdq <= VdpAdr(16);
                            end if;
                        end if;
                    end if;
                when "011" =>
                    SdrUdq <= '1';
                    SdrLdq <= '1';
                when others =>
                    null;
            end case;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- SDRAM address
    -----------------------------------------------------------------------
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( SdrSta(2) = '0' )then                                       -- set [command mode]
                        --           WBL=single TM=off CL=2 WT=0(seq) BL=1
                        SdrAdr <= "00" & "010" & "0" & "010" & "0" & "000";
                        SdrBa  <= "00";                                             -- bank A
                    else                                                            -- set [row address]
                        if( VideoDLClk = '0' )then
                            SdrAdr <= SdrRowAdr(24 downto 23) & SdrRowAdr(11 downto 1); -- cpu/loader read/write
                            SdrBa  <= SdrRowAdr(22 downto 21);                       -- bank A+B+C+D
                        else
                            SdrAdr <= "00" & VdpAdr(10 downto 0);                   -- vdp read/write
                            SdrBa  <= "11";                                         -- bank D
                        end if;
                    end if;
                when "010" =>                                                       -- set [column address]
                    SdrAdr(10 downto 9) <= "10";                                    -- A10=1 => enable auto precharge
                    if( VideoDLClk = '0' )then
                        SdrAdr(12 downto 11) <= SdrColAdr(24 downto 23);
                        SdrAdr(8 downto 0) <= SdrColAdr(20 downto 12);              -- cpu/loader read/write
                    elsif( VdpAdr(15) = '0' )then
                        SdrAdr(12 downto 11) <= "00";
                        SdrAdr(8 downto 0) <= "1" & vram_page(3 downto 0) & VdpAdr(14 downto 11);  -- vdp read/write (even)
                    else
                        SdrAdr(12 downto 11) <= "00";
                        SdrAdr(8 downto 0) <= "1" & vram_page(7 downto 4) & VdpAdr(14 downto 11);  -- vdp read/write (odd)
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "010" )then
                if( SdrSta(2) = '1' )then
                    if( SdrSta(0) = '0' )then
                        SdrDat <= (others => 'Z');
                    else
                        if( RstSeq(4 downto 3) /= "11" )then
                            SdrDat <= (others => '0');
                        elsif( VideoDLClk = '0' )then
                            if( ld_go = '1' )then
                                SdrDat <= ld_dat & ld_dat;          -- loader write
                            else
                                SdrDat <= dbo & dbo;                -- "101"(cpu write)
                            end if;
                        else
                            SdrDat <= VrmDbo & VrmDbo;              -- "111"(vdp write)
                        end if;
                    end if;
                end if;
            else
                SdrDat <= (others => 'Z');
            end if;
        end if;
    end process;

    -- Data read latch for CPU
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "101" )then
                if( SdrSta = "100" )then        -- read cpu
                    if( CpuAdr(0) = '0' )then
                        RamDbi  <= pMemDat(  7 downto 0 );
                    else
                        RamDbi  <= pMemDat( 15 downto 8 );
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Data read latch for VDP
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "101" )then
                if( SdrSta = "110" )then        -- read vdp
                    VrmDbi  <= pMemDat( 15 downto 0 );
                end if;
            end if;
        end if;
    end process;

    -- SDRAM controller state
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( VideoDHClk = '1' or RstSeq(4 downto 3) /= "11" or reset = '1' )then
                        ff_sdr_seq <= "001";
                    end if;
                when "111" =>
                    if( VideoDHClk = '0' or RstSeq(4 downto 3) /= "11" or reset = '1' )then
                        ff_sdr_seq <= "000";
                    end if;
                when others =>
                    ff_sdr_seq <= ff_sdr_seq + 1;
            end case;
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            RamAck <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( RamReq = '0' )then
                RamAck <= '0';
            elsif( VideoDLClk = '0' and VideoDHClk = '1' )then
                RamAck <= '1';
            end if;
        end if;
    end process;

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( VideoDLClk = '0' )then
                vram_page <= vram_slot_ids;
            end if;
        end if;
    end process;

    pMemCke     <= '1';
    pMemCs_n    <= SdrCmd(3);
    pMemRas_n   <= SdrCmd(2);
    pMemCas_n   <= SdrCmd(1);
    pMemWe_n    <= SdrCmd(0);

    pMemUdq     <= SdrUdq;
    pMemLdq     <= SdrLdq;
    pMemBa1     <= SdrBa(1);
    pMemBa0     <= SdrBa(0);

    pMemAdr     <= SdrAdr;
    pMemDat     <= SdrDat;

    ----------------------------------------------------------------
    -- Connect components
    ----------------------------------------------------------------
    U01 : t80a
        port map(
            RESET_n     => cpu_reset_n,
            R800_mode   => '0',
            CLK_n       => iCpuClk,
            WAIT_n      => wait_n_s,
            INT_n       => CpuInt_n,
            NMI_n       => '1',
            BUSRQ_n     => '1',
            M1_n        => CpuM1_n,
            MREQ_n      => CpuMerq_n,
            IORQ_n      => CpuIorq_n,
            RD_n        => CpuRd_n,
            WR_n        => CpuWr_n,
            RFSH_n      => CpuRfsh_n,
            HALT_n      => open,
            BUSAK_n     => open,
            A           => CpuA,
            D           => CpuD
        );

    U05 : mapper
        port map(clk21m, reset, clkena, MapReq, open, mem, wrt, adr, MapDbi, dbo, MapSize,
                        MapRam, MapWrt, MapAdr, RamDbi, open);

    U06 : eseps2
        port map(clk21m, reset, clkena, Kmap, KmapIt, Caps, Kana, Paus, Scro, Reso, Fkeys,
                        pPs2Clk, pPs2Dat, PpiPortC, PpiPortB, CmtScro);

    U07 : rtc_mist
        port map(clk21m, reset, iRTC, RtcReq, open, wrt, adr, RtcDbi, dbo);

    U20 : vdp
        port map(clk21m, reset, VdpReq, open, wrt, adr, VdpDbi, dbo, pVdpInt_n,
                        open, WeVdp_n, VdpAdr, VrmDbi, VrmDbo, '0', "000", '1',
                        VideoR, VideoG, VideoB, VideoHS_n, VideoVS_n, VideoCS_n,
                        VideoDHClk, VideoDLClk, VideoBlank, Reso_v, ntsc_pal_type, forced_v_mode, legacy_vga, VDP_ID, OFFSET_Y);

    U30 : psg
        port map(clk21m, reset, clkena, PsgReq, open, wrt, adr, PsgDbi, dbo,
                        pJoyA, pStrA, pJoyB, pStrB, Kana, CmtIn, '1', PsgAmp);

    U31_1 : cart_slot
        port map(clk21m, reset, clkena, Cart1Req, Cart1Ack, wrt, adr, Cart1Dbi, dbo,
                        Cart1Ram, Cart1Adr, RamDbi, Cart1Map, cart1_mask, cart1_last, cart1_base, Cart1Wav);

    U31_2 : cart_slot
        port map(clk21m, reset, clkena, Cart2Req, Cart2Ack, wrt, adr, Cart2Dbi, dbo,
                        Cart2Ram, Cart2Adr, RamDbi, Cart2Map, cart2_mask, cart2_last, cart2_base, Cart2Wav);

    U32 : eseopll
        port map(clk21m, reset, clkena, OpllEnaWait, OpllReq, OpllAck, wrt, adr, dbo, OpllAmp);

    -- OPLL wait enabler
    OpllEnaWait <= ff_clksel xnor ff_clksel5m_n;

    U40 : rom_loader
        generic map( MSX1 => MSX1 )
        port map(
            clk21m          => clk21m,
            dl_download     => dl_download,
            dl_index        => dl_index,
            dl_wr           => dl_wr,
            dl_addr         => dl_addr,
            dl_data         => dl_data,
            wr_req          => ld_wr_req,
            wr_adr          => ld_wr_adr,
            wr_dat          => ld_wr_dat,
            rom_main_ok     => rom_main_ok,
            rom_sub_ok      => rom_sub_ok,
            rom_disk_ok     => rom_disk_ok,
            rom_music_ok    => rom_music_ok,
            eject1          => eject1,
            eject2          => eject2,
            cart1_present   => cart1_present,
            cart1_mapper    => cart1_det,
            cart1_mask      => cart1_mask,
            cart1_last      => cart1_last,
            cart1_base      => cart1_base,
            cart2_present   => cart2_present,
            cart2_mapper    => cart2_det,
            cart2_mask      => cart2_mask,
            cart2_last      => cart2_last,
            cart2_base      => cart2_base
        );

    u_interpo : interpo
        generic map(
            msbi    => DACin'high
        )
        port map(
            clk21m  => clk21m               ,
            reset   => dac_reset            ,
            clkena  => clkena               ,
            idata   => DACin                ,
            odata   => lpf1_wave
        );

    u_lpf2 : lpf2
        generic map(
            msbi    => DACin'high
        )
        port map(
            clk21m  => clk21m               ,
            reset   => dac_reset            ,
            clkena  => clkena               ,
            idata   => lpf1_wave            ,
            odata   => lpf5_wave
        );

    audio_o <= lpf5_wave;

    U33: esepwm
        generic map(DAC_msbi) port map(clk21m, dac_reset, lpf5_wave, DACout);

end RTL;
