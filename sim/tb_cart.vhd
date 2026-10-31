--
-- tb_cart.vhd - unit test of cart_slot.vhd (address translation of the mappers)
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_cart is
end tb_cart;

architecture sim of tb_cart is
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal req      : std_logic := '0';
    signal ack      : std_logic;
    signal wrt      : std_logic := '0';
    signal adr      : std_logic_vector(15 downto 0) := (others => '0');
    signal dbi      : std_logic_vector(7 downto 0);
    signal dbo      : std_logic_vector(7 downto 0) := (others => '0');
    signal ramreq   : std_logic;
    signal ramadr   : std_logic_vector(22 downto 0);
    signal mapper   : std_logic_vector(2 downto 0) := "000";
    signal mask     : std_logic_vector(22 downto 0) := (others => '1');
    signal last     : std_logic_vector(22 downto 0) := (others => '1');
    signal base     : std_logic_vector(1 downto 0) := "01";
    signal wave     : std_logic_vector(14 downto 0);
    signal done     : boolean := false;
begin
    clk <= not clk after 23.28 ns when not done;

    dut : entity work.cart_slot
        port map( clk21m => clk, reset => reset, clkena => '1', req => req, ack => ack, wrt => wrt, adr => adr,
                  dbi => dbi, dbo => dbo, ramreq => ramreq, ramadr => ramadr, ramdbi => X"5A",
                  mapper => mapper, rom_mask => mask, rom_last => last, plain_base => base, wave => wave );

    stim : process
        variable errs : natural := 0;

        procedure setup( m : std_logic_vector(2 downto 0); size : natural; b : std_logic_vector(1 downto 0) ) is
            variable msk : natural := 8191;
        begin
            while msk < size - 1 loop msk := msk * 2 + 1; end loop;
            mapper <= m; base <= b;
            mask <= std_logic_vector(to_unsigned(msk, 23));
            last <= std_logic_vector(to_unsigned(size - 1, 23));
            reset <= '1';
            wait until rising_edge(clk); wait until rising_edge(clk);
            reset <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure wr( a : natural; v : natural ) is
        begin
            adr <= std_logic_vector(to_unsigned(a, 16)); dbo <= std_logic_vector(to_unsigned(v, 8));
            wrt <= '1'; req <= '1';
            wait until rising_edge(clk);
            req <= '0'; wrt <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- read: expect an SDRAM read at offset "off", or no ROM (-1)
        procedure rd( what : string; a : natural; off : integer ) is
        begin
            adr <= std_logic_vector(to_unsigned(a, 16)); wrt <= '0'; req <= '1';
            wait for 1 ns;
            if( off < 0 )then
                if( ramreq = '1' or dbi /= X"FF" )then
                    report "FAIL " & what & ": expected empty (FFh)" severity error; errs := errs + 1;
                else
                    report "ok   " & what & ": empty";
                end if;
            else
                if( ramreq /= '1' or to_integer(unsigned(ramadr)) /= off )then
                    report "FAIL " & what & ": ramreq=" & std_logic'image(ramreq) & " offset " &
                           integer'image(to_integer(unsigned(ramadr))) & " expected " & integer'image(off) severity error;
                    errs := errs + 1;
                else
                    report "ok   " & what;
                end if;
            end if;
            wait until rising_edge(clk);
            req <= '0';
            wait until rising_edge(clk);
        end procedure;
    begin
        wait for 200 ns;

        -- plain 8K ROM at 4000h: mirrored at 6000h, nothing at 8000h
        setup("001", 8192, "01");
        rd("8K 4000h", 16#4000#, 0);
        rd("8K 6005h mirror", 16#6005#, 5);
        rd("8K 8000h", 16#8000#, -1);
        rd("8K 0000h", 16#0000#, -1);
        -- plain 16K at 8000h
        setup("001", 16384, "10");
        rd("16K@8000 8000h", 16#8000#, 0);
        rd("16K@8000 BFFFh", 16#BFFF#, 16#3FFF#);
        rd("16K@8000 4000h", 16#4000#, -1);
        rd("16K@8000 C000h", 16#C000#, -1);
        -- plain 32K
        setup("001", 32768, "01");
        rd("32K 4000h", 16#4000#, 0);
        rd("32K 9234h", 16#9234#, 16#5234#);
        rd("32K C000h", 16#C000#, -1);
        -- plain 48K at 0000h
        setup("001", 49152, "00");
        rd("48K 0000h", 16#0000#, 0);
        rd("48K A000h", 16#A000#, 16#A000#);
        rd("48K C000h", 16#C000#, -1);
        -- writes to a plain ROM are ignored
        wr(16#4000#, 16#77#);
        rd("48K 4000h after write", 16#4000#, 16#4000#);

        -- Konami (no SCC) 128K: 4000h fixed to bank 0
        setup("011", 131072, "01");
        rd("Konami 4000h", 16#4000#, 0);
        rd("Konami 6000h", 16#6000#, 16#2000#);
        wr(16#6000#, 5);  rd("Konami bank1=5", 16#6001#, 5*8192 + 1);
        wr(16#8000#, 7);  rd("Konami bank2=7", 16#8000#, 7*8192);
        wr(16#A123#, 9);  rd("Konami bank3=9", 16#A000#, 9*8192);
        wr(16#4000#, 3);  rd("Konami 4000h still bank 0", 16#4000#, 0);
        wr(16#6000#, 16#13#); rd("Konami bank 13h masked (128K)", 16#6000#, 3*8192);

        -- ASCII 8K 256K: all banks 0 at reset
        setup("100", 262144, "01");
        rd("ASCII8 4000h", 16#4000#, 0);
        rd("ASCII8 A000h", 16#A000#, 0);
        wr(16#6000#, 1);  rd("ASCII8 6000h->bank0", 16#4000#, 8192);
        wr(16#6800#, 2);  rd("ASCII8 6800h->bank1", 16#6000#, 2*8192);
        wr(16#7000#, 3);  rd("ASCII8 7000h->bank2", 16#8000#, 3*8192);
        wr(16#7800#, 31); rd("ASCII8 7800h->bank3", 16#A000#, 31*8192);
        rd("ASCII8 0000h", 16#0000#, -1);

        -- ASCII 16K 256K
        setup("101", 262144, "01");
        rd("ASCII16 8000h", 16#8000#, 0);
        wr(16#6000#, 2);  rd("ASCII16 6000h->4000h", 16#4000#, 2*16384);
        wr(16#7000#, 15); rd("ASCII16 7000h->8000h", 16#BFFF#, 15*16384 + 16#3FFF#);
        wr(16#7800#, 3);  rd("ASCII16 7800h no effect", 16#8000#, 15*16384);

        -- Konami SCC 512K
        setup("010", 524288, "01");
        rd("SCC 4000h", 16#4000#, 0);
        rd("SCC A000h", 16#A000#, 3*8192);
        wr(16#5000#, 40); rd("SCC 5000h->bank0", 16#4000#, 40*8192);
        wr(16#5800#, 41); rd("SCC 5800h no effect", 16#4000#, 40*8192);
        wr(16#B000#, 63); rd("SCC B000h->bank3", 16#A000#, 63*8192);

        if( errs = 0 )then
            report "CART TEST PASSED";
        else
            report "CART TEST FAILED: " & integer'image(errs) & " errors" severity error;
        end if;
        done <= true;
        wait;
    end process;
end sim;
