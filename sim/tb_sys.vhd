--
-- tb_sys.vhd - system test of msx2_core
--   * uploads MAIN+SUB+DISK (index 0) and two cartridges (index 7 and 8)
--     the way the MiST IO controller does (data_io byte stream)
--   * runs systest.asm from the MAIN-ROM slot
--   * reports the results that the test program writes to C000h-C0FFh by
--     decoding the SDRAM write commands (mapper segment 0 = SDRAM 0x0000000)
--   * a register-file stub stands in for the WD2793 (7FF8h-7FFFh)
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use std.textio.all;

entity tb_sys is
    generic(
        SYS_HEX     : string  := "systest/sys.hex";
        CART1_HEX   : string  := "systest/cart1.hex";
        CART2_HEX   : string  := "systest/cart2.hex";   -- "none" = empty slot
        BYTE_GAP    : natural := 3;
        TIMEOUT_MS  : natural := 20;
        SPEED_SEL   : natural := 0;
        DEBUG_N     : natural := 0;             -- print the first N SDRAM accesses after the reset
        PRELOAD     : boolean := false;         -- preload the SDRAM model, upload only a few bytes
        MAP1        : natural := 0;             -- forced mapper of slot 1 (0 = auto)
        MAP2        : natural := 0;
        VERIFY      : boolean := false;         -- compare the SDRAM with the uploaded files
        FAST_INIT   : boolean := true;          -- short SDRAM init / power-on timers
        INIT_WAIT_US: natural := 50;            -- time from the start to the first upload
        MSX1_G      : integer := 0;             -- 1: MSX1 core
        SYS_PRE_HEX : string  := ""             -- preload image of the system ROMs (default SYS_HEX)
    );
end tb_sys;

