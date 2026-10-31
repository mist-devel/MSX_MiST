--
-- tb_loader.vhd - unit test of rom_loader.vhd
--   mapper detection, ROM size/mask, start page of plain ROMs,
--   system ROM placement (combined image, separate files, OCM-BIOS.DAT)
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_loader is
end tb_loader;

architecture sim of tb_loader is
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
    signal c1p, c2p : std_logic;
    signal c1m, c2m : std_logic_vector(2 downto 0);
    signal c1mask, c1last, c2mask, c2last : std_logic_vector(22 downto 0);
    signal c1b, c2b : std_logic_vector(1 downto 0);
    signal done     : boolean := false;
    signal errors   : natural := 0;

    -- last SDRAM write seen for a given address window (checked by the stimulus)
    type wlog_t is array (0 to 15) of std_logic_vector(32 downto 0);
    signal last_wr  : std_logic_vector(32 downto 0) := (others => '0');
    signal wr_count : natural := 0;
begin
    clk <= not clk after 23.28 ns when not done;

    dut : entity work.rom_loader
        port map( clk21m => clk, dl_download => dl, dl_index => idx, dl_wr => wr, dl_addr => addr, dl_data => data,
                  wr_req => wr_req, wr_adr => wr_adr, wr_dat => wr_dat,
                  rom_main_ok => m_ok, rom_sub_ok => s_ok, rom_disk_ok => d_ok, rom_music_ok => mu_ok,
                  eject1 => '0', eject2 => '0',
                  cart1_present => c1p, cart1_mapper => c1m, cart1_mask => c1mask, cart1_last => c1last, cart1_base => c1b,
                  cart2_present => c2p, cart2_mapper => c2m, cart2_mask => c2mask, cart2_last => c2last, cart2_base => c2b );

    process( clk )
    begin
        if( rising_edge(clk) and wr_req = '1' )then
            last_wr  <= wr_adr & wr_dat;
            wr_count <= wr_count + 1;
        end if;
    end process;

    stim : process
        type kind_t is (K_ZERO, K_SCC, K_K4, K_A8, K_A16, K_AB4000, K_AB8000, K_AB0, K_ADR);
        variable errs : natural := 0;

        -- byte of a synthetic ROM
        function rom_byte( k : kind_t; a : natural ) return natural is
        begin
            case k is
                when K_SCC  => if( a mod 64 = 0 )then return 16#32#; elsif( a mod 64 = 1 )then return 16#00#; elsif( a mod 64 = 2 )then return 16#90#; end if;
                when K_K4   => if( a mod 64 = 0 )then return 16#32#; elsif( a mod 64 = 1 )then return 16#00#; elsif( a mod 64 = 2 )then return 16#A0#; end if;
                when K_A8   => if( a mod 64 = 0 )then return 16#32#; elsif( a mod 64 = 1 )then return 16#00#; elsif( a mod 64 = 2 )then return 16#68#; end if;
                when K_A16  => if( a mod 64 = 0 )then return 16#32#; elsif( a mod 64 = 1 )then return 16#FF#; elsif( a mod 64 = 2 )then return 16#77#; end if;
                when K_AB4000 => if( a = 0 )then return 16#41#; elsif( a = 1 )then return 16#42#; elsif( a = 2 )then return 16#10#; elsif( a = 3 )then return 16#40#; end if;
                when K_AB8000 => if( a = 0 )then return 16#41#; elsif( a = 1 )then return 16#42#; elsif( a = 2 )then return 16#10#; elsif( a = 3 )then return 16#80#; end if;
                when K_AB0  => if( a = 16#4000# )then return 16#41#; elsif( a = 16#4001# )then return 16#42#; elsif( a = 16#4002# )then return 16#10#; elsif( a = 16#4003# )then return 16#40#; end if;
                when K_ADR  => return (a / 16#4000#) mod 256;      -- 16K block number
                when others => null;
            end case;
            return 16#C9#;
        end function;

        procedure send( k : kind_t; size : natural; index : natural; step : natural := 1 ) is
            variable a : natural := 0;
        begin
            idx <= std_logic_vector(to_unsigned(index, 8));
            dl  <= '1';
            wait until rising_edge(clk); wait until rising_edge(clk);
            while a < size loop
                addr <= std_logic_vector(to_unsigned(a, 27));
                data <= std_logic_vector(to_unsigned(rom_byte(k, a), 8));
                wr   <= '1';
                wait until rising_edge(clk);
                wr   <= '0';
                wait until rising_edge(clk);
                a := a + step;
            end loop;
            wait until rising_edge(clk);
            dl <= '0';
            for i in 1 to 4 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure check( what : string; got, exp : std_logic_vector ) is
        begin
            if( got /= exp )then
                report "FAIL " & what & ": got " & integer'image(to_integer(unsigned(got))) & " expected " & integer'image(to_integer(unsigned(exp))) severity error;
                errs := errs + 1;
            else
                report "ok   " & what;
            end if;
        end procedure;
        procedure check( what : string; got, exp : std_logic ) is
        begin
            if( got /= exp )then
                report "FAIL " & what severity error;
                errs := errs + 1;
            else
                report "ok   " & what;
            end if;
        end procedure;

    begin
        wait for 1 us;

        -- cartridges: mapper detection
        send(K_SCC, 131072, 7);
        check("SCC 128K: present", c1p, '1');
        check("SCC 128K: mapper", c1m, "010");
        check("SCC 128K: mask", c1mask, std_logic_vector(to_unsigned(16#1FFFF#, 23)));
        check("SCC 128K: last", c1last, std_logic_vector(to_unsigned(16#1FFFF#, 23)));
        check("SCC 128K: last SDRAM address", last_wr(32 downto 8), std_logic_vector(to_unsigned(16#1000000# + 16#1FFFF#, 25)));
        send(K_K4, 262144, 8);
        check("Konami 256K: mapper", c2m, "011");
        check("Konami 256K in slot 2: address", last_wr(32 downto 8), std_logic_vector(to_unsigned(16#1800000# + 16#3FFFF#, 25)));
        send(K_A8, 196608, 7);
        check("ASCII8 192K: mapper", c1m, "100");
        check("ASCII8 192K: mask", c1mask, std_logic_vector(to_unsigned(16#3FFFF#, 23)));
        send(K_A16, 131072, 7);
        check("ASCII16 128K: mapper", c1m, "101");
        send(K_ZERO, 131072, 7);
        check("no pattern 128K: Generic 8K", c1m, "110");

        -- plain ROMs
        send(K_AB4000, 16384, 7);
        check("16K at 4000h: mapper", c1m, "001");
        check("16K at 4000h: base", c1b, "01");
        send(K_AB8000, 16384, 7);
        check("16K with INIT at 8xxxh: base", c1b, "10");
        send(K_AB8000, 32768, 7);
        check("32K with INIT at 8xxxh: base stays 4000h", c1b, "01");
        send(K_AB0, 49152, 7);
        check("48K with header at 4000h: base 0000h", c1b, "00");
        send(K_AB4000, 8192, 8);
        check("8K: mask", c2mask, std_logic_vector(to_unsigned(16#1FFF#, 23)));
        check("8K: last", c2last, std_logic_vector(to_unsigned(16#1FFF#, 23)));

        -- system ROMs: combined MAIN+SUB+DISK
        send(K_ADR, 65536, 0, 64);
        check("combined: main", m_ok, '1');
        check("combined: sub", s_ok, '1');
        check("combined: disk", d_ok, '1');
        check("combined: no music", mu_ok, '0');
        -- separate MSX-MUSIC file (index 3)
        send(K_ADR, 16384, 3, 64);
        check("R03: music", mu_ok, '1');
        check("R03: address", last_wr(32 downto 8), std_logic_vector(to_unsigned(16#0610000# + 16384 - 64, 25)));

        -- OCM-BIOS.DAT (512K): main 20000h, music 2C000h, sub 30000h
        send(K_ADR, 524288, 0, 1024);
        check("OCM: main", m_ok, '1');
        check("OCM: sub", s_ok, '1');
        check("OCM: music", mu_ok, '1');
        check("OCM: no disk (MegaSD area ignored)", d_ok, '0');
        -- check where the blocks went: write a few bytes and look at the SDRAM address
        idx <= X"00"; dl <= '1'; wait until rising_edge(clk); wait until rising_edge(clk);
        addr <= std_logic_vector(to_unsigned(16#20000#, 27)); data <= X"20"; wr <= '1'; wait until rising_edge(clk); wr <= '0'; wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        check("OCM: 20000h -> MAIN 0600000h", last_wr, std_logic_vector(to_unsigned(16#0600000#, 25)) & X"20");
        addr <= std_logic_vector(to_unsigned(16#30005#, 27)); data <= X"30"; wr <= '1'; wait until rising_edge(clk); wr <= '0'; wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        check("OCM: 30005h -> SUB 0608005h", last_wr, std_logic_vector(to_unsigned(16#0608005#, 25)) & X"30");
        addr <= std_logic_vector(to_unsigned(16#2C001#, 27)); data <= X"2C"; wr <= '1'; wait until rising_edge(clk); wr <= '0'; wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        check("OCM: 2C001h -> MUSIC 0610001h", last_wr, std_logic_vector(to_unsigned(16#0610001#, 25)) & X"2C");
        addr <= std_logic_vector(to_unsigned(16#28000#, 27)); data <= X"28"; wr <= '1'; wait until rising_edge(clk); wr <= '0'; wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        check("OCM: 28000h (XBASIC) not written", last_wr, std_logic_vector(to_unsigned(16#0610001#, 25)) & X"2C");
        addr <= std_logic_vector(to_unsigned(16#40000#, 27)); data <= X"40"; wr <= '1'; wait until rising_edge(clk); wr <= '0'; wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        check("OCM: 40000h (Kanji) not written", last_wr, std_logic_vector(to_unsigned(16#0610001#, 25)) & X"2C");
        dl <= '0'; wait for 1 us;
        -- disk ROM as R02 after the OCM file
        send(K_ADR, 16384, 2, 64);
        check("R02 after OCM: disk", d_ok, '1');

        if( errs = 0 )then
            report "LOADER TEST PASSED";
        else
            report "LOADER TEST FAILED: " & integer'image(errs) & " errors" severity error;
        end if;
        done <= true;
        wait;
    end process;
end sim;
