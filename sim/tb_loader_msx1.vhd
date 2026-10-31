--
-- tb_loader_msx1.vhd - rom_loader with the MSX1 file layout
--   MSX1.ROM = MAIN(32K) + DISK(16K) + MSX-MUSIC(16K), MSX1.R01 = DISK, MSX1.R02 = MSX-MUSIC
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_loader_msx1 is
end tb_loader_msx1;

architecture sim of tb_loader_msx1 is
    signal clk      : std_logic := '0';
    signal dl       : std_logic := '0';
    signal idx      : std_logic_vector(7 downto 0) := (others => '0');
    signal wr       : std_logic := '0';
    signal addr     : std_logic_vector(26 downto 0) := (others => '0');
    signal data     : std_logic_vector(7 downto 0) := (others => '0');
    signal wr_req   : std_logic;
    signal wr_adr   : std_logic_vector(24 downto 0);
    signal wr_dat   : std_logic_vector(7 downto 0);
    signal m_ok, s_ok, d_ok, mu_ok : std_logic;
    signal done     : boolean := false;
    signal last_wr  : std_logic_vector(24 downto 0) := (others => '0');
    signal nwr      : natural := 0;
begin
    clk <= not clk after 23.28 ns when not done;

    dut : entity work.rom_loader
        generic map( MSX1 => 1 )
        port map( clk21m => clk, dl_download => dl, dl_index => idx, dl_wr => wr, dl_addr => addr, dl_data => data,
                  wr_req => wr_req, wr_adr => wr_adr, wr_dat => wr_dat,
                  rom_main_ok => m_ok, rom_sub_ok => s_ok, rom_disk_ok => d_ok, rom_music_ok => mu_ok,
                  eject1 => '0', eject2 => '0',
                  cart1_present => open, cart1_mapper => open, cart1_mask => open, cart1_last => open, cart1_base => open,
                  cart2_present => open, cart2_mapper => open, cart2_mask => open, cart2_last => open, cart2_base => open );

    process( clk ) begin
        if( rising_edge(clk) and wr_req = '1' )then last_wr <= wr_adr; nwr <= nwr + 1; end if;
    end process;

    stim : process
        variable errs : natural := 0;
        procedure one( index : natural; a : natural; exp : integer; what : string ) is
            variable n0 : natural;
        begin
            idx <= std_logic_vector(to_unsigned(index, 8)); dl <= '1';
            wait until rising_edge(clk); wait until rising_edge(clk);
            n0 := nwr;
            addr <= std_logic_vector(to_unsigned(a, 27)); data <= X"5A"; wr <= '1';
            wait until rising_edge(clk); wr <= '0';
            for i in 1 to 4 loop wait until rising_edge(clk); end loop;
            dl <= '0';
            for i in 1 to 4 loop wait until rising_edge(clk); end loop;
            if( exp < 0 )then
                if( nwr /= n0 )then report "FAIL " & what & ": written" severity error; errs := errs + 1;
                else report "ok   " & what & ": not written"; end if;
            elsif( nwr = n0 or to_integer(unsigned(last_wr)) /= exp )then
                report "FAIL " & what & ": address " & integer'image(to_integer(unsigned(last_wr))) severity error; errs := errs + 1;
            else
                report "ok   " & what;
            end if;
        end procedure;
    begin
        wait for 1 us;
        one(0, 16#00000#, 16#0600000#, "MSX1.ROM 0000h -> MAIN");
        one(0, 16#07FFF#, 16#0607FFF#, "MSX1.ROM 7FFFh -> MAIN");
        one(0, 16#08000#, 16#060C000#, "MSX1.ROM 8000h -> DISK");
        one(0, 16#0C001#, 16#0610001#, "MSX1.ROM C001h -> MSX-MUSIC");
        one(0, 16#10000#, -1,          "MSX1.ROM 10000h ignored");
        one(0, 16#20000#, -1,          "MSX1.ROM 20000h ignored (no OCM layout)");
        one(1, 16#00010#, 16#060C010#, "MSX1.R01 -> DISK");
        one(2, 16#00010#, 16#0610010#, "MSX1.R02 -> MSX-MUSIC");
        if( errs = 0 )then report "LOADER MSX1 TEST PASSED"; else report "LOADER MSX1 TEST FAILED" severity error; end if;
        done <= true;
        wait;
    end process;
end sim;
