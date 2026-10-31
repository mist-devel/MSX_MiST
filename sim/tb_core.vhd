--
-- tb_core.vhd - system testbench for msx2_core
--   * uploads the BIOS files the way the MiST IO controller does (data_io)
--   * runs the CPU from SDRAM (behavioural model)
--   * optional cartridge upload (index 7) to check the cartridge slot
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use std.textio.all;

entity tb_core is
    generic(
        MAIN_HEX    : string  := "roms/cbios_main_msx2_eu.hex";
        SUB_HEX     : string  := "roms/cbios_sub.hex";
        CART_HEX    : string  := "";
        BYTE_GAP    : natural := 6;             -- clk21m cycles between two uploaded bytes
        RUN_MS      : natural := 80
    );
end tb_core;

architecture sim of tb_core is

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
    signal cmt_out, cmt_motor, dac : std_logic;

    signal done : boolean := false;

    procedure upload( constant fname : in string; constant idx : in natural;
                      signal dl_download : out std_logic; signal dl_index : out std_logic_vector;
                      signal dl_wr : out std_logic; signal dl_addr : out std_logic_vector;
                      signal dl_data : out std_logic_vector; signal clk : in std_logic ) is
        file     f      : text open read_mode is fname;
        variable l      : line;
        variable v      : std_logic_vector(7 downto 0);
        variable addr   : natural := 0;
        variable good   : boolean;
        variable c      : character;
        variable n      : integer;
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
            dl_addr <= std_logic_vector(to_unsigned(addr, 27));
            dl_data <= std_logic_vector(to_unsigned(n, 8));
            dl_wr   <= '1';
            wait until rising_edge(clk);
            dl_wr   <= '0';
            for i in 2 to BYTE_GAP loop wait until rising_edge(clk); end loop;
            addr := addr + 1;
        end loop;
        for i in 1 to 20 loop wait until rising_edge(clk); end loop;
        dl_download <= '0';
        report "uploaded " & fname & " (" & integer'image(addr) & " bytes) to index " & integer'image(idx);
    end procedure;

begin

    -- clocks: clk21m = memclk / 4, phase aligned like the MiST PLL outputs
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
        port map(
            clk21m => clk21m, memclk => memclk, reset_n => reset_n,
            pMemCke => cke, pMemCs_n => cs_n, pMemRas_n => ras_n, pMemCas_n => cas_n, pMemWe_n => we_n,
            pMemUdq => udq, pMemLdq => ldq, pMemBa1 => ba1, pMemBa0 => ba0, pMemAdr => sdr_a, pMemDat => sdr_dq,
            pPs2Clk => ps2c, pPs2Dat => ps2d,
            pJoyA => joya, pStrA => open, pJoyB => joyb, pStrB => open,
            pVideoR => vr, pVideoG => vg, pVideoB => vb, pVideoHS_n => hs, pVideoVS_n => vs, pVideoBlank => blank,
            audio_o => audio, pDacOut => dac,
            CmtIn => '0', CmtOut => cmt_out, CmtMotor => cmt_motor,
            iRTC => (others => '0'),
            fdc_cs => fdc_cs, fdc_rd => fdc_rd, fdc_wr => fdc_wr, fdc_adr => fdc_adr, fdc_dbo => fdc_dbo,
            fdc_dbi => X"FF", cpu_ce => cpu_ce, msx_reset => msx_reset, disk_on => disk_on,
            dl_download => dl_download, dl_index => dl_index, dl_wr => dl_wr, dl_addr => dl_addr, dl_data => dl_data,
            eject1 => '0', eject2 => '0', sys_rom_ok => sys_ok,
            cfg_speed => "000", cfg_ram => "100", cfg_mapper1 => "000", cfg_mapper2 => "000",
            cfg_disk => '0', cfg_music => '0',
            cfg_psg_vol => "100", cfg_scc_vol => "100", cfg_fm_vol => "100", cfg_tape_snd => '0',
            cfg_vmode => "00", cfg_vga => '1', cfg_lcd => '0', cfg_kbd => "00", cfg_v9958 => '0', cfg_ram30 => '0'
        );

    sdram : entity work.sdram_model
        port map( clk => memclk, cs_n => cs_n, ras_n => ras_n, cas_n => cas_n, we_n => we_n,
                  ba => sdr_ba, a => sdr_a, dqm => sdr_dqm, dq => sdr_dq, refresh_count => rfsh_cnt );

    sdr_ba  <= ba1 & ba0;
    sdr_dqm <= udq & ldq;

    stim : process
    begin
        reset_n <= '0';
        wait for 7 ms;                              -- SDRAM initialisation (about 6 ms)
        upload(MAIN_HEX, 0, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
        wait for 100 us;
        upload(SUB_HEX, 1, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
        if( CART_HEX'length > 0 )then
            wait for 100 us;
            upload(CART_HEX, 7, dl_download, dl_index, dl_wr, dl_addr, dl_data, clk21m);
        end if;
        wait for 200 us;
        report "refresh commands so far: " & integer'image(rfsh_cnt);
        assert sys_ok = '1' report "system ROMs not flagged as present" severity error;
        reset_n <= '1';
        report "MSX reset released";
        wait for RUN_MS * 1 ms;
        report "end of simulation, refresh commands: " & integer'image(rfsh_cnt);
        done <= true;
        wait;
    end process;

end sim;