architecture sim of tb_sys is

    constant T_MEM  : time := 11.638 ns;        -- 85.92 MHz

    signal memclk   : std_logic := '0';
    signal clk21m   : std_logic := '0';
    signal reset_n  : std_logic := '0';

    signal cke, cs_n, ras_n, cas_n, we_n, udq, ldq, ba1, ba0 : std_logic;
    signal sdr_a    : std_logic_vector(12 downto 0);
    signal sdr_dq   : std_logic_vector(15 downto 0);
    signal rfsh_cnt : natural;
    signal sdr_ba   : std_logic_vector(1 downto 0);
    signal sdr_dqm  : std_logic_vector(1 downto 0);

    signal ps2c, ps2d : std_logic;
    signal joya, joyb : std_logic_vector(5 downto 0);

    signal dl_download : std_logic := '0';
    signal dl_index    : std_logic_vector(7 downto 0) := (others => '0');
    signal dl_wr       : std_logic := '0';
    signal dl_addr     : std_logic_vector(26 downto 0) := (others => '0');
    signal dl_data     : std_logic_vector(7 downto 0) := (others => '0');

    signal vr, vg, vb  : std_logic_vector(5 downto 0);
    signal hs, vs, blank : std_logic;
    signal audio       : std_logic_vector(13 downto 0);
    signal fdc_cs, fdc_rd, fdc_wr, cpu_ce, msx_reset, disk_on, sys_ok : std_logic;
    signal fdc_adr     : std_logic_vector(2 downto 0);
    signal fdc_dbo     : std_logic_vector(7 downto 0);
    signal fdc_dbi     : std_logic_vector(7 downto 0);
    signal cmt_out, cmt_motor, dac : std_logic;

    type fdc_regs_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal fdc_regs    : fdc_regs_t := (others => X"FF");

    signal done        : boolean := false;
    signal check       : std_logic := '0';
    signal test_done   : boolean := false;
    signal speed_v     : std_logic_vector(2 downto 0);

    procedure upload( constant fname : in string; constant idx : in natural; constant sparse : in boolean;
                      signal dl_download : out std_logic; signal dl_index : out std_logic_vector;
                      signal dl_wr : out std_logic; signal dl_addr : out std_logic_vector;
                      signal dl_data : out std_logic_vector; signal clk : in std_logic ) is
        file     f      : text open read_mode is fname;
        variable l      : line;
        variable addr   : natural := 0;
        variable good   : boolean;
        variable c      : character;
        variable n      : integer;
        variable pend   : boolean := false;
        variable pdata  : integer;
    begin
        wait until rising_edge(clk);
        dl_index    <= std_logic_vector(to_unsigned(idx, 8));
        dl_download <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk); end loop;
        while not endfile(f) loop
            readline(f, l);
            n := 0;
            for k in 1 to 2 loop
                read(l, c, good);
                if( c >= '0' and c <= '9' )then n := n*16 + character'pos(c) - character'pos('0');
                else n := n*16 + character'pos(c) - character'pos('A') + 10; end if;
            end loop;
            if( (not sparse) or addr = 0 or addr = 16#8000# or addr = 16#C000# or addr = 16#10000# or endfile(f) )then
                dl_addr <= std_logic_vector(to_unsigned(addr, 27));
                dl_data <= std_logic_vector(to_unsigned(n, 8));
                dl_wr   <= '1';
                wait until rising_edge(clk);
                dl_wr   <= '0';
                for i in 2 to BYTE_GAP loop wait until rising_edge(clk); end loop;
            end if;
            addr := addr + 1;
        end loop;
        for i in 1 to 20 loop wait until rising_edge(clk); end loop;
        dl_download <= '0';
        report "uploaded " & fname & " (" & integer'image(addr) & " bytes) to index " & integer'image(idx);
    end procedure;

    function sel( c : boolean; f : string ) return string is
    begin
        if( c and f /= "none" )then return f; else return ""; end if;
    end function;

    function sel2( c : boolean; f1, f2 : string ) return string is
    begin
        if( not c )then return ""; elsif( f1'length > 0 )then return f1; else return f2; end if;
    end function;

    function hex2( v : std_logic_vector(7 downto 0) ) return string is
        constant h : string(1 to 16) := "0123456789ABCDEF";
        variable r : string(1 to 2);
    begin
        if( is_x(v) )then return "XX"; end if;
        r(1) := h(to_integer(unsigned(v(7 downto 4))) + 1);
        r(2) := h(to_integer(unsigned(v(3 downto 0))) + 1);
        return r;
    end function;

begin

    speed_v <= std_logic_vector(to_unsigned(SPEED_SEL, 3));

    memclk <= not memclk after T_MEM/2 when not done;
    process( memclk )
        variable cnt : natural range 0 to 3 := 0;
    begin
        if( rising_edge(memclk) )then
            if( cnt = 1 )then clk21m <= '1'; elsif( cnt = 3 )then clk21m <= '0'; end if;
            if( cnt = 3 )then cnt := 0; else cnt := cnt + 1; end if;
        end if;
    end process;

    ps2c <= 'H'; ps2d <= 'H';
    joya <= (others => 'H'); joyb <= (others => 'H');

    dut : entity work.msx2_core
        generic map( SIM_FAST => FAST_INIT, MSX1 => MSX1_G )
        port map(
            clk21m => clk21m, memclk => memclk, reset_n => reset_n,
            pMemCke => cke, pMemCs_n => cs_n, pMemRas_n => ras_n, pMemCas_n => cas_n, pMemWe_n => we_n,
            pMemUdq => udq, pMemLdq => ldq, pMemBa1 => ba1, pMemBa0 => ba0, pMemAdr => sdr_a, pMemDat => sdr_dq,
            pPs2Clk => ps2c, pPs2Dat => ps2d,
            pJoyA => joya, pStrA => open, pJoyB => joyb, pStrB => open,
            pVideoR => vr, pVideoG => vg, pVideoB => vb, pVideoHS_n => hs, pVideoVS_n => vs, pVideoBlank => blank,
            audio_o => audio, pDacOut => dac,
            CmtIn => '1', CmtOut => cmt_out, CmtMotor => cmt_motor,
            iRTC => (others => '0'),
            fdc_cs => fdc_cs, fdc_rd => fdc_rd, fdc_wr => fdc_wr, fdc_adr => fdc_adr, fdc_dbo => fdc_dbo,
            fdc_dbi => fdc_dbi, cpu_ce => cpu_ce, msx_reset => msx_reset, disk_on => disk_on,
            dl_download => dl_download, dl_index => dl_index, dl_wr => dl_wr, dl_addr => dl_addr, dl_data => dl_data,
            eject1 => '0', eject2 => '0', sys_rom_ok => sys_ok,
            cfg_speed => speed_v, cfg_ram => "100", cfg_mapper1 => std_logic_vector(to_unsigned(MAP1, 3)), cfg_mapper2 => std_logic_vector(to_unsigned(MAP2, 3)),
            cfg_disk => '1', cfg_music => '0',
            cfg_psg_vol => "100", cfg_scc_vol => "100", cfg_fm_vol => "100", cfg_tape_snd => '0',
            cfg_vmode => "00", cfg_vga => '1', cfg_lcd => '0', cfg_kbd => "00", cfg_v9958 => '0', cfg_ram30 => '0'
        );

    sdram : entity work.sdram_model
        generic map(
            INIT0_FILE => sel2(PRELOAD or VERIFY, SYS_PRE_HEX, SYS_HEX),   INIT0_BASE => 16#0600000#,
            INIT1_FILE => sel(PRELOAD or VERIFY, CART1_HEX), INIT1_BASE => 16#1000000#,
            INIT2_FILE => sel(PRELOAD or VERIFY, CART2_HEX), INIT2_BASE => 16#1800000#,
            CHECK_MODE => VERIFY )
        port map( clk => memclk, cs_n => cs_n, ras_n => ras_n, cas_n => cas_n, we_n => we_n,
                  ba => sdr_ba, a => sdr_a, dqm => sdr_dqm, dq => sdr_dq, refresh_count => rfsh_cnt, check => check );

    sdr_ba  <= ba1 & ba0;
    sdr_dqm <= udq & ldq;

    -- WD2793 stand-in: a register file
    process( clk21m )
        variable old_wr : std_logic := '0';
    begin
        if( rising_edge(clk21m) )then
            if( fdc_wr = '1' and old_wr = '0' )then
                fdc_regs( to_integer(unsigned(fdc_adr)) ) <= fdc_dbo;
            end if;
            old_wr := fdc_wr;
        end if;
    end process;
    fdc_dbi <= fdc_regs( to_integer(unsigned(fdc_adr)) ) when( fdc_cs = '1' )else X"FF";

    -- result monitor: CPU writes to SDRAM byte address 0x0000000-0x00000FF
    process( memclk )
        type rows_t is array (0 to 3) of std_logic_vector(12 downto 0);
        variable rows : rows_t := (others => (others => '0'));
        variable cmd  : std_logic_vector(3 downto 0);
        variable b    : integer;
        variable adr  : unsigned(24 downto 0);
        variable v    : std_logic_vector(7 downto 0);
        variable l    : line;
        variable dbg  : natural := 0;
    begin
        if( rising_edge(memclk) )then
            cmd := cs_n & ras_n & cas_n & we_n;
            b   := to_integer(unsigned(sdr_ba));
            if( cmd = "0011" )then
                rows(b) := sdr_a;
            elsif( (cmd = "0101" or cmd = "0100") and reset_n = '1' and dbg < DEBUG_N and sdr_ba /= "11" )then
                dbg := dbg + 1;
                adr := unsigned(rows(b)(12 downto 11)) & unsigned(sdr_ba) & unsigned(sdr_a(8 downto 0)) &
                       unsigned(rows(b)(10 downto 0)) & "0";
                if( cmd = "0101" )then write(l, string'("RD ")); else write(l, string'("WR ")); end if;
                write(l, hex2("0000000" & std_logic_vector(adr(24 downto 24))) & hex2(std_logic_vector(adr(23 downto 16))) & hex2(std_logic_vector(adr(15 downto 8))) & hex2(std_logic_vector(adr(7 downto 0))) & " dqm=" & std_logic'image(sdr_dqm(1)) & std_logic'image(sdr_dqm(0)) & " t=" & time'image(now));
                writeline(output, l);
            end if;
            if( cmd = "0100" and reset_n = '1' )then
                -- row = A24 A23 A11..A1, bank = A22 A21, column = A20..A12
                adr := unsigned(rows(b)(12 downto 11)) & unsigned(sdr_ba) & unsigned(sdr_a(8 downto 0)) &
                       unsigned(rows(b)(10 downto 0)) & "0";
                if( sdr_dqm = "10" )then            -- low byte written: A0 = 0
                    v := sdr_dq(7 downto 0);
                elsif( sdr_dqm = "01" )then
                    adr(0) := '1';
                    v := sdr_dq(15 downto 8);
                else
                    v := sdr_dq(7 downto 0);
                end if;
                if( adr < 256 )then
                    write(l, string'("RESULT C0") & hex2(std_logic_vector(adr(7 downto 0))) & " = " & hex2(v));
                    writeline(output, l);
                    if( adr = 255 and v = X"A5" )then
                        test_done <= true;
                    end if;
                end if;
            end if;
        end if;
    end process;

    stim : process
    begin
        reset_n <= '0';
        wait for INIT_WAIT_US * 1 us;               -- the IO controller starts the upload
        upload(SYS_HEX, 0, PRELOAD, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
        wait for 20 us;
        if( CART1_HEX'length > 0 and CART1_HEX /= "none" )then
            upload(CART1_HEX, 7, PRELOAD, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
            wait for 20 us;
        end if;
        if( CART2_HEX'length > 0 and CART2_HEX /= "none" )then
            upload(CART2_HEX, 8, PRELOAD, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
        end if;
        wait for 20 us;
        report "refresh commands during the upload: " & integer'image(rfsh_cnt);
        check <= '1';
        wait for 1 us;
        assert sys_ok = '1' report "system ROMs not flagged as present" severity error;
        reset_n <= '1';
        report "MSX reset released";
        for i in 1 to TIMEOUT_MS * 10 loop
            wait for 100 us;
            exit when test_done;
        end loop;
        if( test_done )then
            report "TEST PROGRAM FINISHED, disk_on=" & std_logic'image(disk_on) & " motor=" & std_logic'image(cmt_motor);
        else
            report "TIMEOUT" severity error;
        end if;
        done <= true;
        wait;
    end process;

end sim;
